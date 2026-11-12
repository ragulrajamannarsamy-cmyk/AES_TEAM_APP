import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';

import '../models/leave_request.dart';

class LeaveService {
  static final _col = FirebaseFirestore.instance.collection('leaves');

  static Stream<List<LeaveRequest>> watchMine(String phone) => _col
      .where('phone', isEqualTo: phone)
      .orderBy('createdAt', descending: true)
      .snapshots()
      .map((q) => q.docs.map(LeaveRequest.fromDoc).toList());

  /// Admin only.
  static Stream<List<LeaveRequest>> watchPending() => _col
      .where('status', isEqualTo: 'pending')
      .orderBy('createdAt')
      .snapshots()
      .map((q) => q.docs.map(LeaveRequest.fromDoc).toList());

  static Future<String> uploadCertificate(String phone, File file) async {
    final ext = file.path.split('.').last.toLowerCase();
    final type = ext == 'pdf' ? 'application/pdf' : 'image/jpeg';
    final ref = FirebaseStorage.instance.ref(
        'certificates/$phone/${DateTime.now().millisecondsSinceEpoch}.$ext');
    await ref.putFile(file, SettableMetadata(contentType: type));
    return ref.getDownloadURL();
  }

  static Future<void> submit({
    required String phone,
    required String name,
    required LeaveType type,
    required DateTime from,
    required DateTime to,
    required String reason,
    File? certificate,
  }) async {
    String? certUrl;
    if (certificate != null) {
      certUrl = await uploadCertificate(phone, certificate);
    }
    await _col.add({
      'phone': phone,
      'name': name,
      'type': type.name,
      'from': Timestamp.fromDate(from),
      'to': Timestamp.fromDate(to),
      'reason': reason,
      'certUrl': certUrl,
      'status': 'pending',
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  /// Worker adds a certificate later (emergency leave).
  static Future<void> attachCertificate(
      LeaveRequest r, String phone, File file) async {
    final url = await uploadCertificate(phone, file);
    await _col.doc(r.id).update({
      'certUrl': url,
      'certUploadedAt': FieldValue.serverTimestamp(),
    });
  }

  /// Admin only.
  static Future<void> review(
          LeaveRequest r, bool approve, String reviewer, String note) =>
      _col.doc(r.id).update({
        'status': approve ? 'approved' : 'rejected',
        'reviewedBy': reviewer,
        'reviewNote': note,
        'reviewedAt': FieldValue.serverTimestamp(),
      });
}
