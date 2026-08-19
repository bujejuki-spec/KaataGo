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
}
