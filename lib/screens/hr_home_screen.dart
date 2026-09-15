import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/auth_provider.dart';
import '../theme.dart';
import '../utils/logout_confirm.dart';
import '../widgets/hub_menu_tile.dart';
import '../widgets/kaata_logo.dart';
import '../widgets/resto_switcher.dart';
import '../widgets/responsive.dart';
import '../widgets/support_fab.dart';
import '../widgets/tampak_menu.dart';
import 'absensi_report_screen.dart';
import 'absensi_screen.dart';
import 'employee_management_screen.dart';
import 'settings_screen.dart';

/// Beranda HR: orang, kehadirannya, dan tidak lebih dari itu.
///
/// ── Yang sengaja tidak ada di sini ───────────────────────────────────
///
/// Gaji. Tidak menyetel gaji, tidak melihat rekap payroll, tidak
/// mengunduh daftar transfer.
///
/// Godaannya besar, karena absensi dan payroll memang berdampingan dan
/// yang mengurus kehadiran terasa "seharusnya" juga mengurus bayarannya.
/// Tapi keduanya dipisah justru supaya yang mencatat kehadiran bukan
/// orang yang sama dengan yang menentukan bayaran — satu orang yang
/// memegang keduanya bisa menandai rekannya alpa lalu memotong gajinya,
/// sendirian, tanpa satu pun mata kedua.
///
/// Batas itu ditegakkan di server juga, bukan cuma dengan tidak
/// menampilkan menunya di sini.
class HrHomeScreen extends StatelessWidget {
  const HrHomeScreen({super.key});

  Future<void> _logout(BuildContext context) async {
    if (!await confirmLogout(context)) return;
    if (!context.mounted) return;
    await context.read<AuthProvider>().signOut();
    if (!context.mounted) return;
    Navigator.of(context).popUntil((r) => r.isFirst);
  }

  void _open(BuildContext context, Widget layar) {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => layar));
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final nama =
        auth.employeeName?.isNotEmpty == true ? auth.employeeName! : 'HR';
    final email = auth.user?.email;

    return Scaffold(
      backgroundColor: KaataTheme.backgroundOf(context),
      floatingActionButton: const SupportFab(),
      body: Column(
        children: [
          HubHeader(
            logo: const KaataLogo(size: 64),
            title: nama,
            subtitle: email == null ? 'HR' : 'HR • $email',
            colorA: const Color(0xFF7C3AED),
            colorB: const Color(0xFF4C1D95),
            tampilkanTema: true,
            tampilkanPaket: true,
            trailing: const RestoSwitcher(),
          ),
          Expanded(
            child: ResponsiveCenter(
              maxWidth: 900,
              child: ListView(
                padding:
                    const EdgeInsets.fromLTRB(20, 20, 20, kFabSafeBottom),
                // Jaraknya disisipkan SESUDAH menu yang dicabut UAM
                // dibuang, supaya tidak ada lubang selebar dua kali
                // jarak biasa di tempat kartu yang hilang.
                children: tileBerjarak(context, [
                  // Absen sendiri berdiri paling atas.
                  //
                  // HR juga karyawan, dan yang dikerjakannya pertama tiap
                  // pagi adalah absennya sendiri — bukan memeriksa absen
                  // orang lain.
                  HubMenuTile(
                    icon: Icons.how_to_reg,
                    title: 'Absensi',
                    subtitle: 'Absen masuk, absen pulang, izin dan sakit',
                    color: const Color(0xFF10B981),
                    onTap: () => _open(context, const AbsensiScreen()),
                  ),
                  HubMenuTile(
                    icon: Icons.fact_check_outlined,
                    title: 'Absensi Karyawan',
                    subtitle:
                        'Kehadiran seluruh karyawan, jam kerja, dan buktinya',
                    color: const Color(0xFF7C3AED),
                    onTap: () => _open(context, const AbsensiReportScreen()),
                  ),
                  HubMenuTile(
                    icon: Icons.groups_outlined,
                    title: 'Kelola Karyawan',
                    subtitle: 'Tambah, ubah, nonaktifkan, dan atur perannya',
                    color: const Color(0xFF2563EB),
                    onTap: () =>
                        _open(context, const EmployeeManagementScreen()),
                  ),
                  HubMenuTile(
                    icon: Icons.settings_outlined,
                    title: 'Pengaturan',
                    subtitle: 'Tampilan, bahasa, dan keluar dari akun',
                    color: const Color(0xFF64748B),
                    onTap: () => _open(context, const SettingsScreen()),
                  ),
                  HubMenuTile(
                    icon: Icons.logout,
                    title: 'Keluar',
                    subtitle: 'Keluar dari akun ini',
                    color: const Color(0xFFEF4444),
                    onTap: () => _logout(context),
                  ),
                ]),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
