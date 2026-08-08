import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/auth_provider.dart';
import '../widgets/kaata_logo.dart';
import 'employee_management_screen.dart';
import 'restaurant_create_screen.dart';

/// Home screen for the 'super_admin' role — not scoped to any single
/// restaurant. Two jobs: manage employees across every resto (the app
/// previously had no UI for this at all), and create brand-new restos
/// (new tenants) for KaataGo to onboard.
class SuperAdminHomeScreen extends StatelessWidget {
  const SuperAdminHomeScreen({super.key});

  Future<void> _logout(BuildContext context) async {
    await context.read<AuthProvider>().signOut();
    if (!context.mounted) return;
    Navigator.of(context).popUntil((r) => r.isFirst);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('KaataGo (Super Admin)'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Keluar',
            onPressed: () => _logout(context),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const Center(child: KaataLogo(size: 72)),
          const SizedBox(height: 24),
          Card(
            clipBehavior: Clip.antiAlias,
            child: ListTile(
              leading: const Icon(Icons.badge_outlined, size: 32),
              title: const Text('Kelola Karyawan'),
              subtitle: const Text('Tambah/edit/hapus akun Admin, Kasir, Chef — semua resto'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const EmployeeManagementScreen()),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            clipBehavior: Clip.antiAlias,
            child: ListTile(
              leading: const Icon(Icons.storefront_outlined, size: 32),
              title: const Text('Buat Resto Baru'),
              subtitle: const Text('Onboard tenant/resto baru ke KaataGo'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const RestaurantCreateScreen()),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
