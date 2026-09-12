import '../widgets/support_fab.dart';
import '../widgets/penilaian_tile.dart';
import 'customer_display_screen.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../db/cash_deposit_repository.dart';
import '../db/cashier_shift_repository.dart';
import '../db/order_repository.dart';
import '../db/petty_cash_repository.dart';
import '../providers/auth_provider.dart';
import '../theme.dart';
import '../utils/logout_confirm.dart';
import '../widgets/badged_hub_tile.dart';
import '../widgets/hub_group_tile.dart';
import '../widgets/hub_menu_tile.dart';
import 'discount_screen.dart';
import '../widgets/language_theme_toggle.dart';
import '../widgets/inbox_tile.dart';
import '../widgets/responsive.dart';
import '../widgets/kaata_logo.dart';
import 'cash_deposit_screen.dart';
import 'cashier_shift_screen.dart';
import 'finance_balance_screen.dart';
import 'pending_payment_screen.dart';
import 'pos_home_screen.dart';
import 'transaction_history_screen.dart';

/// Home screen for the 'kasir' role — styled the same as Admin/Finance/
/// Super Admin's hub (gradient header + colorful menu cards) instead of
/// putting Riwayat Transaksi/Logout as app-bar icons on the ordering
/// screen. "Kasir / Input Pesanan" is itself just a menu tile here —
/// that's where the product grid + checkout flow ([PosHomeScreen]) lives.
class KasirHomeScreen extends StatefulWidget {
  const KasirHomeScreen({super.key});

  @override
  State<KasirHomeScreen> createState() => _KasirHomeScreenState();
}

