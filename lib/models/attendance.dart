import 'package:cloud_firestore/cloud_firestore.dart';

/// One selfie + GPS record.
class Punch {
  final DateTime time;
  final double lat;
  final double lng;
  final double accuracyM;
  final String siteId;
  final String siteName;
  final String photoUrl;

  const Punch({
    required this.time,
    required this.lat,
    required this.lng,
    required this.accuracyM,
    required this.siteId,
    required this.siteName,
    required this.photoUrl,
  });

  factory Punch.fromMap(Map<String, dynamic> m) => Punch(
        time: (m['time'] is Timestamp)
            ? (m['time'] as Timestamp).toDate()
            : DateTime.now(),
        lat: (m['lat'] ?? 0).toDouble(),
        lng: (m['lng'] ?? 0).toDouble(),
        accuracyM: (m['accuracyM'] ?? 0).toDouble(),
        siteId: (m['siteId'] ?? '') as String,
        siteName: (m['siteName'] ?? '') as String,
        photoUrl: (m['photoUrl'] ?? '') as String,
      );

  Map<String, dynamic> toMap() => {
        'time': Timestamp.fromDate(time),
        'lat': lat,
        'lng': lng,
        'accuracyM': accuracyM,
        'siteId': siteId,
        'siteName': siteName,
        'photoUrl': photoUrl,
      };
}

/// One person's attendance for one day.
/// Doc id: `<phone>_<yyyy-MM-dd>` in collection `attendance`.
class AttendanceDay {
  final String phone;
  final String date; // yyyy-MM-dd
  final Punch? inPunch;
  final Punch? outPunch;
  final List<Punch> siteVisits;

  const AttendanceDay({
    required this.phone,
    required this.date,
    this.inPunch,
    this.outPunch,
    this.siteVisits = const [],
  });

  /// A full present day = In and Out both recorded.
  bool get isComplete => inPunch != null && outPunch != null;

  String get statusLabel {
    if (outPunch != null) return 'Checked out';
    if (siteVisits.isNotEmpty) return 'At site: ${siteVisits.last.siteName}';
    if (inPunch != null) return 'At office';
    return 'Not checked in';
  }

  factory AttendanceDay.fromDoc(DocumentSnapshot<Map<String, dynamic>> d) {
    final m = d.data() ?? {};
    return AttendanceDay(
      phone: (m['phone'] ?? '') as String,
      date: (m['date'] ?? '') as String,
      inPunch: m['in'] == null
          ? null
          : Punch.fromMap(Map<String, dynamic>.from(m['in'])),
      outPunch: m['out'] == null
          ? null
          : Punch.fromMap(Map<String, dynamic>.from(m['out'])),
      siteVisits: ((m['siteVisits'] ?? []) as List)
          .map((e) => Punch.fromMap(Map<String, dynamic>.from(e)))
          .toList(),
    );
  }
}
