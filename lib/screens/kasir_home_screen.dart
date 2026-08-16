import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../db/cash_deposit_repository.dart';
import '../db/order_repository.dart';
import '../db/petty_cash_repository.dart';
import '../providers/auth_provider.dart';
import '../theme.dart';
import '../utils/logout_confirm.dart';
import '../widgets/badged_hub_tile.dart';
import '../widgets/hub_menu_tile.dart';
import '../widgets/inbox_tile.dart';
import '../widgets/responsive.dart';
import '../widgets/kaata_logo.dart';
import 'cash_deposit_screen.dart';
import 'finance_balance_screen.dart';
import 'pending_payment_screen.dart';
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
    final restoId = auth.restoId;

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
            child: HubMenuLayout(
              header: const [
                Text('Menu',
                    style:
                        TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Colors.grey)),
                SizedBox(height: 10),
              ],
              tiles: [
                HubMenuTile(
                  icon: Icons.point_of_sale_outlined,
                  title: 'Kasir / Input Pesanan',
                  subtitle: 'Pilih produk, checkout, terima pembayaran',
                  color: const Color(0xFF10B981),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const PosHomeScreen()),
                  ),
                ),
                BadgedHubTile(
                  icon: Icons.pending_actions_outlined,
                  title: 'Pending Payment',
                  subtitle: 'Pesanan dari HP customer yang bayar tunai di kasir',
                  color: const Color(0xFFF59E0B),
                  loadCount: () => restoId == null
                      ? Future.value(0)
                      : OrderRepository().pendingCashPaymentCount(restoId),
                  destination: () => const PendingPaymentScreen(),
                ),
                HubMenuTile(
                  icon: Icons.receipt_long_outlined,
                  title: 'Riwayat Kasir',
                  subtitle: 'Transaksi yang diinput kasir — rekap per hari',
                  color: const Color(0xFF0EA5E9),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const TransactionHistoryScreen()),
                  ),
                ),
                BadgedHubTile(
                  icon: Icons.account_balance_wallet_outlined,
                  title: 'Saldo & Pengeluaran',
                  subtitle: 'Lihat saldo, catat pengeluaran dari Petty Cash',
                  color: const Color(0xFF6366F1),
                  loadCount: () => restoId == null
                      ? Future.value(0)
                      : PettyCashRepository().pendingCount(restoId),
                  destination: () => const FinanceBalanceScreen(),
                ),
                BadgedHubTile(
                  icon: Icons.account_balance_outlined,
                  title: 'Setor Saldo Cash',
                  subtitle: 'Setor tunai di laci ke rekening resto',
                  color: const Color(0xFF0EA5E9),
                  loadCount: () => restoId == null
                      ? Future.value(0)
                      : CashDepositRepository().pendingCount(restoId),
                  destination: () => const CashDepositScreen(),
                ),
                const InboxTile(),
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
