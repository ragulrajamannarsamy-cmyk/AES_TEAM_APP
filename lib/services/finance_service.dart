import 'dart:io';
import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/payslip.dart';
import '../models/requests.dart';
import 'storage_service.dart';

/// Salary advances, carry-forward requests and expense (payment) requests.
class FinanceService {
  static final _db = FirebaseFirestore.instance;
  static CollectionReference<Map<String, dynamic>> get advances =>
      _db.collection('advances');
  static CollectionReference<Map<String, dynamic>> get carryForwards =>
      _db.collection('carryForwards');
  static CollectionReference<Map<String, dynamic>> get expenses =>
      _db.collection('expenses');

  // ---------- Worker: own lists ----------
  static Stream<List<Advance>> myAdvances(String phone) => advances
      .where('phone', isEqualTo: phone)
      .snapshots()
      .map((q) => newestFirst(q.docs.map(Advance.fromDoc).toList()));

  static Stream<List<CarryForward>> myCarryForwards(String phone) =>
      carryForwards
          .where('phone', isEqualTo: phone)
          .snapshots()
          .map((q) => newestFirst(q.docs.map(CarryForward.fromDoc).toList()));

  static Stream<List<Expense>> myExpenses(String phone) => expenses
      .where('phone', isEqualTo: phone)
      .snapshots()
      .map((q) => newestFirst(q.docs.map(Expense.fromDoc).toList()));

  // ---------- Admin: pending queues (oldest first) ----------
  static Stream<List<Advance>> pendingAdvances() => advances
      .where('status', isEqualTo: 'pending')
      .snapshots()
      .map((q) => oldestFirst(q.docs.map(Advance.fromDoc).toList()));

  static Stream<List<CarryForward>> pendingCarryForwards() => carryForwards
      .where('status', isEqualTo: 'pending')
      .snapshots()
      .map((q) => oldestFirst(q.docs.map(CarryForward.fromDoc).toList()));

  static Stream<List<Expense>> pendingExpenses() => expenses
      .where('status', isEqualTo: 'pending')
      .snapshots()
      .map((q) => oldestFirst(q.docs.map(Expense.fromDoc).toList()));

  // ---------- Submit ----------
  static Future<void> requestAdvance(
          String phone, String name, double amount, String reason) =>
      advances.add({
        'phone': phone,
        'name': name,
        'amount': amount,
        'approvedAmount': 0,
        'reason': reason,
        'status': 'pending',
        'createdAt': FieldValue.serverTimestamp(),
      });

  static Future<void> requestCarryForward(String phone, String name,
          String month, double amount, String reason) =>
      carryForwards.add({
        'phone': phone,
        'name': name,
        'month': month,
        'amount': amount,
        'reason': reason,
        'status': 'pending',
        'createdAt': FieldValue.serverTimestamp(),
      });

  static Future<void> requestExpense({
    required String phone,
    required String name,
    required double amount,
    required String category,
    required String siteName,
    required String details,
    File? bill,
  }) async {
    final url =
        bill == null ? null : await StorageService.upload('bills', phone, bill);
    await expenses.add({
      'phone': phone,
      'name': name,
      'amount': amount,
      'category': category,
      'siteName': siteName,
      'details': details,
      'billUrl': url,
      'status': 'pending',
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  // ---------- Admin: decide ----------
  static Future<void> review(
    CollectionReference<Map<String, dynamic>> col,
    String id, {
    required bool approve,
    required String reviewer,
    String note = '',
    double? approvedAmount,
  }) =>
      col.doc(id).update({
        'status': approve ? 'approved' : 'rejected',
        'reviewedBy': reviewer,
        'note': note,
        'reviewedAt': FieldValue.serverTimestamp(),
        if (approvedAmount != null) 'approvedAmount': approve ? approvedAmount : 0,
      });

  /// Advance still to be recovered: approved advances − recoveries in
  /// approved payslips.
  static double outstanding(List<Advance> advances, List<Payslip> slips) {
    final taken = advances
        .where((a) => a.status == ReqStatus.approved)
        .fold<double>(0, (s, a) => s + a.approvedAmount);
    final recovered = slips
        .where((p) => p.approved)
        .fold<double>(0, (s, p) => s + p.advanceRecovery);
    return math.max(0.0, taken - recovered);
  }
}
