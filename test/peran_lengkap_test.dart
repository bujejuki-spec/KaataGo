import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Tiap peran yang sah harus bisa dipilih, diberi nama, dan diberi warna.
///
/// ── Kenapa tes ini ada ───────────────────────────────────────────────
///
/// Peran HR ditambahkan ke enum, ke katalog UAM, ke RLS, dan ke
/// berandanya sendiri — lalu tetap tidak muncul di dropdown Kelola
/// Karyawan, karena layar itu menyimpan daftar perannya SENDIRI.
///
/// Tidak ada yang gagal karenanya. Aplikasinya tetap jalan, tesnya tetap
/// hijau, dan yang menemukannya orang yang membuka dropdown itu lalu
/// bertanya kenapa perannya tidak ada.
///
/// Empat daftar untuk satu hal berarti tiga peluang terlewat. Selama
/// keempatnya masih berdiri sendiri, tes ini yang menjaganya tetap sama.
void main() {
  final auth = File('lib/providers/auth_provider.dart').readAsStringSync();
  final layar =
      File('lib/screens/employee_management_screen.dart').readAsStringSync();
  final katalog = File('lib/utils/katalog_menu.dart').readAsStringSync();

  /// Nama kode tiap peran, dari satu-satunya sumber yang mengikat:
  /// nilai yang benar-benar tersimpan di kolom `employees.role`.
  List<String> peranDb() {
    final mulai = auth.indexOf('const _roleDbValues');
    final blok = auth.substring(mulai, auth.indexOf('};', mulai));
    return RegExp(r"'([a-z_]+)'")
        .allMatches(blok)
        .map((m) => m.group(1)!)
        .toList();
  }

  test('enum dan nilai basis datanya tidak berselisih jumlah', () {
    final enumBlok = auth.substring(
        auth.indexOf('enum EmployeeRole'), auth.indexOf('}', auth.indexOf('enum EmployeeRole')));
    final jumlahEnum =
        enumBlok.split('{').last.split(',').where((e) => e.trim().isNotEmpty).length;
    expect(peranDb().length, jumlahEnum);
  });

  test('semua peran bisa dipilih di Kelola Karyawan', () {
    // Peran yang tidak ada di daftar ini tidak bisa diberikan kepada
    // siapa pun dari dalam aplikasi — hanya lewat SQL.
    for (final peran in peranDb()) {
      expect(layar, contains("'$peran':"),
          reason: 'Peran "$peran" tidak ada di dropdown Kelola Karyawan.');
    }
  });

  test('semua peran punya warna lencananya sendiri', () {
    final mulai = layar.indexOf('const _roleColors');
    final blok = layar.substring(mulai, layar.indexOf('};', mulai));
    for (final peran in peranDb()) {
      expect(blok, contains("'$peran':"),
          reason: 'Peran "$peran" tidak punya warna, jadi lencananya abu-abu '
              'seperti peran yang tidak dikenal.');
    }
  });

  test('peran merchant punya katalog menu UAM', () {
    // KaataGo Admin sengaja tidak ada di katalog: dialah yang mengatur,
    // dan peran yang bisa mengunci dirinya sendiri dari layar
    // pengaturannya adalah pintu yang kuncinya tertinggal di dalam.
    for (final peran in peranDb().where((p) => p != 'super_admin')) {
      expect(katalog, contains("'$peran': ["),
          reason: 'Peran "$peran" tidak punya katalog menu UAM.');
    }
  });

  test('HR tetap tidak memegang payroll', () {
    // Batas yang paling mudah hilang saat seseorang menambah menu ke
    // katalog HR tanpa membaca alasannya.
    final mulai = katalog.indexOf("'hr': [");
    final blok = katalog.substring(mulai, katalog.indexOf('],', mulai));
    expect(blok, isNot(contains('Payroll')),
        reason: 'Yang mencatat kehadiran tidak boleh jadi orang yang sama '
            'dengan yang menentukan bayarannya — lihat catatan di '
            'lib/screens/hr_home_screen.dart.');
  });
}
