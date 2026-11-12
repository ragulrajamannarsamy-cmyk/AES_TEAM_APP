import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../models/app_user.dart';
import '../../models/attendance.dart';
import '../../services/attendance_service.dart';
import '../../services/user_service.dart';
import '../../theme.dart';

/// Live view of who is at office, who is at which site, and who has not
/// checked in today.
class TodayBoard extends StatelessWidget {
  const TodayBoard({super.key});

  @override
  Widget build(BuildContext context) {
    final date = AttendanceService.today();
    final t = DateFormat('hh:mm a');
    return StreamBuilder<List<AppUser>>(
      stream: UserService.watchAll(),
      builder: (context, usersSnap) {
        final staff = (usersSnap.data ?? [])
            .where((u) => u.active && !u.isAdmin)
            .toList();
        return StreamBuilder<List<AttendanceDay>>(
          stream: AttendanceService.watchAllForDate(date),
          builder: (context, attSnap) {
            final byPhone = {
              for (final a in attSnap.data ?? <AttendanceDay>[]) a.phone: a
            };
            final present = staff.where((u) => byPhone[u.phone] != null).length;
            final atSite = byPhone.values
                .where((a) => a.siteVisits.isNotEmpty && a.outPunch == null)
                .length;
            final out = byPhone.values.where((a) => a.outPunch != null).length;

            // Not-checked-in first, so gaps are visible at the top.
            staff.sort((a, b) {
              final ax = byPhone[a.phone] == null ? 0 : 1;
              final bx = byPhone[b.phone] == null ? 0 : 1;
              return ax != bx ? ax - bx : a.name.compareTo(b.name);
            });

            return ListView(
              padding: const EdgeInsets.all(12),
              children: [
                Row(children: [
                  _stat('Checked in', '$present / ${staff.length}', kNavy),
                  _stat('At sites', '$atSite', kAmber),
                  _stat('Checked out', '$out', kGreen),
                ]),
                const SizedBox(height: 12),
                for (final u in staff)
                  Card(
                    child: ListTile(
                      leading: byPhone[u.phone]?.inPunch == null
                          ? const CircleAvatar(
                              backgroundColor: kRed,
                              child: Icon(Icons.person_off, color: Colors.white))
                          : CircleAvatar(
                              backgroundImage: NetworkImage(
                                  byPhone[u.phone]!.inPunch!.photoUrl)),
                      title: Text(u.name),
                      subtitle: Text(_detail(byPhone[u.phone], t)),
                      onTap: byPhone[u.phone] == null
                          ? null
                          : () => _showDay(context, u, byPhone[u.phone]!, t),
                    ),
                  ),
              ],
            );
          },
        );
      },
    );
  }

  String _detail(AttendanceDay? a, DateFormat t) {
    if (a == null) return 'Not checked in';
    final parts = <String>[];
    if (a.inPunch != null) parts.add('In ${t.format(a.inPunch!.time)}');
    if (a.siteVisits.isNotEmpty) {
      parts.add('${a.siteVisits.last.siteName} ${t.format(a.siteVisits.last.time)}');
    }
    if (a.outPunch != null) parts.add('Out ${t.format(a.outPunch!.time)}');
    return parts.join(' · ');
  }

  Widget _stat(String label, String value, Color c) => Expanded(
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(children: [
              Text(value,
                  style: TextStyle(
                      fontSize: 20, fontWeight: FontWeight.bold, color: c)),
              Text(label, style: const TextStyle(fontSize: 12)),
            ]),
          ),
        ),
      );

  void _showDay(
      BuildContext context, AppUser u, AttendanceDay a, DateFormat t) {
    final punches = <(String, Punch)>[
      if (a.inPunch != null) ('In', a.inPunch!),
      for (final v in a.siteVisits) ('Site', v),
      if (a.outPunch != null) ('Out', a.outPunch!),
    ];
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.7,
        builder: (_, ctrl) => ListView(
          controller: ctrl,
          padding: const EdgeInsets.all(16),
          children: [
            Text(u.name, style: Theme.of(context).textTheme.titleLarge),
            for (final (label, p) in punches) ...[
              const SizedBox(height: 12),
              Text('$label · ${p.siteName} · ${t.format(p.time)}'),
              Text(
                  'GPS ${p.lat.toStringAsFixed(5)}, ${p.lng.toStringAsFixed(5)} (±${p.accuracyM.round()} m)',
                  style: const TextStyle(color: Colors.black54)),
              const SizedBox(height: 6),
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.network(p.photoUrl, height: 220, fit: BoxFit.cover),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
