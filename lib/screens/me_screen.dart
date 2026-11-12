import 'dart:io';

import 'package:flutter/material.dart';

import '../models/app_user.dart';
import '../models/bank.dart';
import '../models/requests.dart';
import '../services/bank_service.dart';
import '../theme.dart';
import '../util.dart';
import '../widgets/common.dart';

/// Worker profile + bank details for salary credit.
class MeScreen extends StatelessWidget {
  final AppUser me;
  const MeScreen({super.key, required this.me});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(children: [
              KV('Name', me.name, strong: true),
              KV('Mobile', me.phone),
              KV('Role', roleLabels[me.role]!),
              if (!me.isAdmin) KV('Per-day rate', money(me.perDayRate)),
              if (!me.isAdmin) KV('PF + ESI / month', money(me.pfEsi)),
              if (me.isDriver && me.perKmRate > 0)
                KV('Vehicle rent / km', money(me.perKmRate)),
            ]),
          ),
        ),
        StreamBuilder<BankDetails?>(
          stream: BankService.watchMine(me.phone),
          builder: (context, snap) {
            final b = snap.data;
            return Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(children: [
                      Text('Bank details',
                          style: Theme.of(context).textTheme.titleMedium),
                      const Spacer(),
                      if (b != null) const StatusChip('VERIFIED', kGreen),
                    ]),
                    const SizedBox(height: 8),
                    if (b == null)
                      const Text(
                          'Add your bank account so salary can be credited.')
                    else ...[
                      KV('Account holder', b.holderName),
                      KV('Account', b.masked),
                      KV('IFSC', b.ifsc),
                      KV('Bank', '${b.bankName}, ${b.branch}'),
                    ],
                    const SizedBox(height: 12),
                    OutlinedButton(
                      onPressed: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) => BankFormScreen(me: me))),
                      child: Text(
                          b == null ? 'Add bank details' : 'Request a change'),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                        'Only the owner and managers can see these details. Changes need manager approval.',
                        style: TextStyle(color: Colors.black54, fontSize: 12)),
                  ],
                ),
              ),
            );
          },
        ),
        StreamBuilder<List<BankRequest>>(
          stream: BankService.myRequests(me.phone),
          builder: (context, snap) {
            final r = (snap.data ?? []).take(3).toList();
            if (r.isEmpty) return const SizedBox.shrink();
            return Card(
              child: Column(children: [
                for (final x in r)
                  ListTile(
                    dense: true,
                    title: Text('Bank update · ${x.details.masked}'),
                    subtitle: Text([
                      ageLabel(x.createdAt),
                      if (x.note?.isNotEmpty == true) 'Note: ${x.note}',
                    ].join(' · ')),
                    trailing: StatusChip.req(x.status),
                  ),
              ]),
            );
          },
        ),
      ],
    );
  }
}

class BankFormScreen extends StatefulWidget {
  final AppUser me;
  const BankFormScreen({super.key, required this.me});

  @override
  State<BankFormScreen> createState() => _BankFormScreenState();
}

class _BankFormScreenState extends State<BankFormScreen> {
  late final _holder = TextEditingController(text: widget.me.name);
  final _acc = TextEditingController();
  final _acc2 = TextEditingController();
  final _ifsc = TextEditingController();
  final _bank = TextEditingController();
  final _branch = TextEditingController();
  File? _proof;
  bool _busy = false;
  String? _err;

  Future<void> _lookup() async {
    final code = _ifsc.text.trim();
    if (!ifscPattern.hasMatch(code)) return;
    final r = await BankService.lookupIfsc(code);
    if (r != null && mounted) {
      setState(() {
        _bank.text = r.bank;
        _branch.text = r.branch;
      });
    }
  }

  Future<void> _submit() async {
    final acc = _acc.text.replaceAll(' ', '');
    String? err;
    if (_holder.text.trim().isEmpty) err = 'Enter account holder name.';
    if (!RegExp(r'^\d{9,18}$').hasMatch(acc)) {
      err = 'Account number must be 9–18 digits.';
    } else if (acc != _acc2.text.replaceAll(' ', '')) {
      err = 'Account numbers do not match.';
    } else if (!ifscPattern.hasMatch(_ifsc.text.trim())) {
      err = 'IFSC must be 11 characters, e.g. SBIN0001234.';
    } else if (_bank.text.trim().isEmpty) {
      err = 'Enter bank name.';
    } else if (_proof == null) {
      err = 'Add a photo of cancelled cheque or passbook first page.';
    }
    if (err != null) {
      setState(() => _err = err);
      return;
    }
    setState(() {
      _busy = true;
      _err = null;
    });
    try {
      await BankService.submit(
        phone: widget.me.phone,
        name: widget.me.name,
        holderName: _holder.text.trim(),
        accountNumber: acc,
        ifsc: _ifsc.text.trim(),
        bankName: _bank.text.trim(),
        branch: _branch.text.trim(),
        proof: _proof!,
      );
      if (mounted) {
        toast(context, 'Sent for verification');
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
      appBar: AppBar(title: const Text('Bank details')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        TextField(
            controller: _holder,
            decoration:
                const InputDecoration(labelText: 'Account holder name')),
        const SizedBox(height: 12),
        TextField(
            controller: _acc,
            keyboardType: TextInputType.number,
            obscureText: true,
            decoration: const InputDecoration(labelText: 'Account number')),
        const SizedBox(height: 12),
        TextField(
            controller: _acc2,
            keyboardType: TextInputType.number,
            decoration:
                const InputDecoration(labelText: 'Re-enter account number')),
        const SizedBox(height: 12),
        TextField(
          controller: _ifsc,
          textCapitalization: TextCapitalization.characters,
          maxLength: 11,
          decoration: const InputDecoration(labelText: 'IFSC code'),
          onChanged: (v) {
            if (v.trim().length == 11) _lookup();
          },
        ),
        TextField(
            controller: _bank,
            decoration: const InputDecoration(labelText: 'Bank name')),
        const SizedBox(height: 12),
        TextField(
            controller: _branch,
            decoration: const InputDecoration(labelText: 'Branch')),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          icon: Icon(_proof == null ? Icons.photo_camera : Icons.check),
          label: Text(_proof == null
              ? 'Photo of cancelled cheque / passbook'
              : 'Proof photo attached'),
          onPressed: () async {
            final f = await takePhoto();
            if (f != null) setState(() => _proof = f);
          },
        ),
        if (_err != null) ...[
          const SizedBox(height: 8),
          Text(_err!, style: const TextStyle(color: kRed)),
        ],
        const SizedBox(height: 20),
        FilledButton(
          onPressed: _busy ? null : _submit,
          child: Text(_busy ? 'Sending…' : 'Submit for verification'),
        ),
      ]),
    );
  }
}
