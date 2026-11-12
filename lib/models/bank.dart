import 'package:cloud_firestore/cloud_firestore.dart';

import 'requests.dart';

String maskAccount(String n) =>
    n.length <= 4 ? n : 'XXXX XXXX ${n.substring(n.length - 4)}';

class BankDetails {
  final String holderName;
  final String accountNumber;
  final String ifsc;
  final String bankName;
  final String branch;
  final String proofUrl;
  final String? verifiedBy;
  final DateTime? verifiedAt;

  const BankDetails({
    required this.holderName,
    required this.accountNumber,
    required this.ifsc,
    required this.bankName,
    required this.branch,
    required this.proofUrl,
    this.verifiedBy,
    this.verifiedAt,
  });

  String get masked => maskAccount(accountNumber);

  factory BankDetails.fromMap(Map<String, dynamic> m) => BankDetails(
        holderName: (m['holderName'] ?? '') as String,
        accountNumber: (m['accountNumber'] ?? '') as String,
        ifsc: (m['ifsc'] ?? '') as String,
        bankName: (m['bankName'] ?? '') as String,
        branch: (m['branch'] ?? '') as String,
        proofUrl: (m['proofUrl'] ?? '') as String,
        verifiedBy: m['verifiedBy'] as String?,
        verifiedAt: tsDate(m['verifiedAt']),
      );

  Map<String, dynamic> toMap() => {
        'holderName': holderName,
        'accountNumber': accountNumber,
        'ifsc': ifsc,
        'bankName': bankName,
        'branch': branch,
        'proofUrl': proofUrl,
      };
}

/// A worker's submission of new or changed bank details.
/// Becomes the live record in `bank/<phone>` only when an admin approves.
class BankRequest extends BaseRequest {
  @override
  final String id, phone, name;
  final BankDetails details;
  @override
  final ReqStatus status;
  @override
  final String? note;
  @override
  final DateTime? createdAt;

  BankRequest({
    required this.id,
    required this.phone,
    required this.name,
    required this.details,
    required this.status,
    this.note,
    this.createdAt,
  });

  factory BankRequest.fromDoc(DocumentSnapshot<Map<String, dynamic>> d) {
    final m = d.data() ?? {};
    return BankRequest(
      id: d.id,
      phone: (m['phone'] ?? '') as String,
      name: (m['name'] ?? '') as String,
      details: BankDetails.fromMap(m),
      status: reqStatusFrom(m['status']),
      note: m['note'] as String?,
      createdAt: tsDate(m['createdAt']),
    );
  }
}
