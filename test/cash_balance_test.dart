import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pos_app/models/cash_deposit.dart';
import 'package:pos_app/models/petty_cash_entry.dart';
import 'package:pos_app/utils/cash_balance.dart';

CashDeposit _setoran(int amount, DepositStatus status) => CashDeposit(
      id: 'd-$amount-${status.name}',
      restoId: 'r1',
      amount: amount,
      status: status,
      createdBy: 'kasir@contoh.com',
      createdAt: DateTime(2026, 8, 14),
    );

PettyCashEntry _petty(
  int amount,
  PettyCashStatus status, {
  PettyCashSource source = PettyCashSource.cashWithdrawal,
}) =>
    PettyCashEntry(
      id: 'p-$amount-${status.name}',
      restoId: 'r1',
      amount: amount,
      source: source,
      status: status,
      createdBy: 'kasir@contoh.com',
      createdAt: DateTime(2026, 8, 14),
    );

void main() {
  group('cashOnHand', () {
    test('pengajuan petty cash yang ditolak tidak mengurangi laci', () {
      // Inilah selisih yang sempat muncul: Saldo & Pengeluaran membuang
      // yang ditolak, Setor Saldo Cash tidak — dan keduanya sama-sama
      // mengaku menyebut "tunai di laci".
      final tunai = cashOnHand(
        cashIncome: 303620,
        deposits: [_setoran(123689, DepositStatus.approved)],
        pettyCash: [
          _petty(10000, PettyCashStatus.approved),
          _petty(10000, PettyCashStatus.rejected),
        ],
      );

      expect(tunai, 303620 - 123689 - 10000);
    });

    test('yang masih menunggu keputusan tetap dikurangi', () {
      // Fisik uangnya sudah keluar dari laci sejak diajukan, apa pun
      // keputusannya nanti.
      final tunai = cashOnHand(
        cashIncome: 100000,
        deposits: [_setoran(20000, DepositStatus.pending)],
        pettyCash: [_petty(5000, PettyCashStatus.pending)],
      );

      expect(tunai, 75000);
    });

    test('setoran yang ditolak dikembalikan ke laci', () {
      final tunai = cashOnHand(
        cashIncome: 100000,
        deposits: [
          _setoran(20000, DepositStatus.approved),
          _setoran(30000, DepositStatus.rejected),
        ],
        pettyCash: const [],
      );

      expect(tunai, 80000);
    });

    test('petty cash dari sumber lain tidak menyentuh laci', () {
      // Withdraw dari saldo non-tunai dan top up manual tidak pernah
      // lewat laci kasir.
      final tunai = cashOnHand(
        cashIncome: 100000,
        deposits: const [],
        pettyCash: [
          _petty(50000, PettyCashStatus.approved,
              source: PettyCashSource.incomeWithdrawal),
          _petty(25000, PettyCashStatus.approved,
              source: PettyCashSource.manual),
        ],
      );

      expect(tunai, 100000);
    });
  });

  // Setoran memindahkan uang, bukan menghilangkannya. Sebelumnya ia
  // dikurangkan dari Saldo Cash tapi tidak ditambahkan ke Saldo Non
  // Cash — Saldo Total menambahkannya sendiri di tingkat atas, jadi
  // totalnya benar sementara rinciannya berbohong.
  group('setoran tunai di layar saldo', () {
    final layar =
        File('lib/screens/finance_balance_screen.dart').readAsStringSync();

    // Setoran TIDAK lagi mendarat di Saldo Non Cash.
    //
    // Begitu disetujui, uangnya berhenti jadi uang merchant dan jadi
    // uang perusahaan — tempatnya di layar Saldo Perusahaan. Menghitung
    // di kedua layar membuat uang yang sama muncul dua kali.
    test('setoran pindah ke Saldo Perusahaan, bukan ke Saldo Non Cash', () {
      final blok = layar.substring(layar.indexOf('int get _nonCashBalance'));
      final rumus = blok.substring(0, blok.indexOf(';'));
      expect(rumus, isNot(contains('_setoranKeRekening')));
      expect(rumus, isNot(contains('_depositedTotal')));
      // Yang tersisa cuma penjualan non-tunai hari ini, dikurangi yang
      // ditarik ke petty cash. Pelunasan selisih lewat transfer juga
      // sudah pindah: uangnya mendarat di rekening, dan sejak
      // jurnal_selisih_ke_bank.sql ia dikreditkan ke Saldo Bank
      // Perusahaan.
      expect(rumus, contains('_nonCashIncome'));
      expect(rumus, isNot(contains('selisihDibayarTransfer')));
    });

    test('tidak ditambahkan lagi di Saldo Total', () {
      expect(layar, contains('return _incomeBalance + _pettyCashBalance;'));
      expect(layar,
          isNot(contains('_incomeBalance + _pettyCashBalance + _setoranKeRekening')));
      expect(layar,
          isNot(contains('_incomeBalance + _pettyCashBalance + _depositedTotal')));
    });

    // Kedua kartu harus berjumlah sama dengan Penghasilan; kalau tidak,
    // ada uang yang tidak muncul di mana pun.
    test('Penghasilan tetap jumlah keduanya', () {
      expect(layar,
          contains('int get _incomeBalance => _cashBalance + _nonCashBalance;'));
    });
  });

  // Dua layar sama-sama menyebut "tunai di laci". Selama keduanya
  // memanggil cashOnHand, keduanya berubah bersama; begitu salah satunya
  // menyalin rumusnya, salinan itu berhenti ikut berubah — dan itulah
  // yang terjadi saat selisih shift mulai diperhitungkan: Setor Saldo
  // Cash tertinggal, lalu kedua layar menampilkan angka berbeda tanpa
  // ada cara menebak yang mana yang benar.
  group('Setor Saldo Cash memakai perhitungan yang sama', () {
    final layar =
        File('lib/screens/cash_deposit_screen.dart').readAsStringSync();

    test('memanggil cashOnHand, bukan menghitung sendiri', () {
      final blok = layar.substring(layar.indexOf('int get _cashOnHand'));
      expect(blok.substring(0, blok.indexOf(';')), contains('cashOnHand('));
    });

    test('ikut menyertakan selisih shift', () {
      final blok = layar.substring(layar.indexOf('int get _cashOnHand'));
      expect(blok.substring(0, blok.indexOf(';')), contains('selisih:'));
    });
  });

  // Kartu Rekening Bank sempat membaca kolom lama di `settings` —
  // salinan yang ditinggalkan apa adanya saat rekening dipindah jadi
  // entitas sendiri. Akibatnya layar ini memajang nomor rekening yang
  // sudah tidak ada di Info Pembayaran, dan yang membacanya tidak punya
  // cara tahu mana yang sebenarnya dipakai.
  group('kartu Rekening Bank', () {
    final layar =
        File('lib/screens/finance_balance_screen.dart').readAsStringSync();

    test('dibaca dari bank_accounts, bukan dari settings', () {
      expect(layar, contains('BankAccountRepository().untukResto'));
      expect(layar, isNot(contains("settings?['bank_name']")));
      expect(layar, isNot(contains("from('settings')")));
    });

    test('menampilkan semua rekening, bukan satu saja', () {
      expect(layar, contains('for (var i = 0; i < _rekening.length; i++)'));
      expect(layar, contains('_KartuRekening(rekening: _rekening[i])'));
    });

    // Nomor rekening adalah deretan angka panjang yang dibaca digit per
    // digit; kartu yang saling menempel membuat yang membacanya
    // kehilangan barisnya di tengah.
    test('tiap rekening punya kartunya sendiri, berjarak', () {
      expect(layar, contains('if (i > 0) const SizedBox(height: 10)'));
      expect(layar, contains('class _KartuRekening'));
    });
  });
}