class _KasirHomeScreenState extends State<KasirHomeScreen> {
  /// Kasir ini sedang memegang shift atau belum.
  ///
  /// Selama belum, berandanya cuma menawarkan tiga hal: membuka shift,
  /// membaca kotak masuk, dan keluar. Sisanya menunggu.
  ///
  /// Bukan pengamanan — servernya sudah menolak hal-hal yang memang
  /// tidak boleh. Ini soal urutan kerja: mencatat penjualan sebelum
  /// laci punya titik awal berarti selisih tutup shift tidak bisa
  /// ditelusuri ke mana pun, dan kasir yang terlanjur melayani sepuluh
  /// pesanan tidak bisa mundur lagi.
  ///
  /// Null berarti belum diketahui. Selama itu yang ditampilkan tetap
  /// yang sempit: menu yang sempat muncul lalu hilang sendiri lebih
  /// membingungkan daripada menu yang datang belakangan.
  bool? _shiftSaya;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _periksaShift());
  }

  Future<void> _periksaShift() async {
    final restoId = context.read<AuthProvider>().restoId;
    if (restoId == null) {
      if (mounted) setState(() => _shiftSaya = false);
      return;
    }
    try {
      final ringkas = await CashierShiftRepository().ringkasTerbuka(restoId);
      if (mounted) setState(() => _shiftSaya = ringkas.milikSaya);
    } catch (_) {
      // Gagal bertanya bukan alasan mengunci: kasir yang jaringannya
      // sedang buruk tetap harus bisa bekerja.
      if (mounted) setState(() => _shiftSaya = true);
    }
  }

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
      backgroundColor: KaataTheme.backgroundOf(context),
      // Mengambang di beranda, bukan jadi satu tombol lagi di daftar.
      //
      // Yang mencarinya sedang kesulitan — dan orang yang sedang
      // kesulitan tidak menggulir daftar menu mencari jalan mengadu.
      floatingActionButton: const SupportFab(),
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
              tiles: [
                // Dibuka dua kali sehari pada dua saat tersibuk: awal shift
                // ketika antrean mulai, dan akhir shift ketika sudah ingin
                // pulang. Menu yang harus dicari di dalam grup pada dua saat
                // itu adalah menu yang dilewati — dan shift yang tidak pernah
                // ditutup membuat seluruh gunanya hilang.
                HubMenuTile(
                  icon: Icons.point_of_sale,
                  title: 'Shift Kasir',
                  subtitle: 'Buka shift, tutup shift, dan hitung uang laci',
                  color: const Color(0xFFF59E0B),
                  onTap: () async {
                    await Navigator.of(context).push(
                      MaterialPageRoute(
                          builder: (_) => const CashierShiftScreen()),
                    );
                    // Kembali dari sana, keadaannya mungkin sudah
                    // berubah — shift baru dibuka, atau baru ditutup.
                    _periksaShift();
                  },
                ),
                if (_shiftSaya != true)
                  _MenungguShift()
                else ...[
                HubGroupTile(
                  icon: Icons.point_of_sale_outlined,
                  title: 'Penjualan',
                  subtitle: 'Input pesanan, pending payment, riwayat',
                  color: const Color(0xFF10B981),
                  loadCount: () => restoId == null ? Future.value(0) : OrderRepository().pendingCashPaymentCount(restoId),
                  tiles: () => [
                    HubMenuTile(
                      icon: Icons.point_of_sale_outlined,
                      title: 'Kasir / Input Pesanan',
                      subtitle: 'Pilih produk, checkout, terima pembayaran',
                      color: const Color(0xFF10B981),
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => const PosHomeScreen()),
                      ),
                    ),
                    HubMenuTile(
                      icon: Icons.tv_outlined,
                      title: 'Layar Pelanggan',
                      subtitle: 'Buka di perangkat kedua yang menghadap pelanggan',
                      color: const Color(0xFF14B8A6),
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(
                            builder: (_) => const CustomerDisplayScreen()),
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
                  ],
                ),
                HubGroupTile(
                  icon: Icons.account_balance_wallet_outlined,
                  title: 'Keuangan',
                  subtitle: 'Saldo hari ini, petty cash, setor & pickup tunai',
                  color: const Color(0xFF6366F1),
                  loadCount: () => _penandaKeuangan(restoId),
                  tiles: () => [
                    BadgedHubTile(
                      icon: Icons.account_balance_wallet_outlined,
                      title: 'Saldo & Pengeluaran',
                      subtitle: 'Penghasilan hari ini, tunai di laci, petty cash',
                      color: const Color(0xFF6366F1),
                      loadCount: () => restoId == null
                          ? Future.value(0)
                          : PettyCashRepository().pendingCount(restoId),
                      destination: () => const FinanceBalanceScreen(),
                    ),
                    BadgedHubTile(
                      icon: Icons.account_balance_outlined,
                      title: 'Setor Saldo Cash',
                      subtitle: 'Setor ke rekening, atau serahkan ke petugas pickup',
                      color: const Color(0xFF0EA5E9),
                      loadCount: () => restoId == null
                          ? Future.value(0)
                          : CashDepositRepository().pendingCount(restoId),
                      destination: () => const CashDepositScreen(),
                    ),
                  ],
                ),
                HubGroupTile(
                  icon: Icons.tune,
                  title: 'Pengelolaan',
                  subtitle: 'Diskon dan promo yang berjalan di merchant ini',
                  color: const Color(0xFF8B5CF6),
                  tiles: () => [
                    HubMenuTile(
                      icon: Icons.local_offer_outlined,
                      title: 'Diskon',
                      subtitle: 'Promo per menu, bundling, atau minimum belanja',
                      color: const Color(0xFF10B981),
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => const DiscountScreen()),
                      ),
                    ),
                  ],
                ),
                const PenilaianTile(),
                ],
                const InboxTile(),
                HubMenuTile(
                    icon: Icons.brightness_6_outlined,
                    title: 'Tampilan',
                    subtitle: 'Mode terang, gelap, atau ikut setelan HP',
                    color: const Color(0xFF0EA5E9),
                    onTap: () => showAppearanceDialog(context),
                  ),
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

/// Keterangan saat berandanya masih sempit.
///
/// Tanpa ini, kasir yang menu-menunya belum muncul mengira aplikasinya
/// belum selesai memuat — lalu menunggu sesuatu yang tidak akan datang
/// sampai dia membuka shift.
class _MenungguShift extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final muted = KaataTheme.mutedOf(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: KaataTheme.softFillOf(context),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.lock_clock, size: 20, color: Color(0xFFF59E0B)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Buka shift dulu',
                    style:
                        TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                const SizedBox(height: 4),
                Text(
                  'Menu kasir, pesanan, dan keuangan terbuka setelah shift '
                  'dibuka — supaya uang di laci punya titik awal yang jelas '
                  'dan selisihnya nanti bisa ditelusuri.',
                  style: TextStyle(fontSize: 12.5, color: muted, height: 1.45),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
