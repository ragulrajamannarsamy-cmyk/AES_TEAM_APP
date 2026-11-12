import 'package:flutter/material.dart';

import '../../models/app_user.dart';
import '../../models/payslip.dart';
import '../../services/bank_service.dart';
import '../../services/payroll_service.dart';
import '../../theme.dart';
import '../../util.dart';
import '../../widgets/common.dart';

/// Monthly payroll: calculate drafts, review/adjust each person,
/// approve, and export the bank-transfer sheet.
///
/// Net = Days × Per-day rate + Km × Per-km rate − PF+ESI − Advance + Adjustment
class PayrollScreen extends StatefulWidget {
  final AppUser me;
  const PayrollScreen({super.key, required this.me});

  @override
  State<PayrollScreen> createState() => _PayrollScreenState();
}

class _PayrollScreenState extends State<PayrollScreen> {
  // On the 1st–2nd of a month, last month is the one to pay.
  String _month = prevMonthKey();
  bool _busy = false;
  String _filter = '';

  Future<void> _calculate(List<Payslip> existing) async {
    final approved = existing.where((p) => p.approved).length;
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('Calculate ${monthLabel(_month)}?'),
        content: Text(
            'Builds salary from attendance, approved leave, km logs and advances '
            'for every active worker and driver.\n\n'
            '${existing.isEmpty ? '' : 'Drafts and your edits to them will be recalculated. '}'
            '${approved == 0 ? '' : '$approved approved payslips stay unchanged.'}'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('Cancel')),
          FilledButton(
              style: FilledButton.styleFrom(minimumSize: const Size(110, 40)),
              onPressed: () => Navigator.pop(c, true),
              child: const Text('Calculate')),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _busy = true);
    try {
      final n = await PayrollService.calculate(_month);
      if (mounted) toast(context, '$n payslips calculated');
    } catch (e) {
      if (mounted) toast(context, 'Calculation failed: $e', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _approveAll(List<Payslip> slips) async {
    final drafts = slips.where((p) => !p.approved).toList();
    if (drafts.isEmpty) return;
    final total = drafts.fold<double>(0, (s, p) => s + p.net);
    final note = await askNote(
        context, 'Approve ${drafts.length} payslips · ${money(total)}?',
        action: 'Approve');
    if (note == null) return;
    await PayrollService.approveAll(drafts, widget.me.name);
    if (mounted) toast(context, 'Approved. Workers can now see their payslips.');
  }

  /// Bank-transfer sheet for approved payslips with net > 0.
  Future<void> _exportBank(List<Payslip> slips) async {
    final paid = slips.where((p) => p.approved && p.net > 0).toList();
    if (paid.isEmpty) {
      toast(context, 'Approve payslips first.', error: true);
      return;
    }
    final banks = await BankService.all();
    final missing = paid.where((p) => banks[p.phone] == null).toList();
    final rows = <List<Object?>>[
      ['S.No', 'Name', 'Mobile', 'Account holder', 'Account number', 'IFSC',
        'Bank', 'Branch', 'Net salary (Rs)', 'Remarks'],
      for (var i = 0; i < paid.length; i++)
        () {
          final p = paid[i];
          final b = banks[p.phone];
          return [
            i + 1,
            p.name,
            p.phone,
            b?.holderName ?? '',
            // Leading apostrophe keeps Excel from turning it into 1.23E+11
            b == null ? 'MISSING' : "'${b.accountNumber}",
            b?.ifsc ?? '',
            b?.bankName ?? '',
            b?.branch ?? '',
            p.net.round(),
            'Salary ${monthLabel(_month)}',
          ];
        }(),
      [],
      ['', 'TOTAL', '', '', '', '', '', '',
        paid.fold<double>(0, (s, p) => s + p.net).round(), ''],
    ];
    await shareCsv('salary_transfer_$_month.csv', rows);
    if (missing.isNotEmpty && mounted) {
      toast(context,
          '${missing.length} without verified bank details: ${missing.map((p) => p.name).take(5).join(', ')}',
          error: true);
    }
  }

  /// Full payroll register (all columns) for accounts / records.
  Future<void> _exportRegister(List<Payslip> slips) => shareCsv(
        'payroll_register_$_month.csv',
        [
          ['Name', 'Mobile', 'Full days', 'Incomplete days', 'Paid leave',
            'Days paid', 'Per-day rate', 'Gross', 'Km', 'Per-km rate',
            'Km rent', 'PF+ESI', 'Advance outstanding', 'Advance recovered',
            'Advance carried fwd', 'Adjustment', 'Adjustment note', 'Net',
            'Status'],
          for (final p in slips)
            [p.name, p.phone, p.completeDays, p.incompleteDays,
              p.paidLeaveDays, p.daysPresent, p.perDayRate, p.gross.round(),
              p.km, p.perKmRate, p.kmRent.round(), p.pfEsi,
              p.advanceOutstanding.round(), p.advanceRecovery.round(),
              p.carriedForward.round(), p.adjustment.round(),
              p.adjustmentNote, p.net.round(), p.status],
        ],
      );

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Payslip>>(
      stream: PayrollService.watchMonth(_month),
      builder: (context, snap) {
        final slips = snap.data ?? [];
        final shown = _filter.isEmpty
            ? slips
            : slips
                .where((p) =>
                    p.name.toLowerCase().contains(_filter.toLowerCase()))
                .toList();
        final total = slips.fold<double>(0, (s, p) => s + p.net);
        final approved = slips.where((p) => p.approved).length;
        final adv = slips.fold<double>(0, (s, p) => s + p.advanceRecovery);
        final pf = slips.fold<double>(0, (s, p) => s + p.pfEsi);

        return ListView(
          padding: const EdgeInsets.all(12),
          children: [
            Row(children: [
              MonthDropdown(
                  value: _month, onChanged: (m) => setState(() => _month = m)),
              const Spacer(),
              FilledButton.icon(
                style: FilledButton.styleFrom(minimumSize: const Size(0, 40)),
                onPressed: _busy ? null : () => _calculate(slips),
                icon: const Icon(Icons.calculate),
                label: Text(_busy
                    ? 'Calculating…'
                    : slips.isEmpty
                        ? 'Calculate'
                        : 'Recalculate'),
              ),
            ]),
            const SizedBox(height: 8),
            if (slips.isEmpty)
              const EmptyState(
                  'No payroll for this month yet.\nTap Calculate after the month ends (1st–2nd).')
            else ...[
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(children: [
                    KV('People', '${slips.length}'),
                    KV('Approved', '$approved / ${slips.length}'),
                    KV('PF + ESI deducted', money(pf)),
                    KV('Advance recovered', money(adv)),
                    KV('Total net salary', money(total), strong: true),
                  ]),
                ),
              ),
              Wrap(spacing: 8, runSpacing: 8, children: [
                if (approved < slips.length)
                  FilledButton.icon(
                    style: FilledButton.styleFrom(
                        minimumSize: const Size(0, 40),
                        backgroundColor: kGreen),
                    onPressed: () => _approveAll(slips),
                    icon: const Icon(Icons.done_all),
                    label: const Text('Approve all'),
                  ),
                OutlinedButton.icon(
                  onPressed: () => _exportBank(slips),
                  icon: const Icon(Icons.account_balance),
                  label: const Text('Bank transfer sheet'),
                ),
                OutlinedButton.icon(
                  onPressed: () => _exportRegister(slips),
                  icon: const Icon(Icons.table_view),
                  label: const Text('Payroll register'),
                ),
              ]),
              const SizedBox(height: 8),
              TextField(
                decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.search),
                    labelText: 'Search name',
                    isDense: true),
                onChanged: (v) => setState(() => _filter = v),
              ),
              const SizedBox(height: 4),
              for (final p in shown)
                Card(
                  child: ListTile(
                    title: Text(p.name),
                    subtitle: Text(
                        '${_d(p.daysPresent)} days × ${money(p.perDayRate)}'
                        '${p.km > 0 ? ' · ${p.km.round()} km' : ''}'
                        '${p.advanceRecovery > 0 ? ' · Adv −${money(p.advanceRecovery)}' : ''}'
                        '${p.incompleteDays > 0 ? ' · ${p.incompleteDays} incomplete' : ''}'),
                    trailing: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(money(p.net),
                            style:
                                const TextStyle(fontWeight: FontWeight.bold)),
                        const SizedBox(height: 2),
                        p.approved
                            ? const StatusChip('APPROVED', kGreen)
                            : const StatusChip('DRAFT', kAmber),
                      ],
                    ),
                    onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) =>
                                PayslipEditScreen(slip: p, me: widget.me))),
                  ),
                ),
            ],
          ],
        );
      },
    );
  }
}

