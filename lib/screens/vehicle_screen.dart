import 'package:flutter/material.dart';

import '../models/app_user.dart';
import '../models/vehicle_log.dart';
import '../services/vehicle_service.dart';
import '../theme.dart';
import '../util.dart';
import '../widgets/common.dart';

/// Driver: daily start/end odometer with photo; monthly km and rent.
class VehicleScreen extends StatefulWidget {
  final AppUser me;
  const VehicleScreen({super.key, required this.me});

  @override
  State<VehicleScreen> createState() => _VehicleScreenState();
}

class _VehicleScreenState extends State<VehicleScreen> {
  bool _busy = false;
  late final _vehicle = TextEditingController(text: widget.me.vehicleNo);

  String get _today => dayFmt.format(DateTime.now());

  Future<void> _start() async {
    final km = await askAmount(context, 'Starting km (odometer)',
        label: 'Odometer reading');
    if (km == null || km < 0 || !mounted) return;
    if (_vehicle.text.trim().isEmpty) {
      toast(context, 'Enter the vehicle number.', error: true);
      return;
    }
    final prev = await VehicleService.lastBefore(widget.me.phone, _today);
    if (prev?.endKm != null && km < prev!.endKm!) {
      if (mounted) {
        toast(
            context,
            'Start km cannot be less than last end km (${prev.endKm!.toStringAsFixed(0)}).',
            error: true);
      }
      return;
    }
    final photo = await takePhoto();
    if (photo == null) return;
    setState(() => _busy = true);
    try {
      await VehicleService.start(
        phone: widget.me.phone,
        name: widget.me.name,
        date: _today,
        vehicleNo: _vehicle.text.trim().toUpperCase(),
        km: km,
        photo: photo,
      );
      if (mounted) toast(context, 'Start km saved');
    } catch (_) {
      if (mounted) toast(context, 'Could not save. Retry.', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _end(VehicleLog log) async {
    final km = await askAmount(context, 'Ending km (odometer)',
        label: 'Odometer reading');
    if (km == null || !mounted) return;
    if (km < log.startKm) {
      toast(context,
          'End km must be more than start km (${log.startKm.toStringAsFixed(0)}).',
          error: true);
      return;
    }
    if (km - log.startKm > 400) {
      toast(context,
          '${(km - log.startKm).toStringAsFixed(0)} km today will be flagged for review.');
    }
    final photo = await takePhoto();
    if (photo == null) return;
    setState(() => _busy = true);
    try {
      await VehicleService.end(
          phone: widget.me.phone, date: _today, km: km, photo: photo);
      if (mounted) toast(context, 'End km saved');
    } catch (_) {
      if (mounted) toast(context, 'Could not save. Retry.', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final month = currentMonthKey();
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        StreamBuilder<VehicleLog?>(
          stream: VehicleService.watchDay(widget.me.phone, _today),
          builder: (context, snap) {
            final log = snap.data;
            return Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text('Today · ${shortDate.format(DateTime.now())}',
                        style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 12),
                    if (log == null) ...[
                      TextField(
                        controller: _vehicle,
                        textCapitalization: TextCapitalization.characters,
                        decoration: const InputDecoration(
                            labelText: 'Vehicle number (TN 58 AB 1234)'),
                      ),
                      const SizedBox(height: 12),
                      FilledButton.icon(
                        onPressed: _busy ? null : _start,
                        icon: const Icon(Icons.speed),
                        label: Text(_busy ? 'Saving…' : 'Enter start km + photo'),
                      ),
                    ] else ...[
                      KV('Vehicle', log.vehicleNo),
                      KV('Start km', log.startKm.toStringAsFixed(0)),
                      KV('End km',
                          log.endKm == null ? '—' : log.endKm!.toStringAsFixed(0)),
                      if (log.closed)
                        KV('Today', '${log.km.toStringAsFixed(0)} km',
                            strong: true),
                      const SizedBox(height: 12),
                      if (!log.closed)
                        FilledButton.icon(
                          onPressed: _busy ? null : () => _end(log),
                          icon: const Icon(Icons.flag),
                          label:
                              Text(_busy ? 'Saving…' : 'Enter end km + photo'),
                        )
                      else
                        const Text('Day complete',
                            style: TextStyle(color: kGreen)),
                    ],
                  ],
                ),
              ),
            );
          },
        ),
        StreamBuilder<List<VehicleLog>>(
          stream: VehicleService.watchMonth(widget.me.phone, month),
          builder: (context, snap) {
            final logs = snap.data ?? [];
            final total = logs.fold<double>(0, (s, l) => s + l.km);
            return Card(
              child: Column(children: [
                ListTile(
                  title: Text('${monthLabel(month)}: ${total.toStringAsFixed(0)} km'),
                  subtitle: widget.me.perKmRate > 0
                      ? Text(
                          'Rent so far: ${money(total * widget.me.perKmRate)} (${money(widget.me.perKmRate)}/km)')
                      : null,
                ),
                for (final l in logs)
                  ListTile(
                    dense: true,
                    title: Text(shortDate.format(DateTime.parse(l.date))),
                    subtitle: Text(
                        '${l.vehicleNo} · ${l.startKm.toStringAsFixed(0)} → ${l.endKm?.toStringAsFixed(0) ?? 'open'}'),
                    trailing: Text('${l.km.toStringAsFixed(0)} km'),
                  ),
              ]),
            );
          },
        ),
      ],
    );
  }
}
