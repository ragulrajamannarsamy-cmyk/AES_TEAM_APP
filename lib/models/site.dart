import 'package:cloud_firestore/cloud_firestore.dart';

enum SiteType { office, substation }

class Site {
  final String id;
  final String name;
  final SiteType type;
  final double lat;
  final double lng;
  final double radiusM;

  const Site({
    required this.id,
    required this.name,
    required this.type,
    required this.lat,
    required this.lng,
    required this.radiusM,
  });

  bool get isOffice => type == SiteType.office;

  factory Site.fromDoc(DocumentSnapshot<Map<String, dynamic>> d) {
    final m = d.data() ?? {};
    return Site(
      id: d.id,
      name: (m['name'] ?? '') as String,
      type: m['type'] == 'office' ? SiteType.office : SiteType.substation,
      lat: (m['lat'] ?? 0).toDouble(),
      lng: (m['lng'] ?? 0).toDouble(),
      radiusM: (m['radiusM'] ?? 200).toDouble(),
    );
  }

  Map<String, dynamic> toMap() => {
        'name': name,
        'type': type.name,
        'lat': lat,
        'lng': lng,
        'radiusM': radiusM,
      };
}
