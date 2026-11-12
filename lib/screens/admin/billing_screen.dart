import 'package:flutter/material.dart';

import '../../models/bill.dart';
import '../../services/billing_service.dart';
import '../../theme.dart';
import '../../util.dart';
import '../../widgets/common.dart';

Color billColor(String status) => switch (status) {
      'Paid' || 'Accepted' || 'Invoiced' => kGreen,
      'Rejected' || 'Cancelled' => kRed,
      'Part paid' || 'Sent' => kNavy,
      _ => kAmber,
    };

/// Quotes and tax invoices with GST, PDF on company details,
/// payment tracking.
class BillingScreen extends StatelessWidget {
  const BillingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const DefaultTabController(
      length: 2,
      child: Column(children: [
        TabBar(tabs: [Tab(text: 'Quotes'), Tab(text: 'Invoices')]),
        Expanded(
          child: TabBarView(children: [
            _BillList(kind: BillKind.quote),
            _BillList(kind: BillKind.invoice),
          ]),
        ),
      ]),
    );
  }
}

class _BillList extends StatelessWidget {
  final BillKind kind;
  const _BillList({required this.kind});

  @override
  Widget build(BuildContext context) {
    final isQuote = kind == BillKind.quote;
    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'new_${kind.name}',
        onPressed: () => Navigator.push(context,
            MaterialPageRoute(builder: (_) => BillFormScreen(kind: kind))),
        icon: const Icon(Icons.add),
        label: Text(isQuote ? 'New quote' : 'New invoice'),
      ),
      body: StreamBuilder<List<Bill>>(
        stream: BillingService.watch(kind),
        builder: (context, snap) {
          final bills = snap.data ?? [];
          if (bills.isEmpty) {
            return EmptyState(isQuote
                ? 'No quotes yet.'
                : 'No invoices yet. Create one, or convert an accepted quote.');
          }
          final live = bills.where((b) => b.status != 'Cancelled');
          final billed = live.fold<double>(0, (s, b) => s + b.total);
          final received = live.fold<double>(0, (s, b) => s + b.paidAmount);
          return ListView(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 88),
            children: [
              if (!isQuote)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(children: [
                      KV('Invoiced', money(billed)),
                      KV('Received', money(received)),
                      KV('Pending', money(billed - received), strong: true),
                    ]),
                  ),
                ),
              for (final b in bills)
                Card(
                  child: ListTile(
                    title: Text('${b.number} · ${b.clientName}'),
                    subtitle: Text([
                      shortDate.format(b.date),
                      if (b.subject.isNotEmpty) b.subject,
                      if (!isQuote && b.balance > 0.5 && b.status != 'Cancelled')
                        'Due ${money(b.balance)}',
                    ].join(' · ')),
                    trailing: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(money(b.total),
                            style:
                                const TextStyle(fontWeight: FontWeight.bold)),
                        const SizedBox(height: 2),
                        StatusChip(b.status.toUpperCase(), billColor(b.status)),
                      ],
                    ),
                    onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => BillViewScreen(bill: b))),
                  ),
                ),
              if (!isQuote)
                OutlinedButton.icon(
                  icon: const Icon(Icons.download),
                  label: const Text('Export invoice register'),
                  onPressed: () => shareCsv('invoices.csv', [
                    ['Number', 'Date', 'Client', 'GSTIN', 'Subject',
                      'Taxable', 'GST %', 'GST', 'Total', 'Received',
                      'Balance', 'Status'],
                    for (final b in bills)
                      [b.number, dayFmt.format(b.date), b.clientName,
                        b.clientGstin, b.subject, b.subtotal.round(),
                        b.gstPct, b.gst.round(), b.total.round(),
                        b.paidAmount.round(), b.balance.round(), b.status],
                  ]),
                ),
            ],
          );
        },
      ),
    );
  }
}

/// Read-only view with actions: PDF, edit, status, payment, convert.
class BillViewScreen extends StatelessWidget {
  final Bill bill;
  const BillViewScreen({super.key, required this.bill});

