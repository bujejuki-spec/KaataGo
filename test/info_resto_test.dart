import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final layar =
      File('lib/screens/restaurant_info_screen.dart').readAsStringSync();

  group('nama resto di Info Resto', () {
    test('bukan isian yang dimatikan', () {
      // Kotak isian yang selalu abu-abu menjanjikan sesuatu yang tidak
      // pernah terjadi.
      expect(layar, isNot(contains("label: requiredLabel('Nama Resto')")));
      expect(layar, contains("'Nama Resto',"));
    });

    test('tanpa label mengambang yang bisa terpotong', () {
      // Label mengambang selalu terpotong di tepi atas area gulir, dan
      // di sini ia tidak perlu ada.
      final blok = layar.substring(
          layar.indexOf("'Nama Resto',") - 900, layar.indexOf("'Nama Resto',"));
      expect(blok, isNot(contains('InputDecoration')));
    });

    test('nilainya tetap terkirim saat disimpan', () {
      // Kolomnya tidak bisa diubah, tapi tetap ikut dalam payload —
      // menghapusnya akan mengosongkan nama restonya saat disimpan.
      expect(layar, contains('name: _nameCtrl.text.trim(),'));
      expect(layar, contains('_nameCtrl.text = resto.name;'));
    });
  });

  group('keterangannya', () {
    test('menyebut KaataGo Admin dan cara menghubunginya', () {
      // Ditulis terpotong beberapa baris di sumbernya, jadi yang
      // diperiksa potongannya — digabung ulang tanpa jeda baris.
      final rapat = layar.replaceAll(RegExp(r"'\s*\n\s*'"), '');
      expect(
          rapat,
          contains('Hanya KaataGo Admin yang bisa ubah nama resto, '
              'silahkan hubungi KaataGo Admin jika ada perubahan nama resto'));
    });

    test('wording lamanya sudah tidak ada', () {
      expect(layar, isNot(contains('Cuma Super Admin')));
    });
  });
}
