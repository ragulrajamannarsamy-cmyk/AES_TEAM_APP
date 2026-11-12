import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';

import 'requests.dart';

/// One person's salary for one month.
/// Doc id: `<yyyy-MM>_<phone>` in collection `payroll`.
///
/// Net = Days present × Per-day rate + Km × Per-km rate
///       − PF+ESI − Advance recovery + Adjustment
class Payslip {
  final String phone;
  final String name;
  final String month;

  // Attendance facts (for review)
  final int completeDays;
  final int incompleteDays;
  final int paidLeaveDays;

  // Editable by admin before approval
  final double daysPresent;
  final double km;
  final double advanceRecovery;
  final double adjustment;
  final String adjustmentNote;

  // Rates at the time of calculation
  final double perDayRate;
  final double perKmRate;
  final double pfEsi;

  // Advance info
  final double advanceOutstanding; // before this month's recovery
  final double carriedForward;

  final String status; // draft | approved

  const Payslip({
    required this.phone,
    required this.name,
    required this.month,
    required this.completeDays,
    required this.incompleteDays,
    required this.paidLeaveDays,
    required this.daysPresent,
    required this.km,
    required this.advanceRecovery,
    required this.adjustment,
    required this.adjustmentNote,
    required this.perDayRate,
    required this.perKmRate,
    required this.pfEsi,
    required this.advanceOutstanding,
    required this.carriedForward,
    required this.status,
  });

  String get docId => '${month}_$phone';
  bool get approved => status == 'approved';

  double get gross => daysPresent * perDayRate;
  double get kmRent => km * perKmRate;
  double get net => gross + kmRent - pfEsi - advanceRecovery + adjustment;
  double get advanceBalanceAfter =>
      math.max(0.0, advanceOutstanding - advanceRecovery);

  /// Highest recovery possible without making salary negative.
  static double maxRecovery(double gross, double kmRent, double pfEsi) =>
      math.max(0.0, gross + kmRent - pfEsi);

  Payslip copyWith({
    double? daysPresent,
    double? km,
    double? advanceRecovery,
    double? adjustment,
    String? adjustmentNote,
    String? status,
  }) =>
      Payslip(
        phone: phone,
        name: name,
        month: month,
        completeDays: completeDays,
        incompleteDays: incompleteDays,
        paidLeaveDays: paidLeaveDays,
        daysPresent: daysPresent ?? this.daysPresent,
        km: km ?? this.km,
        advanceRecovery: advanceRecovery ?? this.advanceRecovery,
        adjustment: adjustment ?? this.adjustment,
        adjustmentNote: adjustmentNote ?? this.adjustmentNote,
        perDayRate: perDayRate,
        perKmRate: perKmRate,
        pfEsi: pfEsi,
        advanceOutstanding: advanceOutstanding,
        carriedForward: carriedForward,
        status: status ?? this.status,
      );

  factory Payslip.fromDoc(DocumentSnapshot<Map<String, dynamic>> d) {
    final m = d.data() ?? {};
    return Payslip(
      phone: (m['phone'] ?? '') as String,
      name: (m['name'] ?? '') as String,
      month: (m['month'] ?? '') as String,
      completeDays: numVal(m['completeDays']).toInt(),
      incompleteDays: numVal(m['incompleteDays']).toInt(),
      paidLeaveDays: numVal(m['paidLeaveDays']).toInt(),
      daysPresent: numVal(m['daysPresent']),
      km: numVal(m['km']),
      advanceRecovery: numVal(m['advanceRecovery']),
      adjustment: numVal(m['adjustment']),
      adjustmentNote: (m['adjustmentNote'] ?? '') as String,
      perDayRate: numVal(m['perDayRate']),
      perKmRate: numVal(m['perKmRate']),
      pfEsi: numVal(m['pfEsi']),
      advanceOutstanding: numVal(m['advanceOutstanding']),
      carriedForward: numVal(m['carriedForward']),
      status: (m['status'] ?? 'draft') as String,
    );
  }

  Map<String, dynamic> toMap() => {
        'phone': phone,
        'name': name,
        'month': month,
        'completeDays': completeDays,
        'incompleteDays': incompleteDays,
        'paidLeaveDays': paidLeaveDays,
        'daysPresent': daysPresent,
        'km': km,
        'advanceRecovery': advanceRecovery,
        'adjustment': adjustment,
        'adjustmentNote': adjustmentNote,
        'perDayRate': perDayRate,
        'perKmRate': perKmRate,
        'pfEsi': pfEsi,
        'advanceOutstanding': advanceOutstanding,
        'carriedForward': carriedForward,
        'gross': gross,
        'kmRent': kmRent,
        'net': net,
        'status': status,
      };
}
