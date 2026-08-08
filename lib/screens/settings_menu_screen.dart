import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/auth_provider.dart';
import '../theme.dart';
import '../widgets/hub_menu_tile.dart';
import '../widgets/kaata_logo.dart';
import 'restaurant_info_screen.dart';
import 'settings_screen.dart';
import 'table_qr_generator_screen.dart';

/// Admin's settings hub — groups the less-frequently-used screens
/// (restaurant info, table QR codes, payment settings) plus logout,
/// instead of cluttering the main app bar with a separate icon for each
/// one. Kasir doesn't use this screen — their Logout is a direct app bar
/// icon instead, since this menu would otherwise be empty for them.
///
/// Styled the same as the Super Admin/Finance hub screens (gradient hero
/// header + colorful icon-badge menu rows) for a consistent look across
/// every "menu" screen in the app.
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
    final email = context.watch<AuthProvider>().user?.email;

    return Scaffold(
      backgroundColor: KaataTheme.backgroundTint,
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            pinned: true,
            backgroundColor: KaataTheme.brandDark,
            expandedHeight: 200,
            flexibleSpace: FlexibleSpaceBar(
              background: HubHeader(
                logo: const KaataLogo(size: 64),
                roleLabel: 'Pengaturan',
                detail: email,
                colorA: KaataTheme.brand,
                colorB: KaataTheme.brandDark,
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.all(20),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                const Text('Menu',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Colors.grey)),
                const SizedBox(height: 10),
                HubMenuTile(
                  icon: Icons.storefront_outlined,
                  title: 'Info Resto',
                  subtitle: 'Nama & alamat yang dilihat customer',
                  color: const Color(0xFF6366F1),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const RestaurantInfoScreen()),
                  ),
                ),
                const SizedBox(height: 12),
                HubMenuTile(
                  icon: Icons.qr_code_2_outlined,
                  title: 'QR Meja',
                  subtitle: 'Buat & lihat QR code tiap meja',
                  color: const Color(0xFF0EA5E9),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const TableQrGeneratorScreen()),
                  ),
                ),
                const SizedBox(height: 12),
                HubMenuTile(
                  icon: Icons.payments_outlined,
                  title: 'Pengaturan Pembayaran',
                  subtitle: 'QRIS & rekening bank',
                  color: const Color(0xFFF59E0B),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const SettingsScreen()),
                  ),
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.red,
                      side: BorderSide(color: Colors.red.shade200),
                    ),
                    icon: const Icon(Icons.logout),
                    label: const Text('Keluar'),
                    onPressed: () => _logout(context),
                  ),
                ),
              ]),
            ),
          ),
        ],
      ),
    );
  }
}
