import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pos_app/utils/periode_laporan.dart';

/// Periode Jurnal GL dan Laporan Transaksi.
void main() {
  group('batas sebulannya', () {
    // Orang membaca "sebulan" sebagai tanggal yang sama di bulan
    // berikutnya, dan Februari membuat itu berbeda tiga hari dari
    // "30 hari".
    test('14 Agustus paling jauh sampai 14 September', () {
      expect(batasAkhirPeriode(DateTime(2026, 8, 14)), DateTime(2026, 9, 14));
    });

    test('Januari ke Februari ikut tanggalnya, bukan 30 hari mati', () {
      expect(batasAkhirPeriode(DateTime(2026, 1, 31)), DateTime(2026, 3, 3));
      expect(batasAkhirPeriode(DateTime(2026, 2, 14)), DateTime(2026, 3, 14));
    });

    test('akhir tahun menyeberang dengan benar', () {
      expect(batasAkhirPeriode(DateTime(2026, 12, 20)), DateTime(2027, 1, 20));
    });
  });

  group('dipakai kedua layarnya', () {
    // Dua pemeriksaan terpisah akan berpisah, dan yang terlihat adalah
    // dua layar dengan aturan periode berbeda untuk alasan yang sama.
    test('Jurnal GL dan Laporan Transaksi memakai pemilih yang sama', () {
      for (final f in [
        'lib/screens/finance_journal_screen.dart',
        'lib/screens/finance_report_screen.dart',
      ]) {
        final isi = File(f).readAsStringSync();
        expect(isi, contains('pilihPeriodeLaporan'),
            reason: '$f harus memakai pemilih periode bersama');
        expect(isi, isNot(contains('showDateRangePicker')),
            reason: '$f tidak boleh memanggil pemilih tanggal sendiri');
      }
    });
  });

  group('jurnalnya disaring di server', () {
    final repo =
        File('lib/db/gl_journal_repository.dart').readAsStringSync();

    // Menarik seluruh jurnal lalu membuang sebagian besarnya di
    // perangkat berarti menunggu lama untuk data yang langsung dibuang.
    test('periodenya jadi syarat kueri, bukan saringan di perangkat', () {
      expect(repo, contains("gte('entry_date'"));
      expect(repo, contains("lte('entry_date'"));
    });

    test('layarnya meminta periode yang sedang dilihat', () {
      final layar =
          File('lib/screens/finance_journal_screen.dart').readAsStringSync();
      expect(layar, contains('mulai: _mulai, akhir: _akhir'));
      // Yang dicetak mengikuti yang dilihat: PDF-nya menyebut periodenya
      // sendiri, dan isinya datang dari daftar yang sama.
      expect(layar, contains("'Periode: "));
    });
  });

  group('penanda tunggakan di Billing Merchant', () {
    final layar =
        File('lib/screens/super_admin_billing_screen.dart').readAsStringSync();

    test('yang belum dibayar ditandai merah', () {
      expect(layar, contains('_Penanda(jumlah: belum, warna: Colors.red)'));
    });

    test('yang menunggu diperiksa tetap oranye', () {
      expect(layar, contains('_Penanda(jumlah: menunggu, warna: Colors.orange)'));
    });
  });
}
