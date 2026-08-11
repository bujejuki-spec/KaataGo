import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/auth_provider.dart';
import '../theme.dart';
import '../utils/logout_confirm.dart';
import '../widgets/hub_menu_tile.dart';
import '../widgets/kaata_logo.dart';
import 'finance_balance_screen.dart';
import 'finance_gl_mapping_screen.dart';
import 'finance_income_screen.dart';
import 'finance_journal_screen.dart';
import 'finance_report_screen.dart';
import 'settings_screen.dart';

/// Home screen for the 'finance' role: view resto-wide income (grouped
/// per day, broken down by payment method), view balance + record
/// expenses, and configure the GL account mapping used to book each
/// payment method's income.
class FinanceHomeScreen extends StatelessWidget {
  const FinanceHomeScreen({super.key});

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
    final name = auth.employeeName?.isNotEmpty == true ? auth.employeeName! : 'Finance';
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
            subtitle: email == null ? 'Finance' : 'Finance • $email',
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
                  icon: Icons.trending_up,
                  title: 'Pemasukan',
                  subtitle: 'Rekap harian, breakdown Tunai/QRIS/Transfer',
                  color: const Color(0xFF10B981),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const FinanceIncomeScreen()),
                  ),
                ),
                const SizedBox(height: 12),
                HubMenuTile(
                  icon: Icons.account_balance_wallet_outlined,
                  title: 'Saldo & Pengeluaran',
                  subtitle: 'Lihat saldo total, catat pengeluaran',
                  color: const Color(0xFF6366F1),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const FinanceBalanceScreen()),
                  ),
                ),
                const SizedBox(height: 12),
                HubMenuTile(
                  icon: Icons.numbers,
                  title: 'Mapping GL Account',
                  subtitle: 'Nomor akun untuk pemasukan & pengeluaran',
                  color: const Color(0xFFF59E0B),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const FinanceGlMappingScreen()),
                  ),
                ),
                const SizedBox(height: 12),
                HubMenuTile(
                  icon: Icons.menu_book_outlined,
                  title: 'Jurnal GL',
                  subtitle: 'Audit trail semua pergerakan uang per GL account',
                  color: const Color(0xFF14B8A6),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const FinanceJournalScreen()),
                  ),
                ),
                const SizedBox(height: 12),
                HubMenuTile(
                  icon: Icons.receipt_long_outlined,
                  title: 'Laporan Transaksi',
                  subtitle: 'Export/cetak laporan seperti rekening koran',
                  color: const Color(0xFF0EA5E9),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const FinanceReportScreen()),
                  ),
                ),
                const SizedBox(height: 12),
                HubMenuTile(
                  icon: Icons.payments_outlined,
                  title: 'Pengaturan Pembayaran',
                  subtitle: 'Atur QRIS & rekening bank resto',
                  color: const Color(0xFFEC4899),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const SettingsScreen()),
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
