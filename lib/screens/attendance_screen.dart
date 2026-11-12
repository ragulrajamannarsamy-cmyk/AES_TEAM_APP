import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

import '../models/app_user.dart';
import '../models/attendance.dart';
import '../services/attendance_service.dart';
import '../services/location_service.dart';
import '../services/site_service.dart';
import '../theme.dart';
import 'job_detail_screen.dart';

class AttendanceScreen extends StatefulWidget {
  final AppUser me;
  const AttendanceScreen({super.key, required this.me});

  @override
  State<AttendanceScreen> createState() => _AttendanceScreenState();
}

class _AttendanceScreenState extends State<AttendanceScreen> {
  String _step = '';
  bool _busy = false;
  final _time = DateFormat('hh:mm a');

  void _toast(String msg, {bool error = false}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: error ? kRed : kGreen,
    ));
  }

  Future<void> _punch(AttendanceDay? today) async {
    if (today?.outPunch != null) {
      _toast('You have already checked out today.', error: true);
      return;
    }
    setState(() {
      _busy = true;
      _step = 'Getting GPS location…';
    });
    try {
      final pos = await LocationService.currentPosition();
      final sites = await SiteService.fetchAll();
      final match = LocationService.matchSite(pos, sites);
      if (match == null) {
        throw LocationException(
            'You are not at the office or any registered site. Move closer and retry.');
      }
      final kind = AttendanceService.decideKind(match.site, today);

      if (kind == PunchKind.checkOut && mounted) {
        final ok = await showDialog<bool>(
          context: context,
          builder: (c) => AlertDialog(
            title: const Text('Check out for the day?'),
            content: const Text('After check-out you cannot punch again today.'),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(c, false),
                  child: const Text('Cancel')),
              FilledButton(
                  onPressed: () => Navigator.pop(c, true),
                  child: const Text('Check out')),
            ],
          ),
        );
        if (ok != true) return;
      }

      setState(() => _step = 'Take your selfie…');
      // Camera only — gallery photos are not allowed.
      final shot = await ImagePicker().pickImage(
        source: ImageSource.camera,
        preferredCameraDevice: CameraDevice.front,
        imageQuality: 45,
        maxWidth: 900,
      );
      if (shot == null) return;

      setState(() => _step = 'Uploading…');
      await AttendanceService.recordPunch(
        phone: widget.me.phone,
        name: widget.me.name,
        kind: kind,
        site: match.site,
        pos: pos,
        selfie: File(shot.path),
      );
      _toast('${punchLabels[kind]} recorded at ${match.site.name}');
    } on LocationException catch (e) {
      _toast(e.message, error: true);
    } catch (e) {
      _toast('Could not save. Check internet and retry. ($e)', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final date = AttendanceService.today();
    return StreamBuilder<AttendanceDay?>(
      stream: AttendanceService.watchDay(widget.me.phone, date),
      builder: (context, snap) {
        final day = snap.data;
        final done = day?.outPunch != null;
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(DateFormat('EEEE, d MMM yyyy').format(DateTime.now()),
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(day?.statusLabel ?? 'Not checked in',
                style: const TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 16),
            _row('In time', day?.inPunch),
            for (final v in day?.siteVisits ?? <Punch>[])
              _row('Site: ${v.siteName}', v),
            _row('Out time', day?.outPunch),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: _busy || done ? null : () => _punch(day),
              icon: const Icon(Icons.camera_alt),
              label: Text(done
                  ? 'Day complete'
                  : _busy
                      ? _step
                      : 'Take selfie & mark attendance'),
            ),
            const SizedBox(height: 12),
            const Text(
              'At office in the morning = In time. At a substation = Site time. '
              'At office in the evening = Out time.',
              style: TextStyle(color: Colors.black54),
            ),
            MyJobsList(me: widget.me),
          ],
        );
      },
    );
  }

  Widget _row(String label, Punch? p) => Card(
        child: ListTile(
          leading: p == null
              ? const CircleAvatar(child: Icon(Icons.schedule))
              : CircleAvatar(backgroundImage: NetworkImage(p.photoUrl)),
          title: Text(label),
          subtitle: Text(p == null
              ? 'Pending'
              : '${_time.format(p.time)} · ${p.siteName} · ±${p.accuracyM.round()} m'),
          trailing: p == null
              ? null
              : const Icon(Icons.check_circle, color: kGreen),
        ),
      );
}
