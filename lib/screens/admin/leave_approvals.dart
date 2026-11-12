import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../models/app_user.dart';
import '../../models/leave_request.dart';
import '../../services/leave_service.dart';
import '../../theme.dart';

class LeaveApprovals extends StatelessWidget {
  final AppUser me;
  const LeaveApprovals({super.key, required this.me});

  @override
  Widget build(BuildContext context) {
    final d = DateFormat('d MMM');
    return StreamBuilder<List<LeaveRequest>>(
      stream: LeaveService.watchPending(),
      builder: (context, snap) {
        final items = snap.data ?? [];
        if (items.isEmpty) {
          return const Center(child: Text('No pending requests.'));
        }
        return ListView.builder(
          padding: const EdgeInsets.all(12),
          itemCount: items.length,
          itemBuilder: (_, i) {
            final r = items[i];
            return Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('${r.name} · ${leaveTypeLabels[r.type]}',
                        style: const TextStyle(fontWeight: FontWeight.bold)),
                    Text(
                        '${d.format(r.from)} – ${d.format(r.to)} (${r.days} day${r.days > 1 ? 's' : ''})'),
                    const SizedBox(height: 4),
                    Text(r.reason),
                    const SizedBox(height: 8),
                    if (r.certUrl?.isNotEmpty == true)
                      TextButton.icon(
                        icon: const Icon(Icons.description),
                        label: const Text('View certificate'),
                        onPressed: () => launchUrl(Uri.parse(r.certUrl!),
                            mode: LaunchMode.externalApplication),
                      )
                    else if (r.type != LeaveType.planned)
                      const Text('No certificate yet — LOP if not uploaded',
                          style: TextStyle(color: kRed)),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        OutlinedButton(
                          onPressed: () => _decide(context, r, false),
                          child: const Text('Reject'),
                        ),
                        const SizedBox(width: 8),
                        FilledButton(
                          style: FilledButton.styleFrom(
                              minimumSize: const Size(100, 40)),
                          onPressed: () => _decide(context, r, true),
                          child: const Text('Approve'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _decide(
      BuildContext context, LeaveRequest r, bool approve) async {
    final note = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(approve ? 'Approve leave?' : 'Reject leave?'),
        content: TextField(
          controller: note,
          decoration: const InputDecoration(labelText: 'Note (optional)'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(c, true),
              child: Text(approve ? 'Approve' : 'Reject')),
        ],
      ),
    );
    if (ok == true) {
      await LeaveService.review(r, approve, me.name, note.text.trim());
    }
  }
}
