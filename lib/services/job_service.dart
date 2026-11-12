import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/job.dart';
import 'storage_service.dart';

class JobService {
  static final _col = FirebaseFirestore.instance.collection('jobs');

  static List<Job> _sorted(List<Job> l) {
    l.sort((a, b) {
      final s = a.status.index.compareTo(b.status.index);
      if (s != 0) return s;
      final far = DateTime(2100);
      return (a.startDate ?? far).compareTo(b.startDate ?? far);
    });
    return l;
  }

  /// Admin: all jobs.
  static Stream<List<Job>> watchAll() => _col
      .snapshots()
      .map((q) => _sorted(q.docs.map(Job.fromDoc).toList()));

  /// Worker: jobs they are assigned to.
  static Stream<List<Job>> watchMine(String phone) => _col
      .where('assigned', arrayContains: phone)
      .snapshots()
      .map((q) => _sorted(q.docs.map(Job.fromDoc).toList()));

  static Stream<Job?> watch(String id) => _col
      .doc(id)
      .snapshots()
      .map((d) => d.exists ? Job.fromDoc(d) : null);

  static Future<void> save(Job j) => j.id.isEmpty
      ? _col.add({...j.toMap(), 'createdAt': FieldValue.serverTimestamp()})
      : _col.doc(j.id).set(j.toMap(), SetOptions(merge: true));

  static Future<void> setStatus(String id, JobStatus s) =>
      _col.doc(id).update({'status': s.name});

  static Future<void> delete(String id) => _col.doc(id).delete();

  static Stream<List<JobUpdate>> watchUpdates(String jobId) => _col
      .doc(jobId)
      .collection('updates')
      .orderBy('time', descending: true)
      .snapshots()
      .map((q) => q.docs.map(JobUpdate.fromDoc).toList());

  static Future<void> postUpdate({
    required String jobId,
    required String phone,
    required String name,
    required String text,
    File? photo,
  }) async {
    final url =
        photo == null ? null : await StorageService.upload('jobs', phone, photo);
    await _col.doc(jobId).collection('updates').add({
      'phone': phone,
      'name': name,
      'text': text,
      'photoUrl': url,
      'time': FieldValue.serverTimestamp(),
    });
  }
}
