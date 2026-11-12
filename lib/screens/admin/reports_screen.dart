import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../models/app_user.dart';
import '../../models/attendance.dart';
import '../../models/leave_request.dart';
import '../../models/requests.dart';
import '../../services/bank_service.dart';
import '../../services/vehicle_service.dart';
import '../../util.dart';
import '../../widgets/common.dart';

/// Downloads for owner/manager. Each opens the share sheet with a CSV that
/// opens in Excel (WhatsApp, Gmail, Drive, Save to Files).
class ReportsScreen extends StatefulWidget {
  const ReportsScreen({super.key});

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  static final _db = FirebaseFirestore.instance;
  String _month = prevMonthKey();
  String? _busy;

  Future<List<AppUser>> _staff() async => (await _db.collection('users').get())
      .docs
      .map(AppUser.fromDoc)
      .where((u) => !u.isAdmin)
      .toList()
    ..sort((a, b) => a.name.compareTo(b.name));

  Future<List<AttendanceDay>> _attendance() async => (await _db
          .collection('attendance')
          .where('date', isGreaterThanOrEqualTo: '$_month-01')
          .where('date', isLessThanOrEqualTo: '$_month-31')
          .get())
      .docs
      .map(AttendanceDay.fromDoc)
      .toList();

  Future<void> _run(String key, Future<void> Function() job) async {
    setState(() => _busy = key);
    try {
      await job();
    } catch (e) {
      if (mounted) toast(context, 'Report failed: $e', error: true);
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  /// One row per person: present / incomplete / leave days.
  Future<void> _attendanceSummary() async {
    final staff = await _staff();
    final att = await _attendance();
    final leaves = (await _db
            .collection('leaves')
            .where('status', isEqualTo: 'approved')
            .get())
        .docs
        .map(LeaveRequest.fromDoc)
        .toList();
    final first = DateTime.parse('$_month-01');
    final daysInMonth = DateTime(first.year, first.month + 1, 0).day;

    int leaveDays(String phone) {
      var n = 0;
      for (final l in leaves.where((l) => l.phone == phone)) {
        for (var d = l.from;
            !d.isAfter(l.to);
            d = DateTime(d.year, d.month, d.day + 1)) {
          if (dayFmt.format(d).startsWith(_month)) n++;
        }
      }
      return n;
    }

    await shareCsv('attendance_summary_$_month.csv', [
      ['Name', 'Mobile', 'Role', 'Full days (In+Out)', 'Incomplete days',
        'Days with site visit', 'Approved leave days', 'Days in month'],
      for (final u in staff)
        () {
          final mine = att.where((a) => a.phone == u.phone);
          return [
            u.name,
            u.phone,
            roleLabels[u.role],
            mine.where((a) => a.isComplete).length,
            mine.where((a) => !a.isComplete && a.inPunch != null).length,
            mine.where((a) => a.siteVisits.isNotEmpty).length,
            leaveDays(u.phone),
            daysInMonth,
          ];
        }(),
    ]);
  }

  /// Every punch: time, site, GPS, selfie link.
  Future<void> _attendanceDetail() async {
    final att = await _attendance()
      ..sort((a, b) => '${a.date}${a.phone}'.compareTo('${b.date}${b.phone}'));
    final names = {for (final u in await _staff()) u.phone: u.name};
    List<Object?> row(AttendanceDay a, String kind, Punch p) => [
          a.date,
          names[a.phone] ?? a.phone,
          kind,
          timeFmt.format(p.time),
          p.siteName,
          p.lat.toStringAsFixed(6),
          p.lng.toStringAsFixed(6),
          p.accuracyM.round(),
          p.photoUrl,
        ];
    await shareCsv('attendance_detail_$_month.csv', [
      ['Date', 'Name', 'Type', 'Time', 'Site', 'Latitude', 'Longitude',
        'Accuracy (m)', 'Selfie link'],
      for (final a in att) ...[
        if (a.inPunch != null) row(a, 'In', a.inPunch!),
        for (final v in a.siteVisits) row(a, 'Site', v),
        if (a.outPunch != null) row(a, 'Out', a.outPunch!),
      ],
    ]);
  }

  Future<void> _vehicleLog() async {
    final logs = await VehicleService.allForMonth(_month)
      ..sort((a, b) => '${a.name}${a.date}'.compareTo('${b.name}${b.date}'));
    final rates = {for (final u in await _staff()) u.phone: u.perKmRate};
    final total = logs.fold<double>(0, (s, l) => s + l.km);
    await shareCsv('vehicle_log_$_month.csv', [
      ['Date', 'Driver', 'Vehicle', 'Start km', 'End km', 'Km',
        'Rate/km', 'Rent (Rs)', 'Start photo', 'End photo'],
      for (final l in logs)
        [
          l.date, l.name, l.vehicleNo, l.startKm, l.endKm ?? 'NOT CLOSED',
          l.km, rates[l.phone] ?? 0, (l.km * (rates[l.phone] ?? 0)).round(),
          l.startPhoto, l.endPhoto ?? '',
        ],
      [],
      ['', 'TOTAL', '', '', '', total, '', '', '', ''],
    ]);
  }

  /// Outstanding advance per person (all time).
  Future<void> _advances() async {
    final adv = (await _db
            .collection('advances')
            .where('status', isEqualTo: 'approved')
            .get())
        .docs
        .map(Advance.fromDoc)
        .toList();
    final slips = (await _db
            .collection('payroll')
            .where('status', isEqualTo: 'approved')
            .get())
        .docs
        .map((d) => d.data())
        .toList();
    final staff = await _staff();
    final rows = <List<Object?>>[];
    for (final u in staff) {
      final taken = adv
          .where((a) => a.phone == u.phone)
          .fold<double>(0, (s, a) => s + a.approvedAmount);
      if (taken == 0) continue;
      final rec = slips
          .where((p) => p['phone'] == u.phone)
          .fold<double>(0, (s, p) => s + numVal(p['advanceRecovery']));
      rows.add([u.name, u.phone, taken.round(), rec.round(),
        (taken - rec).clamp(0, double.infinity).round()]);
    }
    await shareCsv('advances_outstanding.csv', [
      ['Name', 'Mobile', 'Advance taken', 'Recovered', 'Outstanding'],
      ...rows,
    ]);
  }

  Future<void> _expenses() async {
    final ex = (await _db.collection('expenses').get())
        .docs
        .map(Expense.fromDoc)
        .where((e) =>
            e.createdAt != null && monthKey(e.createdAt!) == _month)
        .toList()
      ..sort((a, b) => a.createdAt!.compareTo(b.createdAt!));
    await shareCsv('expenses_$_month.csv', [
      ['Date', 'Name', 'Category', 'Site', 'Details', 'Amount', 'Status',
        'Note', 'Bill link'],
      for (final e in ex)
        [dayFmt.format(e.createdAt!), e.name, e.category, e.siteName,
          e.details, e.amount.round(), e.status.name, e.note ?? '',
          e.billUrl ?? ''],
      [],
      ['', 'APPROVED TOTAL', '', '', '',
        ex.where((e) => e.status == ReqStatus.approved)
            .fold<double>(0, (s, e) => s + e.amount).round(), '', '', ''],
    ]);
  }

  /// Full account numbers. Confirm first: this file is sensitive.
  Future<void> _bank() async {
    final note = await askNote(
        context, 'Download full bank details of all staff?',
        action: 'Download');
    if (note == null) return;
    final banks = await BankService.all();
    final staff = await _staff();
    await shareCsv('bank_details.csv', [
      ['Name', 'Mobile', 'Account holder', 'Account number', 'IFSC', 'Bank',
        'Branch', 'Verified by', 'Proof link'],
      for (final u in staff)
        () {
          final b = banks[u.phone];
          return b == null
              ? [u.name, u.phone, 'NOT SUBMITTED', '', '', '', '', '', '']
              : [u.name, u.phone, b.holderName, "'${b.accountNumber}",
                  b.ifsc, b.bankName, b.branch, b.verifiedBy ?? '',
                  b.proofUrl];
        }(),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    Widget tile(String key, IconData icon, String title, String sub,
            Future<void> Function() job) =>
        Card(
          child: ListTile(
            leading: Icon(icon),
            title: Text(title),
            subtitle: Text(sub),
            trailing: _busy == key
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.download),
            onTap: _busy == null ? () => _run(key, job) : null,
          ),
        );

    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        Row(children: [
          const Text('Month: '),
          MonthDropdown(
              value: _month, onChanged: (m) => setState(() => _month = m)),
        ]),
        const SizedBox(height: 8),
        tile('att', Icons.fact_check, 'Attendance summary',
            'Full, incomplete and leave days per person', _attendanceSummary),
        tile('punch', Icons.camera_front, 'Attendance detail',
            'Every punch with time, site, GPS and selfie link',
            _attendanceDetail),
        tile('km', Icons.local_shipping, 'Vehicle km log',
            'Daily start/end km and rent per driver', _vehicleLog),
        tile('exp', Icons.receipt, 'Expenses',
            'Payment requests raised this month', _expenses),
        const Divider(height: 24),
        tile('adv', Icons.account_balance_wallet, 'Advance outstanding',
            'All staff, as of today', _advances),
        tile('bank', Icons.lock, 'Bank details (sensitive)',
            'Full account numbers of all staff', _bank),
        const SizedBox(height: 8),
        const Text(
          'Payroll register and bank transfer sheet are on the Payroll tab.',
          style: TextStyle(color: Colors.black54),
        ),
      ],
    );
  }
}
