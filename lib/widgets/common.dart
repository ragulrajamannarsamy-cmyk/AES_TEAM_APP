import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/requests.dart';
import '../theme.dart';
import '../util.dart';

class StatusChip extends StatelessWidget {
  final String label;
  final Color color;
  const StatusChip(this.label, this.color, {super.key});

  factory StatusChip.req(ReqStatus s) => StatusChip(
        s.name.toUpperCase(),
        switch (s) {
          ReqStatus.approved => kGreen,
          ReqStatus.rejected => kRed,
          ReqStatus.pending => kAmber,
        },
      );

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: color.withOpacity(0.12),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(label,
            style: TextStyle(
                color: color, fontWeight: FontWeight.bold, fontSize: 11)),
      );
}

class EmptyState extends StatelessWidget {
  final String text;
  const EmptyState(this.text, {super.key});

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text(text,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.black54)),
        ),
      );
}

class MonthDropdown extends StatelessWidget {
  final String value;
  final ValueChanged<String> onChanged;
  const MonthDropdown(
      {super.key, required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final months = recentMonths(12);
    if (!months.contains(value)) months.add(value);
    return DropdownButton<String>(
      value: value,
      items: [
        for (final m in months)
          DropdownMenuItem(value: m, child: Text(monthLabel(m))),
      ],
      onChanged: (v) {
        if (v != null) onChanged(v);
      },
    );
  }
}

/// Small label/value row used in summaries.
class KV extends StatelessWidget {
  final String k;
  final String v;
  final bool strong;
  const KV(this.k, this.v, {super.key, this.strong = false});

  @override
  Widget build(BuildContext context) {
    final style = strong
        ? const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)
        : null;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(children: [
        Expanded(child: Text(k, style: style)),
        Text(v, style: style),
      ]),
    );
  }
}

/// Opens a photo/PDF URL in the phone's viewer.
Future<void> openUrl(String url) =>
    launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);

/// Approve/reject dialog with an optional note.
/// Returns null when cancelled.
Future<String?> askNote(BuildContext context, String title,
    {String action = 'OK'}) async {
  final c = TextEditingController();
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: c,
        decoration: const InputDecoration(labelText: 'Note (optional)'),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel')),
        FilledButton(
            style: FilledButton.styleFrom(minimumSize: const Size(90, 40)),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(action)),
      ],
    ),
  );
  return ok == true ? c.text.trim() : null;
}

/// Asks for an amount, pre-filled with [initial]. Returns null when cancelled.
Future<double?> askAmount(BuildContext context, String title,
    {double? initial, String label = 'Amount (₹)'}) async {
  final c = TextEditingController(
      text: initial == null ? '' : initial.round().toString());
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: c,
        keyboardType: TextInputType.number,
        autofocus: true,
        decoration: InputDecoration(labelText: label),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel')),
        FilledButton(
            style: FilledButton.styleFrom(minimumSize: const Size(90, 40)),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('OK')),
      ],
    ),
  );
  if (ok != true) return null;
  return parseAmount(c.text);
}

String ageLabel(DateTime? t) {
  if (t == null) return 'just now';
  final h = DateTime.now().difference(t).inHours;
  if (h < 1) return 'less than 1 h ago';
  if (h < 48) return '$h h ago';
  return '${h ~/ 24} days ago';
}
