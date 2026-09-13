import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:pos_app/models/merchant_report.dart';

/// Laporan Penjualan yang bisa disetel: apa yang digambar, sekasar apa,
/// dan dari sudut pandang mana omzetnya dibagi.
void main() {
  final layar =
      File('lib/screens/merchant_report_screen.dart').readAsStringSync();

  group('yang bisa dipilih', () {
    // Omzet menjawab berapa uangnya, jumlah pesanan menjawab berapa
    // orang yang datang, porsi menjawab berapa yang keluar dari dapur.
    // Hari ramai yang belanjanya kecil hanya terlihat kalau dua di
    // antaranya bisa dibandingkan.
    test('tiga metrik untuk garis trennya', () {
      expect(layar, contains('enum _Metrik'));
      for (final m in ['omzet', 'pesanan', 'porsi']) {
        expect(layar, contains('$m('));
      }
    });

    // Rentang setahun yang digambar harian menjadi 365 batang selebar
    // rambut di layar HP.
    test('harian, mingguan, bulanan', () {
      expect(layar, contains("('day', 'Harian')"));
      expect(layar, contains("('week', 'Mingguan')"));
      expect(layar, contains("('month', 'Bulanan')"));
    });

    test('empat sudut pandang pembagian omzet', () {
      expect(layar, contains('enum _Dimensi'));
      for (final kode in [
        'payment_method',
        'order_type',
        'source',
        'category',
      ]) {
        expect(layar, contains("'$kode'"));
      }
    });

    // "Minggu ini bagaimana" seharusnya tidak menuntut memilih dua
    // tanggal di dalam kalender.
    test('rentang yang sering dipakai ada sebagai pintasan', () {
      for (final nama in ['7 hari', '30 hari', 'Bulan ini', 'Bulan lalu']) {
        expect(layar, contains("'$nama'"));
      }
      // Pemilih rentang penuhnya tetap ada.
      expect(layar, contains('showDateRangePicker('));
    });
  });

  // Seluruh layar berkedip kosong hanya karena orang menekan "Mingguan"
  // adalah harga yang tidak perlu dibayar: empat panggilan lainnya tidak
  // berubah oleh pilihan itu.
  test('mengganti satuan atau dimensi tidak memuat ulang seluruh layar', () {
    for (final fungsi in ['_gantiSatuan', '_gantiDimensi']) {
      final i = layar.indexOf('Future<void> $fungsi');
      expect(i, greaterThan(-1), reason: '$fungsi tidak ada');
      final blok = layar.substring(i, layar.indexOf('\n  }', i));
      expect(blok, isNot(contains('_muat()')));
    }
  });

  // Istilah basis data yang bocor ke layarnya membuat laporan terbaca
  // seperti hasil ekspor mentah.
  test('nilai mentah basis data ditulis untuk dibaca orang', () {
    expect(layar, contains("'qris_static' => 'QRIS Statis'"));
    expect(layar, contains("'dine_in' => 'Makan di Tempat'"));
    expect(layar, contains("'take_away' => 'Bawa Pulang'"));
  });

  group('modelnya', () {
    test('titik deret membaca kolom servernya', () {
      final t = TitikPenjualan.fromMap(const {
        'periode': '2026-09-13',
        'orders_count': 4,
        'omzet': 120000,
        'qty': 9,
      });
      expect(t.periode, DateTime(2026, 9, 13));
      expect(t.jumlahPesanan, 4);
      expect(t.omzet, 120000);
      expect(t.porsi, 9);
    });

    // Pembagian per kategori menghitung baris menu, bukan pesanan —
    // jadi kolomnya `qty`, bukan `orders_count`.
    test('potongan menerima dua bentuk kolom hitungan', () {
      expect(
        PotongPenjualan.fromMap(const {'kunci': 'cash', 'orders_count': 7})
            .jumlahPesanan,
        7,
      );
      expect(
        PotongPenjualan.fromMap(const {'kunci': 'Minuman', 'qty': 33})
            .jumlahPesanan,
        33,
      );
    });

    test('kunci kosong tidak jadi baris tanpa nama', () {
      expect(PotongPenjualan.fromMap(const {}).kunci, 'lainnya');
    });
  });
}