  @override
  Widget build(BuildContext context) {
    final b = bill;
    final isQuote = b.kind == BillKind.quote;
    return Scaffold(
      appBar: AppBar(
        title: Text(b.number),
        actions: [
          IconButton(
            tooltip: 'Edit',
            icon: const Icon(Icons.edit),
            onPressed: () => Navigator.pushReplacement(
                context,
                MaterialPageRoute(
                    builder: (_) => BillFormScreen(kind: b.kind, bill: b))),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Row(children: [
            Expanded(
              child: Text(b.kindLabel,
                  style: Theme.of(context).textTheme.titleMedium),
            ),
            StatusChip(b.status.toUpperCase(), billColor(b.status)),
          ]),
          const SizedBox(height: 8),
          KV('Date', shortDate.format(b.date)),
          KV('Client', b.clientName),
          if (b.clientGstin.isNotEmpty) KV('GSTIN', b.clientGstin),
          if (b.subject.isNotEmpty) KV('Subject', b.subject),
          const Divider(height: 24),
          for (final i in b.items)
            KV('${i.description} (${_q(i.qty)} ${i.unit} × ${money(i.rate)})',
                money(i.amount)),
          const Divider(height: 24),
          KV('Subtotal', money(b.subtotal)),
          KV('GST ${b.gstPct.toStringAsFixed(0)}%', money(b.gst)),
          KV('Total', money(b.total), strong: true),
          if (!isQuote) ...[
            KV('Received', money(b.paidAmount)),
            KV('Balance', money(b.balance), strong: true),
          ],
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: () => BillingService.sharePdf(b),
            icon: const Icon(Icons.picture_as_pdf),
            label: const Text('Share PDF'),
          ),
          const SizedBox(height: 8),
          if (isQuote && b.status != 'Invoiced')
            OutlinedButton.icon(
              icon: const Icon(Icons.receipt_long),
              label: const Text('Convert to invoice'),
              onPressed: () async {
                await BillingService.convertToInvoice(b);
                if (context.mounted) {
                  toast(context, 'Invoice created. See the Invoices tab.');
                  Navigator.pop(context);
                }
              },
            ),
          if (!isQuote && b.balance > 0.5 && b.status != 'Cancelled')
            OutlinedButton.icon(
              icon: const Icon(Icons.payments),
              label: const Text('Record payment received'),
              onPressed: () async {
                final amt = await askAmount(context, 'Payment received',
                    initial: b.balance);
                if (amt == null || amt <= 0) return;
                await BillingService.recordPayment(b, amt);
                if (context.mounted) Navigator.pop(context);
              },
            ),
          const SizedBox(height: 8),
          Wrap(spacing: 8, children: [
            for (final s in billStatuses[b.kind]!)
              if (s != b.status)
                ActionChip(
                  label: Text('Mark $s'),
                  onPressed: () async {
                    await BillingService.save(_withStatus(b, s));
                    if (context.mounted) Navigator.pop(context);
                  },
                ),
          ]),
        ],
      ),
    );
  }
}

String _q(double v) => v == v.roundToDouble() ? '${v.round()}' : '$v';

Bill _withStatus(Bill b, String status) => Bill(
      id: b.id,
      kind: b.kind,
      number: b.number,
      date: b.date,
      clientName: b.clientName,
      clientAddress: b.clientAddress,
      clientGstin: b.clientGstin,
      subject: b.subject,
      items: b.items,
      gstPct: b.gstPct,
      status: status,
      paidAmount: b.paidAmount,
      notes: b.notes,
      fromQuoteId: b.fromQuoteId,
    );

class _ItemRow {
  final desc = TextEditingController();
  final qty = TextEditingController(text: '1');
  final unit = TextEditingController(text: 'Nos');
  final rate = TextEditingController();

  _ItemRow([LineItem? i]) {
    if (i != null) {
      desc.text = i.description;
      qty.text = _q(i.qty);
      unit.text = i.unit;
      rate.text = _q(i.rate);
    }
  }

  LineItem? toItem() {
    final q = double.tryParse(qty.text.trim());
    final r = parseAmount(rate.text);
    if (desc.text.trim().isEmpty || q == null || r == null) return null;
    return LineItem(
        description: desc.text.trim(),
        qty: q,
        unit: unit.text.trim().isEmpty ? 'Nos' : unit.text.trim(),
        rate: r);
  }
}

class BillFormScreen extends StatefulWidget {
  final BillKind kind;
  final Bill? bill;
  const BillFormScreen({super.key, required this.kind, this.bill});

  @override
  State<BillFormScreen> createState() => _BillFormScreenState();
}

class _BillFormScreenState extends State<BillFormScreen> {
  late final b = widget.bill;
  late final _client = TextEditingController(text: b?.clientName ?? '');
  late final _addr = TextEditingController(text: b?.clientAddress ?? '');
  late final _gstin = TextEditingController(text: b?.clientGstin ?? '');
  late final _subject = TextEditingController(text: b?.subject ?? '');
  late final _notes = TextEditingController(
      text: b?.notes ??
          (widget.kind == BillKind.quote
              ? 'Validity: 30 days.\nPayment: 50% advance, balance on completion.'
              : 'Payment due within 30 days.'));
  late double _gstPct = b?.gstPct ?? 18;
  late DateTime _date = b?.date ?? DateTime.now();
  late final List<_ItemRow> _rows =
      b == null || b!.items.isEmpty ? [_ItemRow()] : b!.items.map(_ItemRow.new).toList();
  bool _busy = false;

  List<LineItem> get _items =>
      _rows.map((r) => r.toItem()).whereType<LineItem>().toList();

  double get _subtotal => _items.fold(0, (s, i) => s + i.amount);