String _d(double v) => v == v.roundToDouble() ? '${v.round()}' : '$v';

/// Review one payslip. Drafts can be adjusted; approved ones are read-only
/// unless the owner reopens them.
class PayslipEditScreen extends StatefulWidget {
  final Payslip slip;
  final AppUser me;
  const PayslipEditScreen({super.key, required this.slip, required this.me});

  @override
  State<PayslipEditScreen> createState() => _PayslipEditScreenState();
}

class _PayslipEditScreenState extends State<PayslipEditScreen> {
  late Payslip _p = widget.slip;
  late final _days = TextEditingController(text: _d(_p.daysPresent));
  late final _km = TextEditingController(text: _d(_p.km));
  late final _adv =
      TextEditingController(text: _p.advanceRecovery.round().toString());
  late final _adj =
      TextEditingController(text: _p.adjustment.round().toString());
  late final _note = TextEditingController(text: _p.adjustmentNote);
  bool _busy = false;

  void _recalc() {
    setState(() {
      _p = _p.copyWith(
        daysPresent: double.tryParse(_days.text) ?? _p.daysPresent,
        km: double.tryParse(_km.text) ?? _p.km,
        advanceRecovery: parseAmount(_adv.text) ?? _p.advanceRecovery,
        adjustment: double.tryParse(_adj.text.trim()) ?? _p.adjustment,
        adjustmentNote: _note.text.trim(),
      );
    });
  }

