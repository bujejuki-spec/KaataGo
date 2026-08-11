import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/auth_provider.dart';
import '../theme.dart';
import '../utils/logout_confirm.dart';
import '../widgets/hub_menu_tile.dart';
import '../widgets/kaata_logo.dart';
import 'finance_balance_screen.dart';
import 'pos_home_screen.dart';
import 'transaction_history_screen.dart';

/// Home screen for the 'kasir' role — styled the same as Admin/Finance/
/// Super Admin's hub (gradient header + colorful menu cards) instead of
/// putting Riwayat Transaksi/Logout as app-bar icons on the ordering
/// screen. "Kasir / Input Pesanan" is itself just a menu tile here —
/// that's where the product grid + checkout flow ([PosHomeScreen]) lives.
class KasirHomeScreen extends StatelessWidget {
  const KasirHomeScreen({super.key});

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
    final name = auth.employeeName?.isNotEmpty == true ? auth.employeeName! : 'Kasir';
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
            subtitle: email == null ? 'Kasir' : 'Kasir • $email',
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
                  icon: Icons.account_balance_wallet_outlined,
                  title: 'Saldo & Pengeluaran',
                  subtitle: 'Lihat saldo, catat pengeluaran dari Petty Cash',
                  color: const Color(0xFF6366F1),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const FinanceBalanceScreen()),
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
