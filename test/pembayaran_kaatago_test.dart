import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pos_app/models/voucher_payout.dart';

/// Settlement tahap 3: apa yang dibayarkan KaataGo ke merchant.
///
/// Uangnya sudah lama berjalan sendiri lewat antrean pencairan. Yang
/// belum ada adalah halaman untuk memeriksanya — dan tidak ada yang
/// membaca jurnal untuk menanyakan haknya.
void main() {
  final layar =
      File('lib/screens/pembayaran_kaatago_screen.dart').readAsStringSync();
  final repo =
      File('lib/db/voucher_payout_repository.dart').readAsStringSync();

  VoucherPayout buat({String status = 'pending'}) => VoucherPayout(
        id: 'p1',
        restoId: 'r1',
        claimId: 'c1',
        amount: 50000,
        status: status,
        createdAt: DateTime(2026, 9, 13),
      );

  group('statusnya', () {
    // Dari sisi merchant, antre dan gagal sama saja: uangnya belum ada.
    test('yang belum terkirim terbaca belum sampai', () {
      expect(buat().belumSampai, isTrue);
      expect(buat(status: 'failed').belumSampai, isTrue);
      expect(buat(status: 'sent').belumSampai, isFalse);
    });

    test('labelnya menyebut keadaannya, bukan kode', () {
      expect(buat().labelStatus, 'Menunggu dibayar');
      expect(buat(status: 'failed').labelStatus, 'Gagal, akan diulang');
      expect(buat(status: 'sent').labelStatus, 'Sudah dibayar');
    });
  });

  group('layarnya', () {
    test('menjawab tiga pertanyaannya sekaligus', () {
      expect(layar, contains('Voucher ditebus di periode ini'));
      expect(layar, contains("judul: 'Sudah dibayar'"));
      expect(layar, contains("judul: 'Masih menggantung'"));
    });

    // Merchant yang menanyakannya besok pagi berhak tahu apa yang
    // sedang ditunggu.
    test('yang gagal menyebutkan sebabnya', () {
      expect(layar, contains('baris.lastError'));
      expect(layar, contains('Akan dicoba lagi.'));
    });

    // Itu yang dipakai mencocokkan baris ini dengan mutasi di akun
    // pembayaran, tanpa menebak-nebak.
    test('nomor transfernya ikut ditulis', () {
      expect(layar, contains('No. transfer'));
    });

    test('periodenya memakai pemilih bersama, maksimal sebulan', () {
      expect(layar, contains('pilihPeriodeLaporan'));
      expect(layar, isNot(contains('showDateRangePicker')));
    });
  });

  group('datanya', () {
    // Merchant yang sudah lama berjalan bisa punya ratusan baris, dan
    // yang dicari hampir selalu satu bulan terakhir.
    test('disaring periodenya di server', () {
      expect(repo, contains("gte('created_at'"));
      expect(repo, contains("lte('created_at'"));
    });

    // RLS-nya sudah membuka baris milik restonya sendiri sejak
    // voucher_payouts.sql; layar ini tidak menambah hak apa pun.
    test('tidak ada jalur tulis dari aplikasi', () {
      expect(repo, isNot(contains('insert')));
      expect(repo, isNot(contains('update')));
    });
  });

  test('menunya ada untuk Finance dan Owner', () {
    for (final f in [
      'lib/screens/finance_home_screen.dart',
      'lib/screens/owner_home_screen.dart',
    ]) {
      expect(File(f).readAsStringSync(),
          contains("title: 'Pembayaran dari KaataGo'"));
    }
    final web = File('lib/screens/web_menu.dart').readAsStringSync();
    expect("judul: 'Pembayaran dari KaataGo'".allMatches(web).length, 2);
  });
}
