import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/app_user.dart';
import '../models/leave_request.dart';
import '../services/leave_service.dart';
import '../theme.dart';

final _d = DateFormat('d MMM yyyy');

Future<File?> pickCertificate() async {
  final res = await FilePicker.pickFiles(
    type: FileType.custom,
    allowedExtensions: ['jpg', 'jpeg', 'png', 'pdf'],
  );
  final path = res?.files.single.path;
  return path == null ? null : File(path);
}

Color statusColor(LeaveStatus s) => switch (s) {
      LeaveStatus.approved => kGreen,
      LeaveStatus.rejected => kRed,
      LeaveStatus.pending => kAmber,
    };

class LeaveScreen extends StatelessWidget {
  final AppUser me;
  const LeaveScreen({super.key, required this.me});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'leave',
        onPressed: () => Navigator.push(context,
            MaterialPageRoute(builder: (_) => LeaveFormScreen(me: me))),
        icon: const Icon(Icons.add),
        label: const Text('Request leave'),
      ),
      body: StreamBuilder<List<LeaveRequest>>(
        stream: LeaveService.watchMine(me.phone),
        builder: (context, snap) {
          final items = snap.data ?? [];
          if (items.isEmpty) {
            return const Center(
                child: Text('No leave requests yet.\nTap "Request leave" to raise one.',
                    textAlign: TextAlign.center));
          }
          return ListView.builder(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 88),
            itemCount: items.length,
            itemBuilder: (_, i) {
              final r = items[i];
              return Card(
                child: ListTile(
                  title: Text(
                      '${leaveTypeLabels[r.type]} · ${r.days} day${r.days > 1 ? 's' : ''}'),
                  subtitle: Text(
                      '${_d.format(r.from)} – ${_d.format(r.to)}\n${r.reason}'
                      '${r.reviewNote?.isNotEmpty == true ? '\nNote: ${r.reviewNote}' : ''}'),
                  isThreeLine: true,
                  trailing: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(r.status.name.toUpperCase(),
                          style: TextStyle(
                              color: statusColor(r.status),
                              fontWeight: FontWeight.bold)),
                      if (r.type != LeaveType.planned &&
                          (r.certUrl == null || r.certUrl!.isEmpty))
                        TextButton(
                          onPressed: () async {
                            final f = await pickCertificate();
                            if (f != null) {
                              await LeaveService.attachCertificate(
                                  r, me.phone, f);
                            }
                          },
                          child: const Text('Add certificate'),
                        ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class LeaveFormScreen extends StatefulWidget {
  final AppUser me;
  const LeaveFormScreen({super.key, required this.me});

  @override
  State<LeaveFormScreen> createState() => _LeaveFormScreenState();
}

class _LeaveFormScreenState extends State<LeaveFormScreen> {
  LeaveType _type = LeaveType.planned;
  DateTimeRange? _range;
  final _reason = TextEditingController();
  File? _cert;
  bool _busy = false;
  String? _error;

  Future<void> _submit() async {
    if (_range == null) {
      setState(() => _error = 'Choose the leave dates.');
      return;
    }
    if (_reason.text.trim().isEmpty) {
      setState(() => _error = 'Enter a reason.');
      return;
    }
    if (_type == LeaveType.medical && _cert == null) {
      setState(() => _error =
          'Medical leave needs a doctor certificate. Upload it, or choose Emergency and add it within 3 days.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await LeaveService.submit(
        phone: widget.me.phone,
        name: widget.me.name,
        type: _type,
        from: _range!.start,
        to: _range!.end,
        reason: _reason.text.trim(),
        certificate: _cert,
      );
      if (mounted) Navigator.pop(context);
    } catch (e) {
      setState(() {
        _busy = false;
        _error = 'Could not submit. Check internet and retry.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    return Scaffold(
      appBar: AppBar(title: const Text('Request leave')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          SegmentedButton<LeaveType>(
            segments: [
              for (final t in LeaveType.values)
                ButtonSegment(value: t, label: Text(leaveTypeLabels[t]!)),
            ],
            selected: {_type},
            onSelectionChanged: (s) => setState(() => _type = s.first),
          ),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            icon: const Icon(Icons.date_range),
            label: Text(_range == null
                ? 'Choose dates'
                : '${_d.format(_range!.start)} – ${_d.format(_range!.end)}'),
            onPressed: () async {
              final r = await showDateRangePicker(
                context: context,
                firstDate: now.subtract(const Duration(days: 7)),
                lastDate: now.add(const Duration(days: 180)),
              );
              if (r != null) setState(() => _range = r);
            },
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _reason,
            maxLines: 3,
            decoration: const InputDecoration(labelText: 'Reason'),
          ),
          const SizedBox(height: 16),
          if (_type != LeaveType.planned)
            OutlinedButton.icon(
              icon: Icon(_cert == null ? Icons.upload_file : Icons.check),
              label: Text(_cert == null
                  ? 'Upload doctor certificate (photo or PDF)'
                  : 'Certificate attached'),
              onPressed: () async {
                final f = await pickCertificate();
                if (f != null) setState(() => _cert = f);
              },
            ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(_error!, style: const TextStyle(color: kRed)),
          ],
          const SizedBox(height: 24),
          FilledButton(
            onPressed: _busy ? null : _submit,
            child: Text(_busy ? 'Submitting…' : 'Submit request'),
          ),
        ],
      ),
    );
  }
}
