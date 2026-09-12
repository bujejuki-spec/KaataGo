import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Saldo & Pengeluaran untuk Kasir dan Admin: hari ini saja.
///
/// Layar ini menjumlahkan sejak hari pertama, dan angka itu adalah saldo
/// perusahaan. Tidak ada pekerjaan di meja kasir yang membutuhkannya.
///
/// Yang dijaga tes ini bukan pemotongannya — melainkan apa yang TIDAK
/// boleh ikut terpotong. Uang yang sedang dipegang orangnya (isi laci
/// dan petty cash) harus tetap dihitung utuh, karena keduanya tidak ikut
/// berganti hari:
///
/// - Saldo Cash yang dipotong per hari membuat uang kemarin yang belum
///   disetor lenyap dari layar, dan selisih tutup shift yang sebenarnya
///   benar terbaca sebagai kurang.
/// - Saldo Petty Cash yang dipotong per hari membuat batas "maksimal
///   sekian" pada pencatatan pengeluaran ikut salah — kasir bisa
///   mencatat pengeluaran lebih besar dari uang yang ada di tangannya.
void main() {
  final layar =
      File('lib/screens/finance_balance_screen.dart').readAsStringSync();

  String blok(String dari, String sampai) =>
      layar.substring(layar.indexOf(dari), layar.indexOf(sampai));

  // Semua peran merchant, bukan cuma kasir dan admin.
  //
  // Mulanya Finance dan Owner dikecualikan, dengan anggapan mereka
  // membutuhkan angka sejak hari pertama di layar ini. Ternyata yang
  // mereka butuhkan adalah saldo perusahaan — dan itu sekarang punya
  // layarnya sendiri, yang menyebut uang tunai dan uang rekening secara
  // terpisah.
  test('dipotong per hari untuk seluruh peran merchant', () {
    final b = blok('bool get _harianSaja', 'bool get _needsApproval');
    expect(b, contains('!_untukPlatform'));
    // Pembukuan KaataGo sendiri tidak punya laci kasir, dan memotongnya
    // per hari membuat layarnya berbunyi nol.
    expect(b, isNot(contains('auth.isKasir')));
  });

  test('penghasilan non-tunai dan pengeluaran ikut terpotong', () {
    expect(layar, contains("o.paymentMethod != 'cash'"));
    expect(layar, contains('!harian || sekarang(o.createdAt)'));
    expect(layar, contains('!harian || sekarang(e.createdAt)'));
  });

  test('penghasilan tunai tidak ikut terpotong', () {
    // Baris tunainya berdiri sendiri tanpa syarat harian — kalau suatu
    // saat syarat itu ditambahkan, isi laci berhenti cocok dengan tutup
    // shift.
    final b = blok('_cashIncome = orders', '_nonCashIncome = orders');
    expect(b, isNot(contains('harian')));
  });

  // Satu pelunasan transfer sempat menambah Saldo Non Cash setiap hari
  // selamanya: daftarnya dimuat utuh dan tidak pernah ikut dipotong,
  // jadi angkanya muncul di layar harian tanpa ada pemasukan apa pun
  // hari itu.
  test('selisih yang dilunasi transfer ikut tanggal pelunasannya', () {
    final b = blok('int get _nonCashBalance', 'int get _pettyCashToppedUp');
    expect(b, contains('selisihDibayarTransfer(_selisihTransferHarian)'));
    expect(layar, contains('v.settledAt != null && sekarang(v.settledAt!)'));
  });

  // Tapi daftar penuhnya tetap dipakai isi laci: selisih kurang yang
  // belum dibayar mengurangi laci sejak hari ia terjadi.
  test('isi laci tetap memakai seluruh riwayat selisih', () {
    final b = blok('int get _cashBalance', 'int get _nonCashBalance');
    expect(b, contains('selisih: _selisih,'));
  });

  test('isi laci dihitung dari seluruh riwayat', () {
    final b = blok('int get _cashBalance', 'int get _nonCashBalance');
    expect(b, contains('deposits: _depositsSemua'));
    expect(b, contains('pettyCash: _pettyCashSemua'));
  });

  test('sisa petty cash dihitung dari seluruh riwayat', () {
    final b = blok('int get _pettyCashBalance', 'int get _totalBalance');
    expect(b, contains('_expensesSemua'));
    expect(b, isNot(contains('_expenseBalance')));

    final topup =
        blok('int get _pettyCashToppedUp', 'int get _pettyCashPending');
    expect(topup, contains('_pettyCashSemua'));
  });

  test('layarnya mengatakan yang sedang ditampilkan', () {
    expect(layar, contains("_harianSaja ? 'Saldo Hari Ini' : 'Saldo Total'"));
  });
}
