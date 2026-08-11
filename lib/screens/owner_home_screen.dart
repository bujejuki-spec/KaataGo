import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/auth_provider.dart';
import '../theme.dart';
import '../utils/logout_confirm.dart';
import '../widgets/hub_menu_tile.dart';
import '../widgets/kaata_logo.dart';
import '../widgets/resto_switcher.dart';
import 'cash_deposit_screen.dart';
import 'chef_home_screen.dart';
import 'employee_orders_screen.dart';
import 'finance_balance_screen.dart';
import 'finance_gl_mapping_screen.dart';
import 'finance_income_screen.dart';
import 'finance_journal_screen.dart';
import 'finance_report_screen.dart';
import 'pos_home_screen.dart';
import 'product_list_screen.dart';
import 'settings_menu_screen.dart';
import 'transaction_history_screen.dart';

/// Layar utama peran Owner: seluruh menu Kasir, Admin, Chef, dan Finance
/// dalam satu tempat.
///
/// Menunya dikelompokkan per bidang alih-alih ditumpuk jadi satu daftar
/// panjang. Dengan tiga belas entri, daftar rata tanpa pengelompokan
/// memaksa orang membaca semuanya untuk menemukan satu — sementara
/// pemilik biasanya sudah tahu dia sedang mengurus penjualan, dapur, atau
/// keuangan.
class OwnerHomeScreen extends StatelessWidget {
  const OwnerHomeScreen({super.key});

  Future<void> _logout(BuildContext context) async {
    if (!await confirmLogout(context)) return;
    if (!context.mounted) return;
    await context.read<AuthProvider>().signOut();
    if (!context.mounted) return;
    Navigator.of(context).popUntil((r) => r.isFirst);
  }

  void _open(BuildContext context, Widget screen) {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final name = auth.employeeName?.isNotEmpty == true ? auth.employeeName! : 'Owner';
    final email = auth.user?.email;

    return Scaffold(
      backgroundColor: KaataTheme.backgroundTint,
      body: Column(
        children: [
          HubHeader(
            logo: const KaataLogo(size: 64),
            title: name,
            subtitle: email == null ? 'Owner' : 'Owner • $email',
            colorA: KaataTheme.brand,
            colorB: KaataTheme.brandDark,
            trailing: const RestoSwitcher(),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                const _SectionLabel('Penjualan'),
                HubMenuTile(
                  icon: Icons.point_of_sale,
                  title: 'Kasir / Input Pesanan',
                  subtitle: 'Pilih produk, checkout, terima pembayaran',
                  color: const Color(0xFF10B981),
                  onTap: () => _open(context, const PosHomeScreen()),
                ),
                const SizedBox(height: 12),
                HubMenuTile(
                  icon: Icons.receipt_long_outlined,
                  title: 'Pesanan Masuk',
                  subtitle: 'Pantau pesanan kasir & customer, status dapur',
                  color: const Color(0xFFF59E0B),
                  onTap: () => _open(context, const EmployeeOrdersScreen()),
                ),
                const SizedBox(height: 12),
                HubMenuTile(
                  icon: Icons.soup_kitchen_outlined,
                  title: 'Layar Dapur',
                  subtitle: 'Antrean masak, cek menu sebelum selesai',
                  color: const Color(0xFFEF4444),
                  onTap: () => _open(context, const ChefHomeScreen()),
                ),
                const SizedBox(height: 12),
                HubMenuTile(
                  icon: Icons.history,
                  title: 'Riwayat Transaksi',
                  subtitle: 'Rekap penjualan per hari, breakdown pembayaran',
                  color: const Color(0xFF6366F1),
                  onTap: () => _open(context, const TransactionHistoryScreen()),
                ),

                const _SectionLabel('Keuangan'),
                HubMenuTile(
                  icon: Icons.trending_up,
                  title: 'Pemasukan',
                  subtitle: 'Rekap harian, breakdown Tunai/QRIS/Transfer',
                  color: const Color(0xFF10B981),
                  onTap: () => _open(context, const FinanceIncomeScreen()),
                ),
                const SizedBox(height: 12),
                HubMenuTile(
                  icon: Icons.account_balance_wallet_outlined,
                  title: 'Saldo & Pengeluaran',
                  subtitle: 'Lihat saldo total, catat pengeluaran',
                  color: const Color(0xFF6366F1),
                  onTap: () => _open(context, const FinanceBalanceScreen()),
                ),
                const SizedBox(height: 12),
                HubMenuTile(
                  icon: Icons.account_balance_outlined,
                  title: 'Setor Saldo Cash',
                  subtitle: 'Setor tunai di laci ke rekening resto',
                  color: const Color(0xFF0EA5E9),
                  onTap: () => _open(context, const CashDepositScreen()),
                ),
                const SizedBox(height: 12),
                HubMenuTile(
                  icon: Icons.numbers,
                  title: 'Mapping GL Account',
                  subtitle: 'Nomor akun untuk pemasukan & pengeluaran',
                  color: const Color(0xFF8B5CF6),
                  onTap: () => _open(context, const FinanceGlMappingScreen()),
                ),
                const SizedBox(height: 12),
                HubMenuTile(
                  icon: Icons.menu_book_outlined,
                  title: 'Jurnal GL',
                  subtitle: 'Audit trail semua pergerakan uang per GL account',
                  color: const Color(0xFF14B8A6),
                  onTap: () => _open(context, const FinanceJournalScreen()),
                ),
                const SizedBox(height: 12),
                HubMenuTile(
                  icon: Icons.description_outlined,
                  title: 'Laporan Transaksi',
                  subtitle: 'Export/cetak laporan seperti rekening koran',
                  color: const Color(0xFF0EA5E9),
                  onTap: () => _open(context, const FinanceReportScreen()),
                ),

                const _SectionLabel('Pengelolaan'),
                HubMenuTile(
                  icon: Icons.inventory_2_outlined,
                  title: 'Kelola Produk',
                  subtitle: 'Tambah/edit produk, kategori, level/varian',
                  color: const Color(0xFF8B5CF6),
                  onTap: () => _open(context, const ProductListScreen()),
                ),
                const SizedBox(height: 12),
                HubMenuTile(
                  icon: Icons.settings_outlined,
                  title: 'Pengaturan',
                  subtitle: 'Info resto, karyawan, QR meja, pembayaran',
                  color: const Color(0xFF64748B),
                  onTap: () => _open(context, const SettingsMenuScreen()),
                ),
                const SizedBox(height: 12),
                HubMenuTile(
                  icon: Icons.logout,
                  title: 'Keluar',
                  subtitle: 'Logout dari akun ini',
                  color: const Color(0xFFEF4444),
                  onTap: () => _logout(context),
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String text;

  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 18, bottom: 10),
      child: Text(
        text.toUpperCase(),
        style: TextStyle(
          fontWeight: FontWeight.bold,
          fontSize: 12,
          letterSpacing: 0.8,
          color: Colors.grey.shade500,
        ),
      ),
    );
  }
}
