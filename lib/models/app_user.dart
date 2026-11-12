import 'package:cloud_firestore/cloud_firestore.dart';

enum Role { owner, manager, worker, driver }

Role roleFrom(String? s) =>
    Role.values.firstWhere((r) => r.name == s, orElse: () => Role.worker);

const roleLabels = {
  Role.owner: 'Owner',
  Role.manager: 'Manager',
  Role.worker: 'Worker',
  Role.driver: 'Driver',
};

class AppUser {
  /// Phone in E.164 format, e.g. +919840921142. Also the Firestore doc id.
  final String phone;
  final String name;
  final Role role;
  final double perDayRate;
  final double pfEsi;
  final double perKmRate; // drivers: truck rent per km
  final String vehicleNo; // drivers: default truck
  final bool active;

  const AppUser({
    required this.phone,
    required this.name,
    required this.role,
    required this.perDayRate,
    required this.pfEsi,
    this.perKmRate = 0,
    this.vehicleNo = '',
    required this.active,
  });

  bool get isAdmin => role == Role.owner || role == Role.manager;
  bool get isOwner => role == Role.owner;
  bool get isDriver => role == Role.driver;

  factory AppUser.fromDoc(DocumentSnapshot<Map<String, dynamic>> d) {
    final m = d.data() ?? {};
    return AppUser(
      phone: d.id,
      name: (m['name'] ?? '') as String,
      role: roleFrom(m['role'] as String?),
      perDayRate: ((m['perDayRate'] ?? 0) as num).toDouble(),
      pfEsi: ((m['pfEsi'] ?? 2100) as num).toDouble(),
      perKmRate: ((m['perKmRate'] ?? 0) as num).toDouble(),
      vehicleNo: (m['vehicleNo'] ?? '') as String,
      active: (m['active'] ?? true) as bool,
    );
  }

  Map<String, dynamic> toMap() => {
        'name': name,
        'role': role.name,
        'perDayRate': perDayRate,
        'pfEsi': pfEsi,
        'perKmRate': perKmRate,
        'vehicleNo': vehicleNo,
        'active': active,
      };
}
