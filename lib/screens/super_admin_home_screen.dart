
import '../db/paket_langganan_repository.dart';
import 'pengajuan_langganan_screen.dart';
import '../providers/auth_provider.dart';
import '../theme.dart';
import '../utils/logout_confirm.dart';
import '../widgets/badged_hub_tile.dart';
import '../widgets/hub_group_tile.dart';
import '../widgets/hub_menu_tile.dart';
import '../widgets/inbox_tile.dart';
import '../widgets/kaata_logo.dart';
import '../widgets/responsive.dart';
import 'employee_management_screen.dart';
import '../db/support_repository.dart';
import 'market_report_screen.dart';
import 'support_admin_screen.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'publish_announcement_screen.dart';
import 'tautan_situs_screen.dart';
import 'restaurant_manage_list_screen.dart';
import 'bank_account_screen.dart';
import '../models/billing.dart';
import 'super_admin_billing_screen.dart';
import 'super_admin_uam_screen.dart';
import 'super_admin_finance_screen.dart';

/// Home screen for the 'super_admin' role — not scoped to any single
/// restaurant. Two jobs: manage employees across every resto (the app
/// previously had no UI for this at all), and manage restos (including
/// creating new ones — that's the "+ Resto Baru" FAB inside List Resto,
/// not a separate menu entry here).
class SuperAdminHomeScreen extends StatelessWidget {
  const SuperAdminHomeScreen({super.key});

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
    final name = auth.employeeName?.isNotEmpty == true ? auth.employeeName! : 'KaataGo Admin';
    final email = auth.user?.email;

    return Scaffold(
      backgroundColor: KaataTheme.backgroundOf(context),
      // Fixed header + scrolling menu, rather than a SliverAppBar: with
      // enough entries to scroll, a collapsing app bar took the logo,
      // name and email away with it. Only the menu should move.
      body: Column(
        children: [
          HubHeader(
            logo: const KaataLogo(size: 64),
            title: name,
            subtitle: email == null ? 'KaataGo Admin' : 'KaataGo Admin • $email',
            colorA: KaataTheme.brand,
            colorB: KaataTheme.brandDark,
            tampilkanTema: true,
          ),
          Expanded(
            child: HubMenuLayout(
              tiles: [
                HubGroupTile(
                  icon: Icons.storefront_outlined,
                  title: 'Merchant & Karyawan',
                  subtitle: 'Daftar merchant dan akun karyawan semua merchant',
                  color: const Color(0xFF0EA5E9),
                  tiles: () => [
                    HubMenuTile(
                      icon: Icons.storefront_outlined,
                      title: 'List Merchant',
                      subtitle: 'Lihat & edit semua merchant terdaftar di KaataGo',
                      color: const Color(0xFF0EA5E9),
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => const RestaurantManageListScreen()),
                      ),
                    ),
                    HubMenuTile(
                      icon: Icons.badge_outlined,
                      title: 'Kelola Karyawan',
                      subtitle: 'Tambah/edit/hapus akun Admin, Kasir, Chef, Finance — semua resto',
                      color: const Color(0xFF6366F1),
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => const EmployeeManagementScreen()),
                      ),
                    ),
                    HubMenuTile(
                      icon: Icons.admin_panel_settings_outlined,
                      title: 'Akses Menu (UAM)',
                      subtitle: 'Atur menu yang muncul & bisa diubah, per merchant dan per peran',
                      color: const Color(0xFFF59E0B),
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => const SuperAdminUamScreen()),
                      ),
                    ),
                  ],
                ),
                HubGroupTile(
                  icon: Icons.workspace_premium_outlined,
                  title: 'Langganan & Keuangan',
                  subtitle: 'Billing merchant, pendapatan, pembukuan KaataGo',
                  color: const Color(0xFF10B981),
                  tiles: () => [
                    // Pengajuan dari merchant yang sudah transfer dan
                    // sedang menunggu. Ditaruh di atas Billing Merchant
                    // karena yang menunggu di sini sedang tidak bisa
                    // memakai aplikasinya sama sekali.
                    BadgedHubTile(
                      icon: Icons.workspace_premium_outlined,
                      title: 'Pengajuan Langganan',
                      subtitle:
                          'Paket yang diajukan merchant, berikut bukti transfernya',
                      color: const Color(0xFFF59E0B),
                      loadCount: () =>
                          PaketLanggananRepository().jumlahMenunggu(),
                      destination: () => const PengajuanLanggananScreen(),
                    ),
                    HubMenuTile(
                      icon: Icons.receipt_long_outlined,
                      title: 'Billing Merchant',
                      subtitle: 'Harga & tanggal langganan tiap merchant, verifikasi pembayaran',
                      color: const Color(0xFF10B981),
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => const SuperAdminBillingScreen()),
                      ),
                    ),
                    // Rekening KaataGo sendiri, bukan rekening
                    // merchant. Inilah tujuan transfer yang dilihat
                    // merchant saat tagihan langganannya ditagih lewat
                    // transfer — tanpa satu pun baris di sini, kolom
                    // rekening di layar tagihannya kosong.
                    HubMenuTile(
                      icon: Icons.account_balance_wallet_outlined,
                      title: 'Rekening KaataGo',
                      subtitle: 'Rekening tujuan transfer tagihan langganan merchant',
                      color: const Color(0xFF0EA5E9),
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const BankAccountScreen(
                            restoId: kPlatformRestoId,
                            judul: 'Rekening KaataGo',
                          ),
                        ),
                      ),
                    ),
                    HubMenuTile(
                      icon: Icons.account_balance_outlined,
                      title: 'Finance',
                      subtitle: 'Pendapatan langganan, pembukuan KaataGo, jurnal semua merchant',
                      color: const Color(0xFF14B8A6),
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => const SuperAdminFinanceScreen()),
                      ),
                    ),
                  ],
                ),
                // Paling atas di antara menu yang berdiri sendiri.
                // Pengaduan yang menunggu jawaban adalah satu-satunya
                // isi beranda ini yang punya orang di ujung sana, sedang
                // menunggu.
                BadgedHubTile(
                  icon: Icons.support_agent,
                  title: 'Customer Service',
                  subtitle: 'Pengaduan dari pelanggan dan merchant',
                  color: const Color(0xFF0EA5E9),
                  loadCount: () => SupportRepository().milikSemuaBelumDibaca(),
                  destination: () => const SupportAdminScreen(),
                ),
                HubMenuTile(
                  icon: Icons.insights_outlined,
                  title: 'Analisa Pasar',
                  subtitle:
                      'Pelanggan & merchant teratas, dan yang belum bergerak',
                  color: const Color(0xFF6366F1),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                        builder: (_) => const MarketReportScreen()),
                  ),
                ),
                HubMenuTile(
                  icon: Icons.language,
                  title: 'Tautan Situs KaataGo',
                  subtitle: 'Alamat yang dibuka dari layar Tentang KaataGo',
                  color: const Color(0xFF0EA5E9),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                        builder: (_) => const TautanSitusScreen()),
                  ),
                ),
                HubMenuTile(
                    icon: Icons.campaign_outlined,
                    title: 'Kirim Pengumuman',
                    subtitle: 'Blast info versi baru ke semua kotak masuk',
                    color: const Color(0xFFF59E0B),
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const PublishAnnouncementScreen()),
                    ),
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
