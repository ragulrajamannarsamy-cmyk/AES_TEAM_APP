import 'package:cloud_firestore/cloud_firestore.dart';

enum LeaveType { planned, medical, emergency }

enum LeaveStatus { pending, approved, rejected }

const leaveTypeLabels = {
  LeaveType.planned: 'Planned leave',
  LeaveType.medical: 'Medical leave',
  LeaveType.emergency: 'Emergency',
};

class LeaveRequest {
  final String id;
  final String phone;
  final String name;
  final LeaveType type;
  final DateTime from;
  final DateTime to;
  final String reason;
  final String? certUrl;
  final LeaveStatus status;
  final String? reviewNote;
  final String? reviewedBy;
  final DateTime? createdAt;

  const LeaveRequest({
    required this.id,
    required this.phone,
    required this.name,
    required this.type,
    required this.from,
    required this.to,
    required this.reason,
    required this.status,
    this.certUrl,
    this.reviewNote,
    this.reviewedBy,
    this.createdAt,
  });

  int get days => to.difference(from).inDays + 1;

  /// Medical leave needs a doctor's certificate to avoid loss of pay.
  bool get needsCertificate =>
      type == LeaveType.medical && (certUrl == null || certUrl!.isEmpty);

  factory LeaveRequest.fromDoc(DocumentSnapshot<Map<String, dynamic>> d) {
    final m = d.data() ?? {};
    return LeaveRequest(
      id: d.id,
      phone: (m['phone'] ?? '') as String,
      name: (m['name'] ?? '') as String,
      type: LeaveType.values.firstWhere((t) => t.name == m['type'],
          orElse: () => LeaveType.planned),
      from: (m['from'] as Timestamp).toDate(),
      to: (m['to'] as Timestamp).toDate(),
      reason: (m['reason'] ?? '') as String,
      certUrl: m['certUrl'] as String?,
      status: LeaveStatus.values.firstWhere((s) => s.name == m['status'],
          orElse: () => LeaveStatus.pending),
      reviewNote: m['reviewNote'] as String?,
      reviewedBy: m['reviewedBy'] as String?,
      createdAt: (m['createdAt'] as Timestamp?)?.toDate(),
    );
  }
}