  String? _validate() {
    if (_p.advanceRecovery > _p.advanceOutstanding + 0.5) {
      return 'Advance recovery is more than outstanding (${money(_p.advanceOutstanding)}).';
    }
    if (_p.adjustment != 0 && _p.adjustmentNote.isEmpty) {
      return 'Add a note for the adjustment.';
    }
    if (_p.net < 0) return 'Net salary cannot be negative.';
    return null;
  }

  Future<void> _save({bool approve = false}) async {
    _recalc();
    final err = _validate();
    if (err != null) {
      toast(context, err, error: true);
      return;
    }
    setState(() => _busy = true);
    try {
      await PayrollService.save(_p.copyWith(status: 'draft'));
      if (approve) {
        await PayrollService.setStatus(_p, 'approved', widget.me.name);
      }
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) toast(context, 'Could not save: $e', error: true);
      setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final locked = _p.approved;
    final carry = _p.advanceOutstanding - _p.advanceRecovery;
    return Scaffold(
      appBar: AppBar(title: Text('${_p.name} · ${monthLabel(_p.month)}')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('Attendance', style: Theme.of(context).textTheme.titleSmall),
          KV('Full days (In + Out)', '${_p.completeDays}'),
          KV('Approved paid leave', '${_p.paidLeaveDays}'),
          KV('Incomplete days (no Out)', '${_p.incompleteDays}'),
          if (_p.incompleteDays > 0)
            const Text(
                'Incomplete days are not paid. Add them to Days paid if the person worked.',
                style: TextStyle(color: kRed, fontSize: 12)),
          const Divider(height: 24),
          TextField(
            controller: _days,
            enabled: !locked,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
                labelText: 'Days paid',
                helperText: '× ${money(_p.perDayRate)} per day'),
            onChanged: (_) => _recalc(),
          ),
          if (_p.perKmRate > 0 || _p.km > 0) ...[
            const SizedBox(height: 12),
            TextField(
              controller: _km,
              enabled: !locked,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                  labelText: 'Km driven',
                  helperText: '× ${money(_p.perKmRate)} per km'),
              onChanged: (_) => _recalc(),
            ),
          ],
          const SizedBox(height: 12),
          TextField(
            controller: _adv,
            enabled: !locked,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
                labelText: 'Advance recovery (₹)',
                helperText:
                    'Outstanding ${money(_p.advanceOutstanding)}'
                    '${_p.carriedForward > 0 ? ' · ${money(_p.carriedForward)} carry-forward approved' : ''}'),
            onChanged: (_) => _recalc(),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _adj,
            enabled: !locked,
            keyboardType: const TextInputType.numberWithOptions(signed: true),
            decoration: const InputDecoration(
                labelText: 'Adjustment (₹, use − to deduct)'),
            onChanged: (_) => _recalc(),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _note,
            enabled: !locked,
            decoration: const InputDecoration(labelText: 'Adjustment note'),
            onChanged: (_) => _recalc(),
          ),
          const Divider(height: 32),
          KV('Gross (${_d(_p.daysPresent)} × ${money(_p.perDayRate)})',
              money(_p.gross)),
          if (_p.kmRent > 0)
            KV('Km rent (${_d(_p.km)} × ${money(_p.perKmRate)})',
                money(_p.kmRent)),
          KV('PF + ESI', '− ${money(_p.pfEsi)}'),
          KV('Advance recovery', '− ${money(_p.advanceRecovery)}'),
          if (_p.adjustment != 0)
            KV('Adjustment', _p.adjustment > 0
                ? '+ ${money(_p.adjustment)}'
                : '− ${money(-_p.adjustment)}'),
          KV('Net salary', money(_p.net), strong: true),
          if (carry > 0.5)
            Text('${money(carry)} advance carries to next month.',
                style: const TextStyle(color: Colors.black54)),
          const SizedBox(height: 24),
          if (!locked) ...[
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: kGreen),
              onPressed: _busy ? null : () => _save(approve: true),
              child: const Text('Save & approve'),
            ),
            const SizedBox(height: 8),
            OutlinedButton(
              onPressed: _busy ? null : () => _save(),
              child: const Text('Save draft'),
            ),
          ] else if (widget.me.isOwner)
            OutlinedButton(
              onPressed: () async {
                await PayrollService.setStatus(_p, 'draft', widget.me.name);
                if (context.mounted) Navigator.pop(context);
              },
              child: const Text('Reopen for editing (owner)'),
            )
          else
            const Text('Approved. Only the owner can reopen it.'),
        ],
      ),
    );
  }
}
