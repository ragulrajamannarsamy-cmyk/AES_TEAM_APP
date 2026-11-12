import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/app_user.dart';
import '../models/attendance.dart';
import '../models/leave_request.dart';
import '../models/payslip.dart';
import '../models/requests.dart';
import '../models/vehicle_log.dart';
import '../util.dart';

class PayrollService {
  static final _db = FirebaseFirestore.instance;
  static final _col = _db.collection('payroll');

  /// Admin: all payslips for a month.
  static Stream<List<Payslip>> watchMonth(String month) => _col
      .where('month', isEqualTo: month)
      .snapshots()
      .map((q) => q.docs.map(Payslip.fromDoc).toList()
        ..sort((a, b) => a.name.compareTo(b.name)));

  /// Worker: own approved payslips, newest first.
  static Stream<List<Payslip>> watchMine(String phone) => _col
      .where('phone', isEqualTo: phone)
      .where('status', isEqualTo: 'approved')
      .snapshots()
      .map((q) => q.docs.map(Payslip.fromDoc).toList()
        ..sort((a, b) => b.month.compareTo(a.month)));

  static Future<void> save(Payslip p) => _col.doc(p.docId).set(p.toMap());

  static Future<void> setStatus(Payslip p, String status, String by) =>
      _col.doc(p.docId).update({
        'status': status,
        if (status == 'approved') 'approvedBy': by,
        if (status == 'approved') 'approvedAt': FieldValue.serverTimestamp(),
      });

  /// Builds draft payslips for every active worker and driver for [month]
  /// (yyyy-MM). Approved payslips are never overwritten. Returns the number
  /// of drafts written.
  ///
  /// Days present = complete days (In + Out) + approved paid-leave days.
  /// Paid leave = approved planned leave, or approved medical/emergency
  /// leave with a doctor certificate. Everything else is loss of pay.
  static Future<int> calculate(String month) async {
    final start = '$month-01', end = '$month-31';

    final users = (await _db.collection('users').get())
        .docs
        .map(AppUser.fromDoc)
        .where((u) => u.active && !u.isAdmin)
        .toList();
    final attendance = (await _db
            .collection('attendance')
            .where('date', isGreaterThanOrEqualTo: start)
            .where('date', isLessThanOrEqualTo: end)
            .get())
        .docs
        .map(AttendanceDay.fromDoc)
        .toList();
    final leaves = (await _db
            .collection('leaves')
            .where('status', isEqualTo: 'approved')
            .get())
        .docs
        .map(LeaveRequest.fromDoc)
        .toList();
    final logs = (await _db
            .collection('vehicleLogs')
            .where('date', isGreaterThanOrEqualTo: start)
            .where('date', isLessThanOrEqualTo: end)
            .get())
        .docs
        .map(VehicleLog.fromDoc)
        .toList();
    final advances = (await _db
            .collection('advances')
            .where('status', isEqualTo: 'approved')
            .get())
        .docs
        .map(Advance.fromDoc)
        .toList();
    final carry = (await _db
            .collection('carryForwards')
            .where('month', isEqualTo: month)
            .get())
        .docs
        .map(CarryForward.fromDoc)
        .where((c) => c.status == ReqStatus.approved)
        .toList();
    final approvedSlips = (await _col.where('status', isEqualTo: 'approved').get())
        .docs
        .map(Payslip.fromDoc)
        .toList();
    final locked = {
      for (final p in approvedSlips.where((p) => p.month == month)) p.phone
    };

    var batch = _db.batch();
    var inBatch = 0, written = 0;

    for (final u in users) {
      if (locked.contains(u.phone)) continue;

      final mine = attendance.where((a) => a.phone == u.phone).toList();
      final completeDates =
          mine.where((a) => a.isComplete).map((a) => a.date).toSet();
      final incomplete =
          mine.where((a) => !a.isComplete && a.inPunch != null).length;

      final leaveDates = <String>{};
      for (final l in leaves.where((l) =>
          l.phone == u.phone &&
          (l.type == LeaveType.planned || (l.certUrl?.isNotEmpty ?? false)))) {
        for (var d = DateTime(l.from.year, l.from.month, l.from.day);
            !d.isAfter(l.to);
            d = DateTime(d.year, d.month, d.day + 1)) {
          final k = dayFmt.format(d);
          if (k.startsWith(month) && !completeDates.contains(k)) {
            leaveDates.add(k);
          }
        }
      }

      final days = (completeDates.length + leaveDates.length).toDouble();
      final km = logs
          .where((l) => l.phone == u.phone)
          .fold<double>(0, (s, l) => s + l.km);

      final taken = advances
          .where((a) => a.phone == u.phone)
          .fold<double>(0, (s, a) => s + a.approvedAmount);
      final recoveredBefore = approvedSlips
          .where((p) => p.phone == u.phone && p.month != month)
          .fold<double>(0, (s, p) => s + p.advanceRecovery);
      final outstanding = math.max(0.0, taken - recoveredBefore);
      final deferred = math.min(
          outstanding,
          carry
              .where((c) => c.phone == u.phone)
              .fold<double>(0, (s, c) => s + c.amount));

      final pfEsi = days > 0 ? u.pfEsi : 0.0;
      final gross = days * u.perDayRate;
      final kmRent = km * u.perKmRate;
      final recovery = math.min(outstanding - deferred,
          Payslip.maxRecovery(gross, kmRent, pfEsi));

      final slip = Payslip(
        phone: u.phone,
        name: u.name,
        month: month,
        completeDays: completeDates.length,
        incompleteDays: incomplete,
        paidLeaveDays: leaveDates.length,
        daysPresent: days,
        km: km,
        advanceRecovery: math.max(0.0, recovery),
        adjustment: 0,
        adjustmentNote: '',
        perDayRate: u.perDayRate,
        perKmRate: u.perKmRate,
        pfEsi: pfEsi,
        advanceOutstanding: outstanding,
        carriedForward: deferred,
        status: 'draft',
      );
      batch.set(_col.doc(slip.docId), slip.toMap());
      written++;
      if (++inBatch == 400) {
        await batch.commit();
        batch = _db.batch();
        inBatch = 0;
      }
    }
    if (inBatch > 0) await batch.commit();
    return written;
  }

  static Future<void> approveAll(List<Payslip> slips, String by) async {
    final batch = _db.batch();
    for (final p in slips.where((p) => !p.approved)) {
      batch.update(_col.doc(p.docId), {
        'status': 'approved',
        'approvedBy': by,
        'approvedAt': FieldValue.serverTimestamp(),
      });
    }
    await batch.commit();
  }
}
