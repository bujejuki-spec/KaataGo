import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:pos_app/widgets/grafik_laporan.dart';

/// Grafik Laporan Penjualan.
///
/// Diuji dengan benar-benar dipasang, bukan dibaca sebagai teks: grafik
/// yang meleset ukurannya tidak gagal diam-diam — ia melempar saat
/// digambar, dan yang melihatnya pertama kali adalah pemakainya.
void main() {
  Future<void> pasang(WidgetTester tester, Widget anak) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Padding(
          padding: const EdgeInsets.all(16),
          child: SizedBox(height: 190, child: anak),
        ),
      ),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('garis tren tergambar tanpa galat', (tester) async {
    await pasang(
      tester,
      GrafikTren(
        nilai: const [10000, 25000, 0, 47000, 31000],
        label: const ['1/9', '2/9', '3/9', '4/9', '5/9'],
        format: (v) => 'Rp ${v.round()}',
      ),
    );
    expect(tester.takeException(), isNull);
  });

  // Rentang sehari, atau merchant yang belum berjualan sama sekali.
  // Deret rata nol pernah membuat pembagi jadi nol di grafik buatan
  // sendiri — yang terlihat bukan grafik kosong melainkan layar merah.
  testWidgets('deret yang seluruhnya nol tidak meledak', (tester) async {
    await pasang(
      tester,
      GrafikTren(
        nilai: const [0, 0, 0],
        label: const ['1/9', '2/9', '3/9'],
        format: (v) => '${v.round()}',
      ),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('batang per jam tergambar 24 jam penuh', (tester) async {
    await pasang(
      tester,
      GrafikJam(
        perJam: List<double>.generate(24, (i) => i == 12 ? 9 : 0),
        tooltip: (jam, nilai) => '$jam: $nilai',
      ),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('lingkaran pembagian tergambar', (tester) async {
    await pasang(
      tester,
      const GrafikPotong(
        nilai: [60000, 30000, 10000],
        tengahAtas: 'Total',
        tengahBawah: 'Rp 100.000',
      ),
    );
    expect(tester.takeException(), isNull);
  });

  // Warna yang berpindah tiap kali layarnya dibuka membuat orang yang
  // membandingkan dua tangkapan layar menyimpulkan yang salah.
  test('warna potongan tetap dan berputar, bukan diacak', () {
    expect(warnaPotong(0), warnaPotong(0));
    expect(warnaPotong(0), isNot(warnaPotong(1)));
    expect(warnaPotong(8), warnaPotong(0));
  });

  group('yang dihitung server', () {
    final sql = File('supabase/laporan_grafik.sql').readAsStringSync();

    // Hari tanpa penjualan tidak punya baris di orders. Grafik yang cuma
    // menggambar hari yang ada barisnya menyambung Senin ke Rabu dengan
    // garis mulus, dan Selasa yang tutup total terbaca sebagai hari
    // biasa.
    test('lubang harinya diisi nol, bukan dilompati', () {
      expect(sql, contains('generate_series'));
      expect(sql, contains('left join isi i on i.periode = k.periode'));
    });

    // Pesanan batal pernah ada di layar kasir tapi tidak pernah jadi
    // uang.
    test('hanya pesanan lunas yang dihitung', () {
      final fungsi = sql.split('create or replace function').skip(1);
      expect(fungsi, isNotEmpty);
      for (final f in fungsi) {
        expect(f, contains("payment_status = 'paid'"));
      }
    });

    // Id merchant yang ditukar di aplikasi tidak boleh membuka angka
    // merchant lain.
    test('tiap fungsi memeriksa penanyanya bekerja di resto itu', () {
      for (final f in sql.split('create or replace function').skip(1)) {
        expect(f, contains('is_resto_employee(p_resto_id'));
      }
    });

    // Jam ramai yang bergeser tujuh jam adalah jadwal shift yang salah.
    test('waktunya WIB, bukan UTC', () {
      expect(sql, contains("at time zone 'Asia/Jakarta'"));
      expect(sql, isNot(contains("at time zone 'UTC'")));
    });
  });
}
