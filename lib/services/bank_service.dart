import 'dart:convert';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:http/http.dart' as http;

import '../models/bank.dart';
import '../models/requests.dart';
import 'storage_service.dart';

/// Live bank details live in `bank/<phone>` and only admins can write them.
/// Workers submit to `bankRequests`; an admin approval copies the request
/// into `bank/<phone>`. So nobody can quietly redirect a salary.
class BankService {
  static final _db = FirebaseFirestore.instance;
  static final _bank = _db.collection('bank');
  static final _req = _db.collection('bankRequests');

  static Stream<BankDetails?> watchMine(String phone) => _bank
      .doc(phone)
      .snapshots()
      .map((d) => d.exists ? BankDetails.fromMap(d.data()!) : null);

  static Stream<List<BankRequest>> myRequests(String phone) => _req
      .where('phone', isEqualTo: phone)
      .snapshots()
      .map((q) => newestFirst(q.docs.map(BankRequest.fromDoc).toList()));

  static Stream<List<BankRequest>> pending() => _req
      .where('status', isEqualTo: 'pending')
      .snapshots()
      .map((q) => oldestFirst(q.docs.map(BankRequest.fromDoc).toList()));

  /// Admin: phone -> bank details, for the salary transfer sheet.
  static Future<Map<String, BankDetails>> all() async {
    final q = await _bank.get();
    return {for (final d in q.docs) d.id: BankDetails.fromMap(d.data())};
  }

  static Future<void> submit({
    required String phone,
    required String name,
    required String holderName,
    required String accountNumber,
    required String ifsc,
    required String bankName,
    required String branch,
    required File proof,
  }) async {
    final url = await StorageService.upload('bankproof', phone, proof);
    await _req.add({
      'phone': phone,
      'name': name,
      'holderName': holderName,
      'accountNumber': accountNumber,
      'ifsc': ifsc.toUpperCase(),
      'bankName': bankName,
      'branch': branch,
      'proofUrl': url,
      'status': 'pending',
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  static Future<void> review(BankRequest r,
      {required bool approve, required String reviewer, String note = ''}) {
    final batch = _db.batch();
    batch.update(_req.doc(r.id), {
      'status': approve ? 'approved' : 'rejected',
      'reviewedBy': reviewer,
      'note': note,
      'reviewedAt': FieldValue.serverTimestamp(),
    });
    if (approve) {
      batch.set(_bank.doc(r.phone), {
        ...r.details.toMap(),
        'name': r.name,
        'verifiedBy': reviewer,
        'verifiedAt': FieldValue.serverTimestamp(),
      });
    }
    return batch.commit();
  }

  /// Looks up bank and branch from IFSC (free Razorpay IFSC API).
  /// Returns null if not found or offline.
  static Future<({String bank, String branch})?> lookupIfsc(String ifsc) async {
    try {
      final res = await http
          .get(Uri.parse('https://ifsc.razorpay.com/${ifsc.toUpperCase()}'))
          .timeout(const Duration(seconds: 8));
      if (res.statusCode != 200) return null;
      final m = jsonDecode(res.body) as Map<String, dynamic>;
      return (
        bank: (m['BANK'] ?? '') as String,
        branch: (m['BRANCH'] ?? '') as String,
      );
    } catch (_) {
      return null;
    }
  }
}

final ifscPattern = RegExp(r'^[A-Za-z]{4}0[A-Za-z0-9]{6}$');
