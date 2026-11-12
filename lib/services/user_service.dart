import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/app_user.dart';

class UserService {
  static final _col = FirebaseFirestore.instance.collection('users');

  static Stream<AppUser?> watch(String phone) => _col
      .doc(phone)
      .snapshots()
      .map((d) => d.exists ? AppUser.fromDoc(d) : null);

  /// Admin only (enforced by Firestore rules).
  static Stream<List<AppUser>> watchAll() => _col
      .orderBy('name')
      .snapshots()
      .map((q) => q.docs.map(AppUser.fromDoc).toList());

  /// Admin only. Phone must be E.164 (+91XXXXXXXXXX).
  static Future<void> save(AppUser u) =>
      _col.doc(u.phone).set(u.toMap(), SetOptions(merge: true));
}

/// Normalises "98409 21142" / "+91 98409-21142" to "+919840921142".
String normalizePhone(String raw) {
  final digits = raw.replaceAll(RegExp(r'[^0-9]'), '');
  if (digits.length == 10) return '+91$digits';
  if (digits.length == 12 && digits.startsWith('91')) return '+$digits';
  return '+$digits';
}
