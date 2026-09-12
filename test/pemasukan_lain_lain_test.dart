import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Selisih lebih yang diakui sebagai pendapatan, di layar Pemasukan.
///
/// Uangnya masuk tapi tidak lewat satu pesanan pun — tidak ada yang
/// dijual. Karena itu ia tidak bisa dibaca dari `orders`, dan sebelum
/// ini layar Pemasukan tidak pernah menyebutnya: pendapatan yang sudah
/// diakui di jurnal tapi tidak terlihat di layar yang justru bernama
/// Pemasukan.
void main() {
  final layar =
      File('lib/screens/finance_income_screen.dart').readAsStringSync();

  test('dibaca dari jurnalnya, bukan dari pesanan palsu', () {
    // Membuatkannya baris pesanan supaya muncul di sini berarti laporan
    // menu terlaris ikut memuat penjualan yang tidak pernah terjadi.
    expect(layar, contains("a.paymentMethod == 'other_income'"));
    expect(layar, contains('GlJournalRepository().getForResto'));
    expect(layar, contains('barisBerlaku(jurnal)'));
  });

  test('hanya sisi kredit yang dihitung', () {
    expect(layar, contains('e.entryType == JournalEntryType.credit'));
  });

  test('masuk ke tanggal saat diakui, bukan tanggal shiftnya', () {
    // Itu tanggal keputusannya, dan itu yang dicari orang saat
    // menelusuri kenapa pemasukan hari itu naik.
    expect(layar, contains('e.entryDate.year, e.entryDate.month'));
  });

  test('ikut dijumlahkan, bukan cuma dipajang', () {
    expect(layar, contains('lainLain.fold(0, (sum, e) => sum + e.amount)'));
    expect(layar,
        contains('_lainLain.fold(0, (sum, e) => sum + e.amount)'));
  });

  test('hari yang isinya cuma pendapatan lain-lain tetap muncul', () {
    // Tanpa ini, selisih yang diakui pada hari resto tutup tidak punya
    // kartu hari untuk ditempeli.
    expect(layar, contains('byDay.putIfAbsent(d, () => []);'));
    expect(layar, contains('_orders.isEmpty && _lainLain.isEmpty'));
  });

  test('gagal membaca jurnal tidak mengosongkan layarnya', () {
    final blok = layar.substring(layar.indexOf('Future<void> _load()'),
        layar.indexOf('List<_DayIncome> _groupByDay()'));
    expect(blok, contains('} catch (_) {'));
  });

  group('kartu Penghasilan di Saldo & Pengeluaran', () {
    final saldo =
        File('lib/screens/finance_balance_screen.dart').readAsStringSync();

    // Ia menjumlahkan Saldo Cash dan Saldo Non Cash yang sudah berdiri
    // sendiri tepat di atasnya — angka ketiga yang tidak menjawab
    // pertanyaan baru.
    test('tidak lagi dipajang untuk merchant', () {
      expect(saldo, isNot(contains("_untukPlatform ? 'Uang Masuk' : 'Penghasilan'")));
    });

    // Pembukuan KaataGo tidak punya pecahan Cash/Non Cash, jadi ini
    // satu-satunya angka uang masuknya.
    test('pembukuan KaataGo tetap punya Uang Masuk', () {
      expect(saldo, contains('if (_untukPlatform) ...['));
      expect(saldo, contains("label: 'Uang Masuk'"));
    });
  });
}
