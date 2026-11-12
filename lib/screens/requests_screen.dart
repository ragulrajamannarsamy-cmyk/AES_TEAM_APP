import 'dart:io';

import 'package:flutter/material.dart';

import '../models/app_user.dart';
import '../models/requests.dart';
import '../models/site.dart';
import '../services/finance_service.dart';
import '../services/site_service.dart';
import '../theme.dart';
import '../util.dart';
import '../widgets/common.dart';
import 'leave_screen.dart';

/// Worker requests: Leave | Advance | Expense.
class RequestsScreen extends StatelessWidget {
  final AppUser me;
  const RequestsScreen({super.key, required this.me});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Column(children: [
        const TabBar(tabs: [
          Tab(text: 'Leave'),
          Tab(text: 'Advance'),
          Tab(text: 'Expense'),
        ]),
        Expanded(
          child: TabBarView(children: [
            LeaveScreen(me: me),
            _AdvanceTab(me: me),
            _ExpenseTab(me: me),
          ]),
        ),
      ]),
    );
  }
}

// ---------------- Advance ----------------

class _AdvanceTab extends StatelessWidget {
  final AppUser me;
  const _AdvanceTab({required this.me});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'adv',
        onPressed: () => Navigator.push(context,
            MaterialPageRoute(builder: (_) => AdvanceFormScreen(me: me))),
        icon: const Icon(Icons.add),
        label: const Text('Request advance'),
      ),
      body: StreamBuilder<List<Advance>>(
        stream: FinanceService.myAdvances(me.phone),
        builder: (context, snap) {
          final items = snap.data ?? [];
          if (items.isEmpty) {
            return const EmptyState(
                'No advance requests.\nApproval within 24–48 hours. The amount is deducted from your next salary.');
          }
          return ListView(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 88),
            children: [
              for (final a in items)
                Card(
                  child: ListTile(
                    title: Text(money(a.amount)),
                    subtitle: Text([
                      a.reason,
                      'Requested ${ageLabel(a.createdAt)}',
                      if (a.status == ReqStatus.approved &&
                          a.approvedAmount != a.amount)
                        'Approved ${money(a.approvedAmount)}',
                      if (a.note?.isNotEmpty == true) 'Note: ${a.note}',
                    ].join('\n')),
                    isThreeLine: true,
                    trailing: StatusChip.req(a.status),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class AdvanceFormScreen extends StatefulWidget {
  final AppUser me;
  const AdvanceFormScreen({super.key, required this.me});

  @override
  State<AdvanceFormScreen> createState() => _AdvanceFormScreenState();
}

class _AdvanceFormScreenState extends State<AdvanceFormScreen> {
  final _amount = TextEditingController();
  final _reason = TextEditingController();
  bool _busy = false;
  String? _err;

  Future<void> _submit() async {
    final amt = parseAmount(_amount.text);
    if (amt == null || amt <= 0) {
      setState(() => _err = 'Enter the amount.');
      return;
    }
    if (_reason.text.trim().isEmpty) {
      setState(() => _err = 'Enter a reason.');
      return;
    }
    setState(() => _busy = true);
    try {
      await FinanceService.requestAdvance(
          widget.me.phone, widget.me.name, amt, _reason.text.trim());
      if (mounted) {
        toast(context, 'Advance request sent');
        Navigator.pop(context);
      }
    } catch (_) {
      setState(() {
        _busy = false;
        _err = 'Could not submit. Check internet and retry.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Salary advance')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        TextField(
          controller: _amount,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(labelText: 'Amount (₹)'),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _reason,
          maxLines: 3,
          decoration: const InputDecoration(labelText: 'Reason'),
        ),
        const SizedBox(height: 8),
        const Text(
            'Approved within 24–48 hours. Deducted from your next salary unless a carry forward is approved.',
            style: TextStyle(color: Colors.black54)),
        if (_err != null) ...[
          const SizedBox(height: 8),
          Text(_err!, style: const TextStyle(color: kRed)),
        ],
        const SizedBox(height: 20),
        FilledButton(
          onPressed: _busy ? null : _submit,
          child: Text(_busy ? 'Sending…' : 'Submit request'),
        ),
      ]),
    );
  }
}

// ---------------- Expense ----------------

class _ExpenseTab extends StatelessWidget {
  final AppUser me;
  const _ExpenseTab({required this.me});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'exp',
        onPressed: () => Navigator.push(context,
            MaterialPageRoute(builder: (_) => ExpenseFormScreen(me: me))),
        icon: const Icon(Icons.add),
        label: const Text('Claim expense'),
      ),
      body: StreamBuilder<List<Expense>>(
        stream: FinanceService.myExpenses(me.phone),
        builder: (context, snap) {
          final items = snap.data ?? [];
          if (items.isEmpty) {
            return const EmptyState(
                'No expense claims.\nClaim site spends (material, travel, food) with the bill photo.');
          }
          return ListView(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 88),
            children: [
              for (final e in items)
                Card(
                  child: ListTile(
                    title: Text('${money(e.amount)} · ${e.category}'),
                    subtitle: Text([
                      if (e.siteName.isNotEmpty) e.siteName,
                      e.details,
                      if (e.note?.isNotEmpty == true) 'Note: ${e.note}',
                    ].join('\n')),
                    isThreeLine: true,
                    trailing: StatusChip.req(e.status),
                    onTap: e.billUrl == null ? null : () => openUrl(e.billUrl!),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class ExpenseFormScreen extends StatefulWidget {
  final AppUser me;
  const ExpenseFormScreen({super.key, required this.me});

  @override
  State<ExpenseFormScreen> createState() => _ExpenseFormScreenState();
}

class _ExpenseFormScreenState extends State<ExpenseFormScreen> {
  final _amount = TextEditingController();
  final _details = TextEditingController();
  String _category = expenseCategories.first;
  String _site = '';
  File? _bill;
  bool _busy = false;
  String? _err;

  Future<void> _submit() async {
    final amt = parseAmount(_amount.text);
    if (amt == null || amt <= 0) {
      setState(() => _err = 'Enter the amount.');
      return;
    }
    if (_details.text.trim().isEmpty) {
      setState(() => _err = 'Describe what was bought or paid for.');
      return;
    }
    setState(() => _busy = true);
    try {
      await FinanceService.requestExpense(
        phone: widget.me.phone,
        name: widget.me.name,
        amount: amt,
        category: _category,
        siteName: _site,
        details: _details.text.trim(),
        bill: _bill,
      );
      if (mounted) {
        toast(context, 'Expense claim sent');
        Navigator.pop(context);
      }
    } catch (_) {
      setState(() {
        _busy = false;
        _err = 'Could not submit. Check internet and retry.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Claim expense')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        TextField(
          controller: _amount,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(labelText: 'Amount (₹)'),
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          value: _category,
          decoration: const InputDecoration(labelText: 'Category'),
          items: [
            for (final c in expenseCategories)
              DropdownMenuItem(value: c, child: Text(c)),
          ],
          onChanged: (v) => setState(() => _category = v ?? _category),
        ),
        const SizedBox(height: 12),
        StreamBuilder<List<Site>>(
          stream: SiteService.watchAll(),
          builder: (context, snap) {
            final sites = snap.data ?? [];
            return DropdownButtonFormField<String>(
              value: _site,
              decoration: const InputDecoration(labelText: 'Site'),
              items: [
                const DropdownMenuItem(value: '', child: Text('—')),
                for (final s in sites)
                  DropdownMenuItem(value: s.name, child: Text(s.name)),
              ],
              onChanged: (v) => setState(() => _site = v ?? ''),
            );
          },
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _details,
          maxLines: 3,
          decoration: const InputDecoration(labelText: 'Details'),
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          icon: Icon(_bill == null ? Icons.receipt_long : Icons.check),
          label: Text(_bill == null ? 'Photo of bill' : 'Bill photo attached'),
          onPressed: () async {
            final f = await takePhoto();
            if (f != null) setState(() => _bill = f);
          },
        ),
        if (_err != null) ...[
          const SizedBox(height: 8),
          Text(_err!, style: const TextStyle(color: kRed)),
        ],
        const SizedBox(height: 20),
        FilledButton(
          onPressed: _busy ? null : _submit,
          child: Text(_busy ? 'Sending…' : 'Submit claim'),
        ),
      ]),
    );
  }
}
