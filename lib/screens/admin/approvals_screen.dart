import 'package:flutter/material.dart';

import '../../models/app_user.dart';
import '../../models/bank.dart';
import '../../models/requests.dart';
import '../../services/bank_service.dart';
import '../../services/finance_service.dart';
import '../../theme.dart';
import '../../util.dart';
import '../../widgets/common.dart';
import 'leave_approvals.dart';

/// All pending requests. Target: decide within 24–48 hours.
/// Requests older than 24 h are marked in red.
class ApprovalsScreen extends StatelessWidget {
  final AppUser me;
  const ApprovalsScreen({super.key, required this.me});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 5,
      child: Column(children: [
        const TabBar(
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          tabs: [
            Tab(text: 'Leave'),
            Tab(text: 'Advance'),
            Tab(text: 'Carry fwd'),
            Tab(text: 'Expense'),
            Tab(text: 'Bank'),
          ],
        ),
        Expanded(
          child: TabBarView(children: [
            LeaveApprovals(me: me),
            _Advances(me: me),
            _CarryForwards(me: me),
            _Expenses(me: me),
            _Bank(me: me),
          ]),
        ),
      ]),
    );
  }
}

/// Managers cannot approve their own requests; the owner can.
bool _canDecide(AppUser me, BaseRequest r) => me.isOwner || r.phone != me.phone;

class _RequestCard extends StatelessWidget {
  final BaseRequest r;
  final String title;
  final List<String> lines;
  final String? fileUrl;
  final String fileLabel;
  final bool canDecide;
  final VoidCallback onApprove;
  final VoidCallback onReject;

  const _RequestCard({
    required this.r,
    required this.title,
    required this.lines,
    required this.canDecide,
    required this.onApprove,
    required this.onReject,
    this.fileUrl,
    this.fileLabel = 'View attachment',
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Expanded(
                child: Text('${r.name} · $title',
                    style: const TextStyle(fontWeight: FontWeight.bold)),
              ),
              Text(ageLabel(r.createdAt),
                  style: TextStyle(
                      color: r.overdue ? kRed : Colors.black54,
                      fontWeight:
                          r.overdue ? FontWeight.bold : FontWeight.normal)),
            ]),
            for (final l in lines.where((l) => l.isNotEmpty)) Text(l),
            if (fileUrl != null && fileUrl!.isNotEmpty)
              TextButton.icon(
                icon: const Icon(Icons.attach_file),
                label: Text(fileLabel),
                onPressed: () => openUrl(fileUrl!),
              ),
            if (!canDecide)
              const Text('Your own request: the owner decides.',
                  style: TextStyle(color: Colors.black54))
            else
              Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                OutlinedButton(onPressed: onReject, child: const Text('Reject')),
                const SizedBox(width: 8),
                FilledButton(
                  style:
                      FilledButton.styleFrom(minimumSize: const Size(100, 40)),
                  onPressed: onApprove,
                  child: const Text('Approve'),
                ),
              ]),
          ],
        ),
      ),
    );
  }
}

Widget _list<T extends BaseRequest>(
    Stream<List<T>> stream, Widget Function(T) card, String empty) {
  return StreamBuilder<List<T>>(
    stream: stream,
    builder: (context, snap) {
      final items = snap.data ?? [];
      if (items.isEmpty) return EmptyState(empty);
      return ListView(
        padding: const EdgeInsets.all(12),
        children: [for (final i in items) card(i)],
      );
    },
  );
}

class _Advances extends StatelessWidget {
  final AppUser me;
  const _Advances({required this.me});

