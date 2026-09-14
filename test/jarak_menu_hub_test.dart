import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Jarak antar tombol di layar hub harus seragam.
///
/// Celah 24 di antara barisan yang semuanya berjarak 12 terbaca seperti
/// ada sesuatu yang gagal dimuat di situ — dan itu persis yang terjadi
/// saat sebuah tile dibuang tapi kedua SizedBox pengapitnya tertinggal.
void main() {
  test('tidak ada celah ganda di layar hub mana pun', () {
    final ganda = RegExp(
      r'const SizedBox\(height: 12\),\s*(?://[^\n]*\n\s*)*const SizedBox\(height: 12\),',
    );

    final temuan = <String>[];
    for (final f in Directory('lib/screens').listSync()) {
      if (f is! File || !f.path.endsWith('_home_screen.dart')) continue;
      final isi = f.readAsStringSync();
      for (final m in ganda.allMatches(isi)) {
        final baris = '\n'.allMatches(isi.substring(0, m.start)).length + 1;
        temuan.add('${f.path}:$baris');
      }
    }

    expect(temuan, isEmpty,
        reason: 'celah dobel bikin satu tombol terlihat terpisah sendiri');
  });

  /// Beranda Owner menyusun daftarnya sendiri, bukan lewat
  /// HubMenuLayout — dan dulu jaraknya ditulis tangan di antara tiap
  /// kartu.
  ///
  /// Itu rapi selama semua menunya muncul. Begitu paket Basic mencabut
  /// beberapa menu, kartunya hilang tapi dua SizedBox pengapitnya tetap
  /// tinggal, dan yang terlihat lubang selebar dua kali jarak biasa.
  ///
  /// Sekarang jaraknya disisipkan tileBerjarak, SESUDAH yang dicabut
  /// dibuang. Hasilnya diuji dengan benar-benar dibangun di
  /// jarak_menu_tercabut_test.dart — sumber yang benar tidak menjamin
  /// hasil yang benar setelah disaring.
  test('beranda Owner menyerahkan jaraknya ke tileBerjarak', () {
    final isi = File('lib/screens/owner_home_screen.dart').readAsStringSync();
    expect(isi, contains('tileBerjarak(context, ['));
    expect(isi, isNot(contains('const SizedBox(height: 12),')),
        reason: 'jarak yang ditulis tangan tertinggal saat menunya dicabut '
            'UAM — pakai tileBerjarak');
  });
}
