import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/auth_provider.dart';
import '../theme.dart';
import '../utils/logout_confirm.dart';
import '../widgets/hub_menu_tile.dart';
import '../widgets/kaata_logo.dart';
import 'employee_management_screen.dart';
import 'restaurant_manage_list_screen.dart';

/// Home screen for the 'super_admin' role — not scoped to any single
/// restaurant. Two jobs: manage employees across every resto (the app
/// previously had no UI for this at all), and manage restos (including
/// creating new ones — that's the "+ Resto Baru" FAB inside List Resto,
/// not a separate menu entry here).
class SuperAdminHomeScreen extends StatelessWidget {
  const SuperAdminHomeScreen({super.key});

  Future<void> _logout(BuildContext context) async {
    if (!await confirmLogout(context)) return;
    if (!context.mounted) return;
    await context.read<AuthProvider>().signOut();
    if (!context.mounted) return;
    Navigator.of(context).popUntil((r) => r.isFirst);
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final name = auth.employeeName?.isNotEmpty == true ? auth.employeeName! : 'Super Admin';
    final email = auth.user?.email;

    return Scaffold(
      backgroundColor: KaataTheme.backgroundTint,
      // Fixed header + scrolling menu, rather than a SliverAppBar: with
      // enough entries to scroll, a collapsing app bar took the logo,
      // name and email away with it. Only the menu should move.
      body: Column(
        children: [
          HubHeader(
            logo: const KaataLogo(size: 64),
            title: name,
            subtitle: email == null ? 'Super Admin' : 'Super Admin • $email',
            colorA: KaataTheme.brand,
            colorB: KaataTheme.brandDark,
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                const Text('Menu',
                    style:
                        TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Colors.grey)),
                const SizedBox(height: 10),
                HubMenuTile(
                  icon: Icons.badge_outlined,
                  title: 'Kelola Karyawan',
                  subtitle: 'Tambah/edit/hapus akun Admin, Kasir, Chef, Finance — semua resto',
                  color: const Color(0xFF6366F1),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const EmployeeManagementScreen()),
                  ),
                ),
                const SizedBox(height: 12),
                HubMenuTile(
                  icon: Icons.storefront_outlined,
                  title: 'List Resto',
                  subtitle: 'Lihat & edit semua resto terdaftar di KaataGo',
                  color: const Color(0xFF0EA5E9),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const RestaurantManageListScreen()),
                  ),
                ),
                const SizedBox(height: 12),
                HubMenuTile(
                  icon: Icons.logout,
                  title: 'Keluar',
                  subtitle: 'Logout dari akun ini',
                  color: const Color(0xFFEF4444),
                  onTap: () => _logout(context),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
