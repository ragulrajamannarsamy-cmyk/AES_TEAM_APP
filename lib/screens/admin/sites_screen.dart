import 'package:flutter/material.dart';

import '../../models/site.dart';
import '../../services/location_service.dart';
import '../../services/site_service.dart';

/// Office + substations with their GPS geofence.
/// Easiest setup: stand at the site and tap "Use my current location".
class SitesScreen extends StatelessWidget {
  const SitesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'sites',
        onPressed: () => _edit(context, null),
        icon: const Icon(Icons.add_location_alt),
        label: const Text('Add site'),
      ),
      body: StreamBuilder<List<Site>>(
        stream: SiteService.watchAll(),
        builder: (context, snap) {
          final sites = snap.data ?? [];
          if (sites.isEmpty) {
            return const Center(
                child: Text('Add the office first, then each substation.'));
          }
          return ListView(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 88),
            children: [
              for (final s in sites)
                Card(
                  child: ListTile(
                    leading: Icon(s.isOffice ? Icons.business : Icons.bolt),
                    title: Text(s.name),
                    subtitle: Text(
                        '${s.isOffice ? 'Office' : 'Substation'} · ${s.radiusM.round()} m radius\n'
                        '${s.lat.toStringAsFixed(5)}, ${s.lng.toStringAsFixed(5)}'),
                    isThreeLine: true,
                    onTap: () => _edit(context, s),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _edit(BuildContext context, Site? s) => showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        builder: (_) => _SiteForm(site: s),
      );
}

class _SiteForm extends StatefulWidget {
  final Site? site;
  const _SiteForm({this.site});

  @override
  State<_SiteForm> createState() => _SiteFormState();
}

class _SiteFormState extends State<_SiteForm> {
  late final _name = TextEditingController(text: widget.site?.name ?? '');
  late final _lat =
      TextEditingController(text: widget.site?.lat.toString() ?? '');
  late final _lng =
      TextEditingController(text: widget.site?.lng.toString() ?? '');
  late final _radius = TextEditingController(
      text: (widget.site?.radiusM ?? 200).round().toString());
  late SiteType _type = widget.site?.type ?? SiteType.substation;
  String? _msg;

  Future<void> _useHere() async {
    try {
      final p = await LocationService.currentPosition();
      setState(() {
        _lat.text = p.latitude.toStringAsFixed(6);
        _lng.text = p.longitude.toStringAsFixed(6);
        _msg = 'Location captured (±${p.accuracy.round()} m)';
      });
    } on LocationException catch (e) {
      setState(() => _msg = e.message);
    }
  }

  Future<void> _save() async {
    final lat = double.tryParse(_lat.text);
    final lng = double.tryParse(_lng.text);
    final r = double.tryParse(_radius.text);
    if (_name.text.trim().isEmpty || lat == null || lng == null || r == null) {
      setState(() => _msg = 'Fill name, location and radius.');
      return;
    }
    await SiteService.save(Site(
      id: widget.site?.id ?? '',
      name: _name.text.trim(),
      type: _type,
      lat: lat,
      lng: lng,
      radiusM: r,
    ));
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
          16, 16, 16, MediaQuery.of(context).viewInsets.bottom + 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SegmentedButton<SiteType>(
            segments: const [
              ButtonSegment(value: SiteType.office, label: Text('Office')),
              ButtonSegment(
                  value: SiteType.substation, label: Text('Substation')),
            ],
            selected: {_type},
            onSelectionChanged: (v) => setState(() {
              _type = v.first;
              _radius.text = _type == SiteType.office ? '100' : '200';
            }),
          ),
          const SizedBox(height: 12),
          TextField(
              controller: _name,
              decoration: const InputDecoration(labelText: 'Site name')),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: _useHere,
            icon: const Icon(Icons.my_location),
            label: const Text('Use my current location'),
          ),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(
                child: TextField(
                    controller: _lat,
                    keyboardType: const TextInputType.numberWithOptions(
                        decimal: true, signed: true),
                    decoration: const InputDecoration(labelText: 'Latitude'))),
            const SizedBox(width: 8),
            Expanded(
                child: TextField(
                    controller: _lng,
                    keyboardType: const TextInputType.numberWithOptions(
                        decimal: true, signed: true),
                    decoration: const InputDecoration(labelText: 'Longitude'))),
          ]),
          const SizedBox(height: 12),
          TextField(
              controller: _radius,
              keyboardType: TextInputType.number,
              decoration:
                  const InputDecoration(labelText: 'Radius (metres)')),
          if (_msg != null) ...[const SizedBox(height: 8), Text(_msg!)],
          const SizedBox(height: 16),
          FilledButton(onPressed: _save, child: const Text('Save site')),
          if (widget.site != null)
            TextButton(
              onPressed: () async {
                await SiteService.delete(widget.site!.id);
                if (context.mounted) Navigator.pop(context);
              },
              child: const Text('Delete site'),
            ),
        ],
      ),
    );
  }
}
