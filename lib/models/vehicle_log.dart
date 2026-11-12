import 'package:cloud_firestore/cloud_firestore.dart';

import 'requests.dart';

/// One driver's truck log for one day.
/// Doc id: `<phone>_<yyyy-MM-dd>` in collection `vehicleLogs`.
class VehicleLog {
  final String phone;
  final String name;
  final String date;
  final String vehicleNo;
  final double startKm;
  final String startPhoto;
  final DateTime? startTime;
  final double? endKm;
  final String? endPhoto;
  final DateTime? endTime;

  const VehicleLog({
    required this.phone,
    required this.name,
    required this.date,
    required this.vehicleNo,
    required this.startKm,
    required this.startPhoto,
    this.startTime,
    this.endKm,
    this.endPhoto,
    this.endTime,
  });

  bool get closed => endKm != null;
  double get km => endKm == null ? 0 : endKm! - startKm;

  factory VehicleLog.fromDoc(DocumentSnapshot<Map<String, dynamic>> d) {
    final m = d.data() ?? {};
    return VehicleLog(
      phone: (m['phone'] ?? '') as String,
      name: (m['name'] ?? '') as String,
      date: (m['date'] ?? '') as String,
      vehicleNo: (m['vehicleNo'] ?? '') as String,
      startKm: numVal(m['startKm']),
      startPhoto: (m['startPhoto'] ?? '') as String,
      startTime: tsDate(m['startTime']),
      endKm: m['endKm'] == null ? null : numVal(m['endKm']),
      endPhoto: m['endPhoto'] as String?,
      endTime: tsDate(m['endTime']),
    );
  }
}