  Future<void> _save() async {
    final items = _items;
    if (_client.text.trim().isEmpty || items.isEmpty) {
      toast(context, 'Enter client name and at least one complete item.',
          error: true);
      return;
    }
    if (items.length < _rows.length) {
      toast(context, 'Some item rows are incomplete. Fill or remove them.',
          error: true);
      return;
    }
    setState(() => _busy = true);
    try {
      final id = await BillingService.save(Bill(
        id: b?.id ?? '',
        kind: widget.kind,
        number: b?.number ?? '',
        date: _date,
        clientName: _client.text.trim(),
        clientAddress: _addr.text.trim(),
        clientGstin: _gstin.text.trim().toUpperCase(),
        subject: _subject.text.trim(),
        items: items,
        gstPct: _gstPct,
        status: b?.status ?? billStatuses[widget.kind]!.first,
        paidAmount: b?.paidAmount ?? 0,
        notes: _notes.text.trim(),
        fromQuoteId: b?.fromQuoteId,
      ));
      if (mounted) {
        toast(context, 'Saved');
        Navigator.pop(context, id);
      }
    } catch (e) {
      if (mounted) toast(context, 'Could not save: $e', error: true);
      setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final sub = _subtotal;
    final gst = sub * _gstPct / 100;
    final label = widget.kind == BillKind.quote ? 'quote' : 'invoice';
    return Scaffold(
      appBar: AppBar(
          title: Text(b == null ? 'New $label' : 'Edit ${b!.number}')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          OutlinedButton.icon(
            icon: const Icon(Icons.event),
            label: Text('Date ${shortDate.format(_date)}'),
            onPressed: () async {
              final d = await showDatePicker(
                  context: context,
                  initialDate: _date,
                  firstDate: DateTime(2025),
                  lastDate: DateTime(2030));
              if (d != null) setState(() => _date = d);
            },
          ),
          const SizedBox(height: 12),
          TextField(
              controller: _client,
              decoration: const InputDecoration(
                  labelText: 'Client name', hintText: 'e.g. TNEB, Madurai')),
          const SizedBox(height: 12),
          TextField(
              controller: _addr,
              maxLines: 2,
              decoration: const InputDecoration(labelText: 'Client address')),
          const SizedBox(height: 12),
          TextField(
              controller: _gstin,
              textCapitalization: TextCapitalization.characters,
              decoration:
                  const InputDecoration(labelText: 'Client GSTIN (optional)')),
          const SizedBox(height: 12),
          TextField(
              controller: _subject,
              decoration: const InputDecoration(labelText: 'Subject / work')),
          const SizedBox(height: 16),
          Text('Items', style: Theme.of(context).textTheme.titleSmall),
          for (var i = 0; i < _rows.length; i++)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: Column(children: [
                  Row(children: [
                    Expanded(
                      child: TextField(
                        controller: _rows[i].desc,
                        decoration: InputDecoration(
                            labelText: 'Item ${i + 1} description',
                            isDense: true),
                        onChanged: (_) => setState(() {}),
                      ),
                    ),
                    if (_rows.length > 1)
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => setState(() => _rows.removeAt(i)),
                      ),
                  ]),
                  const SizedBox(height: 8),
                  Row(children: [
                    Expanded(
                      child: TextField(
                        controller: _rows[i].qty,
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true),
                        decoration: const InputDecoration(
                            labelText: 'Qty', isDense: true),
                        onChanged: (_) => setState(() {}),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: TextField(
                        controller: _rows[i].unit,
                        decoration: const InputDecoration(
                            labelText: 'Unit', isDense: true),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      flex: 2,
                      child: TextField(
                        controller: _rows[i].rate,
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true),
                        decoration: const InputDecoration(
                            labelText: 'Rate (₹)', isDense: true),
                        onChanged: (_) => setState(() {}),
                      ),
                    ),
                  ]),
                ]),
              ),
            ),
          TextButton.icon(
            onPressed: () => setState(() => _rows.add(_ItemRow())),
            icon: const Icon(Icons.add),
            label: const Text('Add item'),
          ),
          const SizedBox(height: 8),
          DropdownButtonFormField<double>(
            value: [0.0, 5.0, 12.0, 18.0, 28.0].contains(_gstPct) ? _gstPct : 18,
            decoration: const InputDecoration(labelText: 'GST'),
            items: [
              for (final g in [0.0, 5.0, 12.0, 18.0, 28.0])
                DropdownMenuItem(value: g, child: Text('${g.round()}%')),
            ],
            onChanged: (v) => setState(() => _gstPct = v ?? 18),
          ),
          const SizedBox(height: 12),
          KV('Subtotal', money(sub)),
          KV('GST ${_gstPct.round()}%', money(gst)),
          KV('Total', money(sub + gst), strong: true),
          const SizedBox(height: 12),
          TextField(
              controller: _notes,
              maxLines: 3,
              decoration: const InputDecoration(labelText: 'Terms / notes')),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: _busy ? null : _save,
            child: Text(_busy ? 'Saving…' : 'Save $label'),
          ),
          if (b != null) ...[
            const SizedBox(height: 8),
            TextButton(
              onPressed: () async {
                final n = await askNote(context, 'Delete ${b!.number}?',
                    action: 'Delete');
                if (n == null) return;
                await BillingService.delete(b!.id);
                if (context.mounted) Navigator.pop(context);
              },
              child: const Text('Delete', style: TextStyle(color: kRed)),
            ),
          ],
        ],
      ),
    );
  }
}
