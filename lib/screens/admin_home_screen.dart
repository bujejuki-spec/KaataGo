import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/auth_provider.dart';
import '../theme.dart';
import '../utils/logout_confirm.dart';
import '../widgets/hub_menu_tile.dart';
import '../widgets/kaata_logo.dart';
import 'employee_orders_screen.dart';
import 'pos_home_screen.dart';
import 'product_list_screen.dart';
import 'settings_menu_screen.dart';
import 'transaction_history_screen.dart';

/// Home screen for the 'admin' role — styled the same as Finance/Super
/// Admin's hub (gradient header + colorful menu cards) instead of
/// stacking every action as an app bar icon on the ordering screen.
/// "Kasir / Input Pesanan" is itself just a menu tile here — that's
/// where the product grid + checkout flow ([PosHomeScreen]) lives now.
class AdminHomeScreen extends StatelessWidget {
  const AdminHomeScreen({super.key});

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
    final name = auth.employeeName?.isNotEmpty == true ? auth.employeeName! : 'Admin';
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
            subtitle: email == null ? 'Admin' : 'Admin • $email',
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
                  icon: Icons.point_of_sale_outlined,
                  title: 'Kasir / Input Pesanan',
                  subtitle: 'Pilih produk, checkout, terima pembayaran',
                  color: const Color(0xFF10B981),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const PosHomeScreen()),
                  ),
                ),
                const SizedBox(height: 12),
                HubMenuTile(
                  icon: Icons.inventory_2_outlined,
                  title: 'Kelola Produk',
                  subtitle: 'Tambah/edit produk, kategori, level/varian',
                  color: const Color(0xFF6366F1),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const ProductListScreen()),
                  ),
                ),
                const SizedBox(height: 12),
                HubMenuTile(
                  icon: Icons.list_alt_outlined,
                  title: 'Pesanan Masuk',
                  subtitle: 'Pantau pesanan kasir & customer, status dapur',
                  color: const Color(0xFFF59E0B),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const EmployeeOrdersScreen()),
                  ),
                ),
                const SizedBox(height: 12),
                HubMenuTile(
                  icon: Icons.receipt_long_outlined,
                  title: 'Riwayat Transaksi',
                  subtitle: 'Rekap penjualan per hari, breakdown pembayaran',
                  color: const Color(0xFF0EA5E9),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const TransactionHistoryScreen()),
                  ),
                ),
                const SizedBox(height: 12),
                HubMenuTile(
                  icon: Icons.settings_outlined,
                  title: 'Pengaturan',
                  subtitle: 'Info resto, QR meja, pengaturan pembayaran',
                  color: const Color(0xFFEC4899),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const SettingsMenuScreen()),
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
