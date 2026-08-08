import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/auth_provider.dart';
import '../providers/table_session_provider.dart';
import 'chef_home_screen.dart';
import 'customer_home_screen.dart';
import 'finance_home_screen.dart';
import 'pos_home_screen.dart';
import 'role_choice_screen.dart';
import 'super_admin_home_screen.dart';

/// Decides which experience to show:
/// - Admin/Kasir/Chef still signed in (Firebase Auth persists across app
///   restarts) → straight to their role's screen, bypassing the choice
///   screen entirely.
/// - Customer with a still-active table session on this device → straight
///   back into [CustomerHomeScreen] (no re-choosing needed).
/// - Otherwise (logged out employee, or an ended/no session) →
///   [RoleChoiceScreen] to pick Customer or Karyawan.
class RootScreen extends StatefulWidget {
  const RootScreen({super.key});

  @override
  State<RootScreen> createState() => _RootScreenState();
}

class _RootScreenState extends State<RootScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final session = context.read<TableSessionProvider>();
      if (!session.loaded) session.load();
    });
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    // Only gate on the one-time app-launch bootstrap check. Deliberately
    // NOT gating on auth.isCheckingRole here — that also flips true for
    // every later role re-check (e.g. a customer optionally logging in
    // from RoleChoiceScreen), and swapping this screen out mid-flow would
    // tear down whatever screen/dialog was mid-await, discarding it.
    // Screens that specifically want a spinner during a role check show
    // one themselves (see EmployeeLoginScreen).
    if (auth.isInitializing) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (auth.isSuperAdmin) return const SuperAdminHomeScreen();
    if (auth.isAdmin) return const PosHomeScreen(isAdmin: true);
    if (auth.isKasir) return const PosHomeScreen(isAdmin: false);
    if (auth.isChef) return const ChefHomeScreen();
    if (auth.isFinance) return const FinanceHomeScreen();

    final session = context.watch<TableSessionProvider>();
    if (!session.loaded) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (session.hasActiveResto) return const CustomerHomeScreen();
    return const RoleChoiceScreen();
  }
}
