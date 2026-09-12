import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Tindakan di kartu List Merchant.
///
/// Sebelumnya ada empat kontrol berjejer di tiap baris — chat, saklar
/// aktif, ubah, hapus. Pada nama merchant yang panjang keempatnya
/// berdesakan sampai teksnya terpotong, dan yang lebih berbahaya:
/// saklar aktif bersebelahan dengan tombol hapus, dua tindakan yang
/// akibatnya jauh berbeda dalam jarak satu ibu jari.
void main() {
  final daftar =
      File('lib/screens/restaurant_manage_list_screen.dart').readAsStringSync();
  final form =
      File('lib/screens/restaurant_create_screen.dart').readAsStringSync();

  test('semuanya berkumpul di satu tombol tindakan', () {
    expect(daftar, contains('PopupMenuButton<String>'));
    for (final nilai in ["value: 'wa'", "value: 'ubah'", "value: 'hapus'"]) {
      expect(daftar, contains(nilai));
    }
  });

  test('tidak ada lagi saklar aktif di daftarnya', () {
    expect(daftar, isNot(contains('Switch(')));
    expect(daftar, isNot(contains('_toggleActive')));
  });

  // Yang sudah dihapus cuma menawarkan satu tindakan; menu berisi ubah
  // dan hapus di sana tidak akan berpengaruh apa pun.
  test('yang dihapus tetap menawarkan Kembalikan saja', () {
    expect(daftar, contains('resto.isDeleted'));
    expect(daftar, contains("label: const Text('Kembalikan')"));
  });

  group('aktif/nonaktif pindah ke form ubah', () {
    test('saklarnya ada di sana dan ikut tersimpan', () {
      expect(form, contains("title: const Text('Merchant Aktif')"));
      expect(form, contains('active: _aktif,'));
    });

    // Akibatnya tidak terlihat dari layar itu: karyawannya berhenti bisa
    // masuk, dan merchantnya hilang dari daftar pilihan pelanggan.
    test('mematikannya ditanya dulu', () {
      expect(form, contains("title: const Text('Nonaktifkan merchant?')"));
      expect(form, contains("confirmLabel: 'Nonaktifkan'"));
    });

    // Tidak ada yang rusak karena sebuah merchant kembali bisa
    // berjualan.
    test('menyalakannya kembali tidak ditanya', () {
      final blok = form.substring(form.indexOf('Future<void> _ubahAktif'),
          form.indexOf('Future<void> _save()'));
      expect(blok, contains('if (nyala) {'));
    });
  });
}