  @override
  Widget build(BuildContext context) => _list<Advance>(
        FinanceService.pendingAdvances(),
        (a) => _RequestCard(
          r: a,
          title: 'Advance ${money(a.amount)}',
          lines: [a.reason],
          canDecide: _canDecide(me, a),
          onApprove: () async {
            final amt = await askAmount(context, 'Approve amount',
                initial: a.amount);
            if (amt == null || amt <= 0 || !context.mounted) return;
            final note = await askNote(context, 'Approve ${money(amt)}?',
                action: 'Approve');
            if (note == null) return;
            await FinanceService.review(FinanceService.advances, a.id,
                approve: true,
                reviewer: me.name,
                note: note,
                approvedAmount: amt);
          },
          onReject: () async {
            final note =
                await askNote(context, 'Reject advance?', action: 'Reject');
            if (note == null) return;
            await FinanceService.review(FinanceService.advances, a.id,
                approve: false, reviewer: me.name, note: note, approvedAmount: 0);
          },
        ),
        'No pending advance requests.',
      );
}

class _CarryForwards extends StatelessWidget {
  final AppUser me;
  const _CarryForwards({required this.me});

  @override
  Widget build(BuildContext context) => _list<CarryForward>(
        FinanceService.pendingCarryForwards(),
        (c) => _RequestCard(
          r: c,
          title: 'Carry forward ${money(c.amount)}',
          lines: ['Do not deduct from ${monthLabel(c.month)} salary', c.reason],
          canDecide: _canDecide(me, c),
          onApprove: () => _decide(context, c, true),
          onReject: () => _decide(context, c, false),
        ),
        'No pending carry-forward requests.',
      );

  Future<void> _decide(BuildContext context, CarryForward c, bool ok) async {
    final note = await askNote(
        context, ok ? 'Approve carry forward?' : 'Reject carry forward?',
        action: ok ? 'Approve' : 'Reject');
    if (note == null) return;
    await FinanceService.review(FinanceService.carryForwards, c.id,
        approve: ok, reviewer: me.name, note: note);
  }
}

class _Expenses extends StatelessWidget {
  final AppUser me;
  const _Expenses({required this.me});

  @override
  Widget build(BuildContext context) => _list<Expense>(
        FinanceService.pendingExpenses(),
        (e) => _RequestCard(
          r: e,
          title: '${e.category} ${money(e.amount)}',
          lines: [e.siteName, e.details],
          fileUrl: e.billUrl,
          fileLabel: 'View bill',
          canDecide: _canDecide(me, e),
          onApprove: () => _decide(context, e, true),
          onReject: () => _decide(context, e, false),
        ),
        'No pending expense claims.',
      );

  Future<void> _decide(BuildContext context, Expense e, bool ok) async {
    final note = await askNote(
        context, ok ? 'Approve ${money(e.amount)}?' : 'Reject claim?',
        action: ok ? 'Approve' : 'Reject');
    if (note == null) return;
    await FinanceService.review(FinanceService.expenses, e.id,
        approve: ok, reviewer: me.name, note: note);
  }
}

class _Bank extends StatelessWidget {
  final AppUser me;
  const _Bank({required this.me});

  @override
  Widget build(BuildContext context) => _list<BankRequest>(
        BankService.pending(),
        (b) => _RequestCard(
          r: b,
          title: 'Bank details',
          lines: [
            'Holder: ${b.details.holderName}',
            'Account: ${b.details.accountNumber}',
            'IFSC: ${b.details.ifsc} · ${b.details.bankName}, ${b.details.branch}',
            if (b.details.holderName.toLowerCase().trim() !=
                b.name.toLowerCase().trim())
              '⚠ Holder name differs from staff name (${b.name})',
          ],
          fileUrl: b.details.proofUrl,
          fileLabel: 'View cheque / passbook',
          canDecide: _canDecide(me, b),
          onApprove: () => _decide(context, b, true),
          onReject: () => _decide(context, b, false),
        ),
        'No bank details waiting for verification.',
      );

  Future<void> _decide(BuildContext context, BankRequest b, bool ok) async {
    final note = await askNote(
        context,
        ok
            ? 'Verify ${maskAccount(b.details.accountNumber)}? Salary will go to this account.'
            : 'Reject bank details?',
        action: ok ? 'Verify' : 'Reject');
    if (note == null) return;
    await BankService.review(b, approve: ok, reviewer: me.name, note: note);
  }
}
