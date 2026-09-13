import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Saldo & Pengeluaran harus menyebut angka yang sama untuk semua peran,
/// dan berhenti menghitung uang yang sudah pindah ke perusahaan.
///
/// Dua aturan itu berkali-kali dilanggar tanpa sengaja, dan cara
/// melanggarnya selalu sama: sebuah angka dijumlahkan dari daftar yang
/// dibatasi RLS, atau dari uang yang sudah punya tempat di layar lain.
/// Tes ini menjaga keduanya.
void main() {
  final layar =
      File('lib/screens/finance_balance_screen.dart').readAsStringSync();

  String rumus(String dari, String sampai) =>
      layar.substring(layar.indexOf(dari), layar.indexOf(sampai));

  group('angkanya sama untuk semua peran', () {
    // Daftar selisih kasir dibatasi RLS — kasir cuma melihat miliknya
    // sendiri. Menjumlahkannya di layar membuat isi laci berbeda antar
    // peran, padahal lacinya cuma satu dan isinya bisa dihitung tangan.
    test('isi laci dijawab server, bukan dihitung dari daftar selisih', () {
      expect(layar, contains('CashierShiftRepository().saldoCashLaci'));
      expect(layar, contains('_saldoLaciServer ?? _cashBalanceLokal'));
    });

    // Angka perkiraan yang tampil seperti angka pasti adalah yang paling
    // menyesatkan.
    test('cadangan lokalnya mengaku perkiraan', () {
      expect(layar, contains('perkiraan: _saldoLaciServer == null'));
      expect(layar, contains('Perkiraan — gagal menghubungi server'));
    });

    test('Saldo Non Cash tidak menyentuh daftar selisih sama sekali', () {
      final b = rumus('int get _nonCashBalance', 'int get _pettyCashToppedUp');
      expect(b, isNot(contains('selisih')));
      expect(b, contains('_nonCashIncome'));
    });
  });

  group('yang sudah pindah ke perusahaan tidak dihitung lagi', () {
    test('setoran bank dan cash pickup tidak masuk Saldo Non Cash', () {
      final b = rumus('int get _nonCashBalance', 'int get _pettyCashToppedUp');
      expect(b, isNot(contains('_setoranKeRekening')));
      expect(b, isNot(contains('_depositedTotal')));
    });

    test('setoran modal tidak masuk Saldo Non Cash', () {
      final b = rumus('int get _nonCashBalance', 'int get _pettyCashToppedUp');
      expect(b, isNot(contains('_topup')));
    });

    // Pelunasan selisih lewat transfer mendarat di rekening, dan sejak
    // jurnal_selisih_ke_bank.sql ia dikreditkan ke Saldo Bank Perusahaan.
    test('pelunasan selisih transfer tidak masuk Saldo Non Cash', () {
      expect(layar, isNot(contains('selisihDibayarTransfer')));
    });

    // Yang paling halus: pengeluaran dari kas/rekening perusahaan sempat
    // ikut terhitung di sini — dan ia mengurangi sisa petty cash kasir
    // untuk uang yang tidak pernah keluar dari kas kecil.
    test('pengeluaran perusahaan tidak mengurangi petty cash', () {
      expect(layar, contains("if (e.fundSource == 'petty') e,"));
      final b = rumus('int get _pettyCashBalance', 'int get _totalBalance');
      expect(b, contains('_expensesSemua'));
    });

    test('layar harian hanya mencatat pengeluaran petty cash', () {
      expect(layar, contains("const namaSumber = 'Petty Cash';"));
    });
  });
}
