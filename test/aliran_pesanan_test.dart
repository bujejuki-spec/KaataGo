import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Dua kebutuhan yang dulu dilayani satu fungsi, dan itu sumbernya.
///
/// `watchAll` menarik seluruh riwayat pesanan resto lewat realtime, dan
/// dipakai dua golongan pemakai sekaligus: layar langsung yang cuma
/// menampilkan antrean hari ini, dan layar Finance yang menjumlahkan
/// sejak awal. Membatasinya menyenangkan yang pertama dan diam-diam
/// merusak yang kedua — Saldo Cash yang cuma menghitung sebulan tetap
/// muncul, tetap terlihat wajar, dan salah tanpa satu pun pesan galat.
///
/// Yang dijaga di sini letaknya di kode, bukan hasilnya: kerusakannya
/// tidak menampakkan diri pada satu angka mana pun yang bisa diuji tanpa
/// data setahun.
void main() {
  final repo = File('lib/db/order_repository.dart').readAsStringSync();

  group('aliran langsung dibatasi', () {
    test('watchAktif memakai limit', () {
      final blok = repo.substring(repo.indexOf('Stream<List<CustomerOrder>> watchAktif'));
      expect(blok.substring(0, blok.indexOf('}')), contains('.limit('));
    });

    test('watchAll yang tak berbatas sudah tidak ada', () {
      expect(repo, isNot(contains('Stream<List<CustomerOrder>> watchAll(')));
    });
  });

  group('Finance tetap melihat semuanya', () {
    const layarFinance = [
      'lib/screens/finance_balance_screen.dart',
      'lib/screens/finance_income_screen.dart',
      'lib/screens/finance_report_screen.dart',
      'lib/screens/cash_deposit_screen.dart',
    ];

    for (final jalur in layarFinance) {
      test('${jalur.split('/').last} membaca seluruh pesanan', () {
        final isi = File(jalur).readAsStringSync();
        expect(isi, contains('semua('),
            reason: 'Layar ini menjumlahkan sejak awal; membacanya lewat '
                'aliran yang dibatasi membuat angkanya salah diam-diam.');
        expect(isi, isNot(contains('watchAktif(')),
            reason: 'watchAktif dibatasi dan tidak boleh jadi sumber angka '
                'yang menjumlahkan sejak awal.');
      });
    }
  });

  test('semua() bukan stream', () {
    expect(repo, contains('Future<List<CustomerOrder>> semua(String restoId)'));
  });
}
