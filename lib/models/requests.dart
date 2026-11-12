import 'package:cloud_firestore/cloud_firestore.dart';

enum ReqStatus { pending, approved, rejected }

ReqStatus reqStatusFrom(Object? s) => ReqStatus.values
    .firstWhere((e) => e.name == s, orElse: () => ReqStatus.pending);

DateTime? tsDate(Object? v) => v is Timestamp ? v.toDate() : null;
double numVal(Object? v) => (v as num?)?.toDouble() ?? 0;

/// Fields every request shares (advance, carry forward, expense, bank change).
abstract class BaseRequest {
  String get id;
  String get phone;
  String get name;
  ReqStatus get status;
  String? get note;
  DateTime? get createdAt;

  /// Pending for 24 hours or more (target is approval within 24–48 h).
  bool get overdue =>
      status == ReqStatus.pending &&
      createdAt != null &&
      DateTime.now().difference(createdAt!).inHours >= 24;
}

/// Salary advance. Approved amount is recovered from salary.
class Advance extends BaseRequest {
  @override
  final String id, phone, name;
  final String reason;
  final double amount;
  final double approvedAmount;
  @override
  final ReqStatus status;
  @override
  final String? note;
  @override
  final DateTime? createdAt;
  final DateTime? reviewedAt;

  Advance({
    required this.id,
    required this.phone,
    required this.name,
    required this.reason,
    required this.amount,
    required this.approvedAmount,
    required this.status,
    this.note,
    this.createdAt,
    this.reviewedAt,
  });

  factory Advance.fromDoc(DocumentSnapshot<Map<String, dynamic>> d) {
    final m = d.data() ?? {};
    return Advance(
      id: d.id,
      phone: (m['phone'] ?? '') as String,
      name: (m['name'] ?? '') as String,
      reason: (m['reason'] ?? '') as String,
      amount: numVal(m['amount']),
      approvedAmount: numVal(m['approvedAmount']),
      status: reqStatusFrom(m['status']),
      note: m['note'] as String?,
      createdAt: tsDate(m['createdAt']),
      reviewedAt: tsDate(m['reviewedAt']),
    );
  }
}

/// Request to NOT deduct [amount] of the advance from [month]'s salary.
class CarryForward extends BaseRequest {
  @override
  final String id, phone, name;
  final String month; // yyyy-MM payroll month
  final double amount;
  final String reason;
  @override
  final ReqStatus status;
  @override
  final String? note;
  @override
  final DateTime? createdAt;

  CarryForward({
    required this.id,
    required this.phone,
    required this.name,
    required this.month,
    required this.amount,
    required this.reason,
    required this.status,
    this.note,
    this.createdAt,
  });

  factory CarryForward.fromDoc(DocumentSnapshot<Map<String, dynamic>> d) {
    final m = d.data() ?? {};
    return CarryForward(
      id: d.id,
      phone: (m['phone'] ?? '') as String,
      name: (m['name'] ?? '') as String,
      month: (m['month'] ?? '') as String,
      amount: numVal(m['amount']),
      reason: (m['reason'] ?? '') as String,
      status: reqStatusFrom(m['status']),
      note: m['note'] as String?,
      createdAt: tsDate(m['createdAt']),
    );
  }
}

const expenseCategories = [
  'Material',
  'Travel',
  'Food',
  'Fuel',
  'Tools',
  'Other',
];

/// Payment request for site expenses, with bill photo.
class Expense extends BaseRequest {
  @override
  final String id, phone, name;
  final double amount;
  final String category;
  final String siteName;
  final String details;
  final String? billUrl;
  @override
  final ReqStatus status;
  @override
  final String? note;
  @override
  final DateTime? createdAt;

  Expense({
    required this.id,
    required this.phone,
    required this.name,
    required this.amount,
    required this.category,
    required this.siteName,
    required this.details,
    required this.status,
    this.billUrl,
    this.note,
    this.createdAt,
  });

  factory Expense.fromDoc(DocumentSnapshot<Map<String, dynamic>> d) {
    final m = d.data() ?? {};
    return Expense(
      id: d.id,
      phone: (m['phone'] ?? '') as String,
      name: (m['name'] ?? '') as String,
      amount: numVal(m['amount']),
      category: (m['category'] ?? 'Other') as String,
      siteName: (m['siteName'] ?? '') as String,
      details: (m['details'] ?? '') as String,
      billUrl: m['billUrl'] as String?,
      status: reqStatusFrom(m['status']),
      note: m['note'] as String?,
      createdAt: tsDate(m['createdAt']),
    );
  }
}

List<T> newestFirst<T extends BaseRequest>(List<T> l) {
  final now = DateTime.now();
  l.sort((a, b) => (b.createdAt ?? now).compareTo(a.createdAt ?? now));
  return l;
}

List<T> oldestFirst<T extends BaseRequest>(List<T> l) {
  final now = DateTime.now();
  l.sort((a, b) => (a.createdAt ?? now).compareTo(b.createdAt ?? now));
  return l;
}
