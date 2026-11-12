import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/site.dart';

class SiteService {
  static final _col = FirebaseFirestore.instance.collection('sites');

  static Stream<List<Site>> watchAll() => _col
      .orderBy('name')
      .snapshots()
      .map((q) => q.docs.map(Site.fromDoc).toList());

  static Future<List<Site>> fetchAll() async =>
      (await _col.get()).docs.map(Site.fromDoc).toList();

  /// Admin only.
  static Future<void> save(Site s) => s.id.isEmpty
      ? _col.add(s.toMap())
      : _col.doc(s.id).set(s.toMap());

  /// Admin only.
  static Future<void> delete(String id) => _col.doc(id).delete();
}
