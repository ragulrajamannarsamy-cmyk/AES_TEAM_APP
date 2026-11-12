import 'package:flutter/material.dart';

import '../models/app_user.dart';
import '../models/payslip.dart';
import '../models/requests.dart';
import '../services/finance_service.dart';
import '../services/payroll_service.dart';
import '../theme.dart';
import '../util.dart';
import '../widgets/common.dart';

/// Worker: advance balance, carry-forward requests and payslips.
class PayScreen extends StatelessWidget {
  final AppUser me;
  const PayScreen({super.key, required this.me});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Payslip>>(
      stream: PayrollService.watchMine(me.phone),
      builder: (context, slipSnap) {
        final slips = slipSnap.data ?? [];
        return StreamBuilder<List<Advance>>(
          stream: FinanceService.myAdvances(me.phone),
          builder: (context, advSnap) {
            final balance =
                FinanceService.outstanding(advSnap.data ?? [], slips);
            return ListView(
              padding: const EdgeInsets.all(12),
              children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Advance balance'),
                        Text(money(balance),
                            style: const TextStyle(
                                fontSize: 26,
                                fontWeight: FontWeight.bold,
                                color: kNavy)),
                        const Text(
                            'Deducted from your next salary by default.',
                            style: TextStyle(color: Colors.black54)),
                        if (balance > 0) ...[
                          const SizedBox(height: 8),
                          OutlinedButton.icon(
                            icon: const Icon(Icons.redo),
                            label: Text(
                                'Carry forward from ${monthLabel(currentMonthKey())} salary'),
                            onPressed: () => _askCarryForward(context, balance),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                _CarryForwardList(me: me),
                const SizedBox(height: 8),
                Text('Payslips', style: Theme.of(context).textTheme.titleMedium),
                if (slips.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(16),
                    child: Text(
                        'Your payslip appears here on the 1st–2nd of each month after approval.'),
                  ),
                for (final p in slips)
                  Card(
                    child: ListTile(
                      title: Text(monthLabel(p.month)),
                      subtitle: Text(
                          '${_fmtDays(p.daysPresent)} days × ${money(p.perDayRate)}'),
                      trailing: Text(money(p.net),
                          style: const TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 16)),
                      onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) => PayslipScreen(slip: p))),
                    ),
                  ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _askCarryForward(BuildContext context, double balance) async {
    final month = currentMonthKey();
    final amt = await askAmount(
        context, 'Do not deduct this much from ${monthLabel(month)} salary',
        initial: balance);
    if (amt == null || amt <= 0 || !context.mounted) return;
    final reason = await askNote(context, 'Reason for carry forward',
        action: 'Send request');
    if (reason == null) return;
    await FinanceService.requestCarryForward(
        me.phone, me.name, month, amt > balance ? balance : amt, reason);
    if (context.mounted) toast(context, 'Carry forward request sent');
  }
}

String _fmtDays(double d) =>
    d == d.roundToDouble() ? d.toStringAsFixed(0) : d.toStringAsFixed(1);

class _CarryForwardList extends StatelessWidget {
  final AppUser me;
  const _CarryForwardList({required this.me});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<CarryForward>>(
      stream: FinanceService.myCarryForwards(me.phone),
      builder: (context, snap) {
        final items = (snap.data ?? []).take(3).toList();
        if (items.isEmpty) return const SizedBox.shrink();
        return Card(
          child: Column(children: [
            for (final c in items)
              ListTile(
                dense: true,
                title: Text(
                    'Carry forward ${money(c.amount)} · ${monthLabel(c.month)}'),
                subtitle: c.note?.isNotEmpty == true ? Text(c.note!) : null,
                trailing: StatusChip.req(c.status),
              ),
          ]),
        );
      },
    );
  }
}

class PayslipScreen extends StatelessWidget {
  final Payslip slip;
  const PayslipScreen({super.key, required this.slip});

  @override
  Widget build(BuildContext context) {
    final p = slip;
    return Scaffold(
      appBar: AppBar(title: Text('Payslip · ${monthLabel(p.month)}')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        Text(p.name, style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 12),
        KV('Full days (In + Out)', '${p.completeDays}'),
        KV('Paid leave days', '${p.paidLeaveDays}'),
        KV('Days paid', _fmtDays(p.daysPresent)),
        KV('Per-day rate', money(p.perDayRate)),
        const Divider(),
        KV('Salary (${_fmtDays(p.daysPresent)} × ${money(p.perDayRate)})',
            money(p.gross)),
        if (p.km > 0)
          KV('Vehicle rent (${p.km.toStringAsFixed(0)} km × ${money(p.perKmRate)})',
              money(p.kmRent)),
        KV('PF + ESI', '− ${money(p.pfEsi)}'),
        KV('Advance recovery', '− ${money(p.advanceRecovery)}'),
        if (p.adjustment != 0)
          KV('Adjustment${p.adjustmentNote.isEmpty ? '' : ' (${p.adjustmentNote})'}',
              money(p.adjustment)),
        const Divider(),
        KV('Net salary', money(p.net), strong: true),
        const SizedBox(height: 16),
        KV('Advance balance after this month', money(p.advanceBalanceAfter)),
        if (p.carriedForward > 0)
          KV('Advance carried forward', money(p.carriedForward)),
      ]),
    );
  }
}
