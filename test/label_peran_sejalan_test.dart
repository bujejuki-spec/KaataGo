import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Nama peran yang dibaca orang ditulis di TIGA tempat, dan ketiganya
/// tidak boleh menyebut peran yang sama dengan nama yang berbeda.
///
/// ── Apa yang terjadi ─────────────────────────────────────────────────
///
/// Peran dapur diganti namanya jadi "Waiters" di
/// `lib/providers/auth_provider.dart` dan `lib/utils/katalog_menu.dart`.
/// Salinan ketiga di `lib/screens/employee_management_screen.dart`
/// tertinggal, dan justru layar ITU yang dipakai memilih peran
/// seseorang.
///
/// Jadi yang menambahkan karyawan memilih "Chef", lalu orang itu masuk
/// dan berandanya menyebut dirinya "Waiters". Tidak ada galat, tidak
/// ada yang janggal secara teknis — cuma dua nama untuk satu pekerjaan,
/// dan yang menanggung kebingungannya pemilik warung.
///
/// ── Kenapa bukan "ketiganya harus identik" ───────────────────────────
///
/// Karena ada perbedaan yang DISENGAJA. `employee_management_screen`
/// mengeja 'HR (Human Resource)' sementara dua lainnya cukup 'HR', dan
/// alasannya ditulis di sana: daftar itu yang dibaca saat memilih peran
/// seseorang, dan singkatan dua huruf di antara "Kasir" dan "Finance"
/// menuntut yang memilihnya sudah tahu artinya.
///
/// Jadi yang ditolak bukan perbedaan panjang, melainkan perbedaan NAMA:
/// ejaan yang lebih lengkap boleh, nama yang lain sama sekali tidak.
void main() {
  String baca(String jalur) => File(jalur).readAsStringSync();

  /// Isi sebuah peta label, dibaca dari potongan sumbernya.
  ///
  /// Melempar, bukan memakai `expect`: ini dijalankan saat berkas tesnya
  /// dimuat, di luar tes mana pun — dan `expect` di sana gagal sebagai
  /// "OutsideTestException", yang tidak menyebut apa pun tentang peta
  /// yang tidak terbaca.
  Map<String, String> peta(String isi, String penanda, RegExp baris) {
    final mulai = isi.indexOf(penanda);
    if (mulai < 0) throw StateError('$penanda tidak ditemukan');
    final blok = isi.substring(mulai, isi.indexOf('};', mulai));
    final hasil = <String, String>{};
    for (final m in baris.allMatches(blok)) {
      hasil[m.group(1)!] = m.group(2)!;
    }
    if (hasil.isEmpty) throw StateError('tidak ada baris terbaca di $penanda');
    return hasil;
  }

  final sumber = <String, Map<String, String>>{
    'auth_provider': peta(
      baca('lib/providers/auth_provider.dart'),
      'const _roleDisplayLabels = {',
      RegExp(r"EmployeeRole\.(\w+): '([^']+)'"),
    ),
    'katalog_menu': peta(
      baca('lib/utils/katalog_menu.dart'),
      'const labelPeran = <String, String>{',
      RegExp(r"'(\w+)': '([^']+)'"),
    ),
    'employee_management': peta(
      baca('lib/screens/employee_management_screen.dart'),
      'const _roleLabels = {',
      RegExp(r"'(\w+)': '([^']+)'"),
    ),
  };

  /// `auth_provider` memakai nama enum (superAdmin), dua lainnya nilai
  /// basis data (super_admin). Disamakan supaya bisa dibandingkan.
  String kunci(String k) => k == 'superAdmin' ? 'super_admin' : k;

  test('tidak ada peran yang punya dua nama berbeda', () {
    final per = <String, Map<String, String>>{};
    sumber.forEach((asal, m) {
      m.forEach((k, label) {
        per.putIfAbsent(kunci(k), () => {})[asal] = label;
      });
    });

    final bentrok = <String>[];
    per.forEach((peran, label) {
      final nilai = label.values.toSet();
      if (nilai.length == 1) return;

      // Ejaan yang lebih lengkap boleh: 'HR' dan 'HR (Human Resource)'
      // menyebut hal yang sama. Yang satu harus awalan yang lain.
      final terpendek =
          nilai.reduce((a, b) => a.length <= b.length ? a : b);
      if (nilai.every((v) => v.startsWith(terpendek))) return;

      final sebutan =
          label.entries.map((e) => '${e.key}: "${e.value}"').join(', ');
      bentrok.add('$peran — $sebutan');
    });

    expect(bentrok, isEmpty,
        reason: 'satu peran disebut dengan nama yang berbeda di layar '
            'yang berbeda:\n  ${bentrok.join("\n  ")}');
  });

  test('layar pemilih peran tidak menyebut Chef lagi', () {
    // Disebut satu per satu, bukan hanya diandalkan pada pemeriksaan di
    // atas: kalau nanti ketiganya sama-sama ketinggalan, yang di atas
    // diam karena memang sepakat — sepakat pada nama yang salah.
    for (final e in sumber.entries) {
      expect(e.value.values, isNot(contains('Chef')), reason: e.key);
    }
    expect(sumber['employee_management']!['chef'], 'Waiters');
  });

  test("nilainya di basis data tetap 'chef'", () {
    // Yang berganti labelnya, bukan nilainya: 'chef' disebut puluhan
    // kali di kebijakan RLS, dan menggantinya berarti menyentuh
    // seluruhnya sekaligus memigrasikan baris karyawan yang ada.
    expect(baca('lib/providers/auth_provider.dart'),
        contains("EmployeeRole.chef: 'chef'"));
    expect(sumber['employee_management']!.containsKey('chef'), isTrue);
  });
}
