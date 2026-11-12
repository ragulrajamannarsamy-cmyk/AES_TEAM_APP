import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:geolocator/geolocator.dart';
import 'package:intl/intl.dart';

import '../models/attendance.dart';
import '../models/site.dart';

enum PunchKind { checkIn, siteVisit, checkOut }

const punchLabels = {
  PunchKind.checkIn: 'In time (office)',
  PunchKind.siteVisit: 'Site time',
  PunchKind.checkOut: 'Out time (office)',
};

class AttendanceService {
  static final _col = FirebaseFirestore.instance.collection('attendance');
  static final _fmt = DateFormat('yyyy-MM-dd');

  static String today() => _fmt.format(DateTime.now());
  static String docId(String phone, String date) => '${phone}_$date';

  static Stream<AttendanceDay?> watchDay(String phone, String date) => _col
      .doc(docId(phone, date))
      .snapshots()
      .map((d) => d.exists ? AttendanceDay.fromDoc(d) : null);

  /// Admin only: everyone's records for one date.
  static Stream<List<AttendanceDay>> watchAllForDate(String date) => _col
      .where('date', isEqualTo: date)
      .snapshots()
      .map((q) => q.docs.map(AttendanceDay.fromDoc).toList());

  /// One person's month, e.g. month = '2026-11'. Used for payroll.
  static Stream<List<AttendanceDay>> watchMonth(String phone, String month) =>
      _col
          .where('phone', isEqualTo: phone)
          .where('date', isGreaterThanOrEqualTo: '$month-01')
          .where('date', isLessThanOrEqualTo: '$month-31')
          .snapshots()
          .map((q) => q.docs.map(AttendanceDay.fromDoc).toList());

  /// Decides what this punch is from where the worker is standing
  /// and what they have already recorded today.
  static PunchKind decideKind(Site site, AttendanceDay? day) {
    if (!site.isOffice) return PunchKind.siteVisit;
    if (day?.inPunch == null) return PunchKind.checkIn;
    return PunchKind.checkOut;
  }

  /// Uploads the selfie and writes the punch.
  static Future<void> recordPunch({
    required String phone,
    required String name,
    required PunchKind kind,
    required Site site,
    required Position pos,
    required File selfie,
  }) async {
    final date = today();
    final now = DateTime.now();
    final path =
        'selfies/$phone/${date}_${kind.name}_${now.millisecondsSinceEpoch}.jpg';
    final ref = FirebaseStorage.instance.ref(path);
    await ref.putFile(selfie, SettableMetadata(contentType: 'image/jpeg'));
    final url = await ref.getDownloadURL();

    final punch = Punch(
      time: now,
      lat: pos.latitude,
      lng: pos.longitude,
      accuracyM: pos.accuracy,
      siteId: site.id,
      siteName: site.name,
      photoUrl: url,
    ).toMap()
      ..['serverTime'] = FieldValue.serverTimestamp();

    final doc = _col.doc(docId(phone, date));
    final base = {
      'phone': phone,
      'name': name,
      'date': date,
      'updatedAt': FieldValue.serverTimestamp(),
    };

    switch (kind) {
      case PunchKind.checkIn:
        await doc.set({...base, 'in': punch}, SetOptions(merge: true));
      case PunchKind.checkOut:
        await doc.set({...base, 'out': punch}, SetOptions(merge: true));
      case PunchKind.siteVisit:
        // serverTimestamp is not allowed inside arrays.
        punch.remove('serverTime');
        await doc.set({
          ...base,
          'siteVisits': FieldValue.arrayUnion([punch]),
        }, SetOptions(merge: true));
    }
  }
}
