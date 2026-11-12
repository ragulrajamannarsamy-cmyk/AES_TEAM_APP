import 'package:flutter/material.dart';

import '../../models/app_user.dart';
import 'approvals_screen.dart';
import 'billing_screen.dart';
import 'jobs_admin.dart';
import 'payroll_screen.dart';
import 'reports_screen.dart';
import 'sites_screen.dart';
import 'staff_screen.dart';
import 'today_board.dart';

class AdminHome extends StatelessWidget {
  final AppUser me;
  const AdminHome({super.key, required this.me});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 8,
      child: Column(
        children: [
          const TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            tabs: [
              Tab(text: 'Today'),
              Tab(text: 'Approvals'),
              Tab(text: 'Payroll'),
              Tab(text: 'Jobs'),
              Tab(text: 'Billing'),
              Tab(text: 'Reports'),
              Tab(text: 'Sites'),
              Tab(text: 'Staff'),
            ],
          ),
          Expanded(
            child: TabBarView(
              children: [
                const TodayBoard(),
                ApprovalsScreen(me: me),
                PayrollScreen(me: me),
                JobsAdmin(me: me),
                const BillingScreen(),
                const ReportsScreen(),
                const SitesScreen(),
                StaffScreen(me: me),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
