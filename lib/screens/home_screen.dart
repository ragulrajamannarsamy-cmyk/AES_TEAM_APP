import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../models/app_user.dart';
import 'admin/admin_home.dart';
import 'attendance_screen.dart';
import 'me_screen.dart';
import 'pay_screen.dart';
import 'requests_screen.dart';
import 'vehicle_screen.dart';

class _Tab {
  final String title;
  final IconData icon;
  final Widget page;
  const _Tab(this.title, this.icon, this.page);
}

class HomeScreen extends StatefulWidget {
  final AppUser me;
  const HomeScreen({super.key, required this.me});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    final me = widget.me;
    final tabs = <_Tab>[
      _Tab('Attendance', Icons.camera_front, AttendanceScreen(me: me)),
      _Tab('Requests', Icons.assignment, RequestsScreen(me: me)),
      _Tab('Pay', Icons.currency_rupee, PayScreen(me: me)),
      if (me.isDriver)
        _Tab('Vehicle', Icons.local_shipping, VehicleScreen(me: me)),
      _Tab('Me', Icons.person, MeScreen(me: me)),
      if (me.isAdmin)
        _Tab('Admin', Icons.admin_panel_settings, AdminHome(me: me)),
    ];
    final index = _tab.clamp(0, tabs.length - 1);

    return Scaffold(
      appBar: AppBar(
        title: Text(tabs[index].title),
        actions: [
          IconButton(
            tooltip: 'Log out',
            icon: const Icon(Icons.logout),
            onPressed: () => FirebaseAuth.instance.signOut(),
          ),
        ],
      ),
      body: IndexedStack(
        index: index,
        children: [for (final t in tabs) t.page],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: index,
        onDestinationSelected: (i) => setState(() => _tab = i),
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        destinations: [
          for (final t in tabs)
            NavigationDestination(icon: Icon(t.icon), label: t.title),
        ],
      ),
    );
  }
}
