import 'package:flutter/material.dart';

import '../../models/app_user.dart';
import '../../services/user_service.dart';

/// Add staff by mobile number. Only numbers added here can log in.
class StaffScreen extends StatelessWidget {
  final AppUser me;
  const StaffScreen({super.key, required this.me});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'staff',
        onPressed: () => _edit(context, null),
        icon: const Icon(Icons.person_add),
        label: const Text('Add staff'),
      ),
      body: StreamBuilder<List<AppUser>>(
        stream: UserService.watchAll(),
        builder: (context, snap) {
          final users = snap.data ?? [];
          return ListView(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 88),
            children: [
              Text('${users.where((u) => u.active).length} active staff',
                  style: Theme.of(context).textTheme.titleSmall),
              for (final u in users)
                Card(
                  child: ListTile(
                    title: Text(u.name +
                        (u.active ? '' : ' (inactive)')),
                    subtitle: Text(
                        '${u.phone} · ${u.role.name} · ₹${u.perDayRate.round()}/day · PF+ESI ₹${u.pfEsi.round()}'),
                    // Only the owner can edit owner/manager accounts.
                    onTap: u.isAdmin && me.role != Role.owner
                        ? null
                        : () => _edit(context, u),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _edit(BuildContext context, AppUser? u) =>
      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        builder: (_) => _StaffForm(user: u, canSetAdmin: me.role == Role.owner),
      );
}

class _StaffForm extends StatefulWidget {
  final AppUser? user;
  final bool canSetAdmin;
  const _StaffForm({this.user, required this.canSetAdmin});

  @override
  State<_StaffForm> createState() => _StaffFormState();
}

class _StaffFormState extends State<_StaffForm> {
  late final _phone = TextEditingController(
      text: widget.user?.phone.replaceFirst('+91', '') ?? '');
  late final _name = TextEditingController(text: widget.user?.name ?? '');
  late final _rate = TextEditingController(
      text: widget.user?.perDayRate.round().toString() ?? '');
  late final _pf = TextEditingController(
      text: (widget.user?.pfEsi ?? 2100).round().toString());
  late Role _role = widget.user?.role ?? Role.worker;
  late bool _active = widget.user?.active ?? true;
  String? _err;

  Future<void> _save() async {
    final phone = normalizePhone(_phone.text);
    final rate = double.tryParse(_rate.text);
    final pf = double.tryParse(_pf.text);
    if (phone.length != 13 ||
        _name.text.trim().isEmpty ||
        rate == null ||
        pf == null) {
      setState(() => _err = 'Fill mobile number, name, per-day rate and PF+ESI.');
      return;
    }
    await UserService.save(AppUser(
      phone: phone,
      name: _name.text.trim(),
      role: _role,
      perDayRate: rate,
      pfEsi: pf,
      active: _active,
    ));
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final roles = widget.canSetAdmin
        ? Role.values
        : [Role.worker, Role.driver];
    return Padding(
      padding: EdgeInsets.fromLTRB(
          16, 16, 16, MediaQuery.of(context).viewInsets.bottom + 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _phone,
            enabled: widget.user == null,
            keyboardType: TextInputType.phone,
            decoration: const InputDecoration(
                labelText: 'Mobile number', prefixText: '+91 '),
          ),
          const SizedBox(height: 12),
          TextField(
              controller: _name,
              decoration: const InputDecoration(labelText: 'Full name')),
          const SizedBox(height: 12),
          DropdownButtonFormField<Role>(
            value: roles.contains(_role) ? _role : Role.worker,
            decoration: const InputDecoration(labelText: 'Role'),
            items: [
              for (final r in roles)
                DropdownMenuItem(value: r, child: Text(r.name)),
            ],
            onChanged: (r) => setState(() => _role = r ?? Role.worker),
          ),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(
                child: TextField(
                    controller: _rate,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                        labelText: 'Per-day rate (₹)'))),
            const SizedBox(width: 8),
            Expanded(
                child: TextField(
                    controller: _pf,
                    keyboardType: TextInputType.number,
                    decoration:
                        const InputDecoration(labelText: 'PF + ESI (₹/month)'))),
          ]),
          SwitchListTile(
            title: const Text('Active (can log in)'),
            value: _active,
            onChanged: (v) => setState(() => _active = v),
          ),
          if (_err != null) Text(_err!, style: const TextStyle(color: Colors.red)),
          const SizedBox(height: 8),
          FilledButton(onPressed: _save, child: const Text('Save')),
        ],
      ),
    );
  }
}
