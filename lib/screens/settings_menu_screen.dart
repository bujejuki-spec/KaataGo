import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/auth_provider.dart';
import 'restaurant_info_screen.dart';
import 'settings_screen.dart';
import 'table_qr_generator_screen.dart';

/// Admin's settings hub — groups the less-frequently-used screens
/// (restaurant info, table QR codes, payment settings) plus logout,
/// instead of cluttering the main app bar with a separate icon for each
/// one. Kasir doesn't use this screen — their Logout is a direct app bar
/// icon instead, since this menu would otherwise be empty for them.
class SettingsMenuScreen extends StatelessWidget {
  const SettingsMenuScreen({super.key});

  Future<void> _logout(BuildContext context) async {
    await context.read<AuthProvider>().signOut();
    if (!context.mounted) return;
    // This screen was pushed on top of the role's home screen — pop all
    // the way back to the root route so RootScreen's now-logged-out
    // rebuild (→ RoleChoiceScreen) is actually visible instead of
    // staying hidden behind this still-open route.
    Navigator.of(context).popUntil((r) => r.isFirst);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Pengaturan')),
      body: ListView(
        children: [
          ListTile(
            leading: const Icon(Icons.storefront),
            title: const Text('Info Resto'),
            subtitle: const Text('Nama & alamat yang dilihat customer'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const RestaurantInfoScreen()),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.qr_code_2_outlined),
            title: const Text('QR Meja'),
            subtitle: const Text('Buat & lihat QR code tiap meja'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const TableQrGeneratorScreen()),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.payments_outlined),
            title: const Text('Pengaturan Pembayaran'),
            subtitle: const Text('QRIS & rekening bank'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const SettingsScreen()),
            ),
          ),
          const Divider(height: 24),
          ListTile(
            leading: const Icon(Icons.logout, color: Colors.red),
            title: const Text('Keluar', style: TextStyle(color: Colors.red)),
            onTap: () => _logout(context),
          ),
        ],
      ),
    );
  }
}
