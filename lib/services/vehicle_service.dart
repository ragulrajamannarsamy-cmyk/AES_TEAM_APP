import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/vehicle_log.dart';
import 'storage_service.dart';

class VehicleService {
  static final _col = FirebaseFirestore.instance.collection('vehicleLogs');

  static String docId(String phone, String date) => '${phone}_$date';

  static Stream<VehicleLog?> watchDay(String phone, String date) => _col
      .doc(docId(phone, date))
      .snapshots()
      .map((d) => d.exists ? VehicleLog.fromDoc(d) : null);

  static Stream<List<VehicleLog>> watchMonth(String phone, String month) => _col
      .where('phone', isEqualTo: phone)
      .where('date', isGreaterThanOrEqualTo: '$month-01')
      .where('date', isLessThanOrEqualTo: '$month-31')
      .orderBy('date', descending: true)
      .snapshots()
      .map((q) => q.docs.map(VehicleLog.fromDoc).toList());

  /// Admin: every driver's logs for a month.
  static Future<List<VehicleLog>> allForMonth(String month) async => (await _col
          .where('date', isGreaterThanOrEqualTo: '$month-01')
          .where('date', isLessThanOrEqualTo: '$month-31')
          .get())
      .docs
      .map(VehicleLog.fromDoc)
      .toList();

  /// The driver's most recent log before [date], to check odometer continuity.
  static Future<VehicleLog?> lastBefore(String phone, String date) async {
    final q = await _col
        .where('phone', isEqualTo: phone)
        .where('date', isLessThan: date)
        .orderBy('date', descending: true)
        .limit(1)
        .get();
    return q.docs.isEmpty ? null : VehicleLog.fromDoc(q.docs.first);
  }

  static Future<void> start({
    required String phone,
    required String name,
    required String date,
    required String vehicleNo,
    required double km,
    required File photo,
  }) async {
    final url = await StorageService.upload('odometer', phone, photo);
    await _col.doc(docId(phone, date)).set({
      'phone': phone,
      'name': name,
      'date': date,
      'vehicleNo': vehicleNo,
      'startKm': km,
      'startPhoto': url,
      'startTime': FieldValue.serverTimestamp(),
    });
  }

  static Future<void> end({
    required String phone,
    required String date,
    required double km,
    required File photo,
  }) async {
    final url = await StorageService.upload('odometer', phone, photo);
    await _col.doc(docId(phone, date)).update({
      'endKm': km,
      'endPhoto': url,
      'endTime': FieldValue.serverTimestamp(),
    });
  }
}
