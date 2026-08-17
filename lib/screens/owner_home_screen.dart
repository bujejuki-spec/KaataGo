import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../db/cash_deposit_repository.dart';
import '../db/order_repository.dart';
import '../db/petty_cash_repository.dart';
import '../providers/auth_provider.dart';
import '../theme.dart';
import '../utils/logout_confirm.dart';
import '../widgets/badged_hub_tile.dart';
import '../widgets/hub_group_tile.dart';
import '../widgets/hub_menu_tile.dart';
import 'billing_screen.dart';
import 'discount_screen.dart';
import '../widgets/inbox_tile.dart';
import '../widgets/responsive.dart';
import '../widgets/kaata_logo.dart';
import '../widgets/resto_switcher.dart';
import 'cash_deposit_screen.dart';
import 'chef_home_screen.dart';
import 'employee_orders_screen.dart';
import 'finance_balance_screen.dart';
import 'finance_gateway_settlement_screen.dart';
import 'finance_gl_mapping_screen.dart';
import 'finance_income_screen.dart';
import 'finance_journal_screen.dart';
import 'finance_report_screen.dart';
import 'pending_payment_screen.dart';
import 'pos_home_screen.dart';
import 'publish_announcement_screen.dart';
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
    final restoId = auth.restoId;

    return Scaffold(
      backgroundColor: KaataTheme.backgroundOf(context),
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
            child: ResponsiveCenter(
              maxWidth: 900,
              child: ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  HubGroupTile(
                    icon: Icons.point_of_sale_outlined,
                    title: 'Penjualan',
                    subtitle: 'Input pesanan, pesanan masuk, dapur, pending payment, riwayat',
                    color: const Color(0xFF10B981),
                    loadCount: () => restoId == null ? Future.value(0) : OrderRepository().pendingCashPaymentCount(restoId),
                    tiles: () => [
                      HubMenuTile(
                      icon: Icons.point_of_sale,
                      title: 'Kasir / Input Pesanan',
                      subtitle: 'Pilih produk, checkout, terima pembayaran',
                      color: const Color(0xFF10B981),
                      onTap: () => _open(context, const PosHomeScreen()),
                    ),
                      HubMenuTile(
                      icon: Icons.receipt_long_outlined,
                      title: 'Pesanan Masuk',
                      subtitle: 'Pantau pesanan kasir & customer, status dapur',
                      color: const Color(0xFFF59E0B),
                      onTap: () => _open(context, const EmployeeOrdersScreen()),
                    ),
                      HubMenuTile(
                      icon: Icons.soup_kitchen_outlined,
                      title: 'Layar Dapur',
                      subtitle: 'Antrean masak, cek menu sebelum selesai',
                      color: const Color(0xFFEF4444),
                      onTap: () => _open(context, const ChefHomeScreen()),
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
                      icon: Icons.history,
                      title: 'Riwayat Kasir',
                      subtitle: 'Transaksi yang diinput kasir — rekap per hari',
                      color: const Color(0xFF6366F1),
                      onTap: () => _open(context, const TransactionHistoryScreen()),
                    ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  HubGroupTile(
                    icon: Icons.account_balance_wallet_outlined,
                    title: 'Keuangan',
                    subtitle: 'Pemasukan, saldo, setoran, GL, jurnal, laporan',
                    color: const Color(0xFF6366F1),
                    loadCount: () => _penandaKeuangan(restoId),
                    tiles: () => [
                      HubMenuTile(
                      icon: Icons.trending_up,
                      title: 'Pemasukan',
                      subtitle: 'Rekap harian, breakdown Tunai/QRIS/Transfer',
                      color: const Color(0xFF10B981),
                      onTap: () => _open(context, const FinanceIncomeScreen()),
                    ),
                      BadgedHubTile(
                      icon: Icons.account_balance_wallet_outlined,
                      title: 'Saldo & Pengeluaran',
                      subtitle: 'Lihat saldo total, catat pengeluaran',
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
                      HubMenuTile(
                      icon: Icons.numbers,
                      title: 'Mapping GL Account',
                      subtitle: 'Nomor akun untuk pemasukan & pengeluaran',
                      color: const Color(0xFF8B5CF6),
                      onTap: () => _open(context, const FinanceGlMappingScreen()),
                    ),
                      HubMenuTile(
                      icon: Icons.credit_card_outlined,
                      title: 'Pencairan Gateway',
                      subtitle: 'Catat dana QRIS yang masuk rekening & potongannya',
                      color: const Color(0xFFEC4899),
                      onTap: () =>
                          _open(context, const FinanceGatewaySettlementScreen()),
                    ),
                      HubMenuTile(
                      icon: Icons.menu_book_outlined,
                      title: 'Jurnal GL',
                      subtitle: 'Audit trail semua pergerakan uang per GL account',
                      color: const Color(0xFF14B8A6),
                      onTap: () => _open(context, const FinanceJournalScreen()),
                    ),
                      HubMenuTile(
                      icon: Icons.description_outlined,
                      title: 'Laporan Transaksi',
                      subtitle: 'Export/cetak laporan seperti rekening koran',
                      color: const Color(0xFF0EA5E9),
                      onTap: () => _open(context, const FinanceReportScreen()),
                    ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  HubGroupTile(
                    icon: Icons.tune,
                    title: 'Pengelolaan',
                    subtitle: 'Produk, diskon, pengumuman, tagihan langganan',
                    color: const Color(0xFF8B5CF6),
                    tiles: () => [
                      HubMenuTile(
                      icon: Icons.inventory_2_outlined,
                      title: 'Kelola Produk',
                      subtitle: 'Tambah/edit produk, kategori, level/varian',
                      color: const Color(0xFF8B5CF6),
                      onTap: () => _open(context, const ProductListScreen()),
                    ),
                      HubMenuTile(
                      icon: Icons.local_offer_outlined,
                      title: 'Diskon',
                      subtitle: 'Promo per menu, bundling, atau minimum belanja',
                      color: const Color(0xFF10B981),
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => const DiscountScreen()),
                      ),
                    ),
                      HubMenuTile(
                      icon: Icons.campaign_outlined,
                      title: 'Kirim Pengumuman',
                      subtitle: 'Blast info & promo ke kotak masuk resto ini',
                      color: const Color(0xFF8B5CF6),
                      onTap: () => _open(context, const PublishAnnouncementScreen()),
                    ),
                      // Tagihan langganan KaataGo — bukan keuangan resto.
                    // Ditaruh di kelompok pengelolaan, bukan di KEUANGAN,
                    // supaya tidak tertukar dengan pembukuan restonya
                    // sendiri: yang satu uang yang masuk ke resto, yang
                    // satu uang yang keluar dari resto ke kami.
                    HubMenuTile(
                      icon: Icons.receipt_long_outlined,
                      title: 'Tagihan Langganan',
                      subtitle: 'Biaya bulanan KaataGo & bukti pembayaran',
                      color: const Color(0xFF6366F1),
                      onTap: () {
                        final restoId = context.read<AuthProvider>().restoId;
                        if (restoId == null) return;
                        Navigator.of(context).push(MaterialPageRoute(
                          builder: (_) => BillingScreen(restoId: restoId),
                        ));
                      },
                    ),
                    ],
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
                  const InboxTile(),
                  const SizedBox(height: 12),
                  HubMenuTile(
                    icon: Icons.logout,
                    title: 'Keluar',
                    subtitle: 'Logout dari akun ini',
                    color: const Color(0xFFEF4444),
                    onTap: () => _logout(context),
                  ),
                  const SizedBox(height: 12),
                  const SizedBox(height: 8),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Jumlah pengajuan yang menunggu keputusan di kelompok Keuangan.
///
/// Dijumlahkan supaya penandanya ikut naik ke halaman awal. Menyembunyikan
/// menu di balik pintu juga menyembunyikan titik merahnya — dan titik
/// merah itu satu-satunya cara orang tahu ada yang menunggu tanpa membuka
/// apa pun.
Future<int> _penandaKeuangan(String? restoId) async {
  if (restoId == null) return 0;
  final hasil = await Future.wait([
    PettyCashRepository().pendingCount(restoId),
    CashDepositRepository().pendingCount(restoId),
  ]);
  return hasil.fold<int>(0, (a, b) => a + b);
}
