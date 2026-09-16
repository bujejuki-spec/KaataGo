import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_app/widgets/hub_menu_tile.dart';

/// Header beranda harus tetap padat.
///
/// ── Kenapa tingginya diukur, bukan dibaca ────────────────────────────
///
/// Header ini pernah menumpuk enam baris: logo, nama, email, tiga tombol
/// tema, lencana paket, lalu pemilih merchant — masing-masing satu baris
/// sendiri. Di HP 6 inci, menu kerja pertama baru mulai di separuh bawah
/// layar.
///
/// Tes yang membaca kodenya tidak akan pernah menangkap itu kembali:
/// susunannya bisa terlihat rapi di kode dan tetap tinggi di layar. Jadi
/// yang diperiksa di sini tingginya sungguhan, dari widget yang dipasang.
///
/// Lencana paket dan pemilih merchant sengaja tidak ikut — keduanya
/// menuntut Supabase. Yang diukur susunan dasarnya, dan di situlah
/// penumpukannya dulu terjadi.
void main() {
  /// Sebelum dirapikan, susunan dasarnya saja sekitar 190 piksel:
  /// jarak atas 44, logo 64, jarak 16, nama 20, jarak 8, email 15,
  /// jarak bawah 24. Batas ini diberi kelonggaran, tapi tetap jauh di
  /// bawah angka itu — supaya kembali menumpuk berarti tes ini merah.
  const batas = 130.0;

  Future<double> tinggiHeader(WidgetTester tester, {String? subtitle}) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Column(
          children: [
            HubHeader(
              logo: const SizedBox(width: 64, height: 64),
              title: 'Kaata Jajan',
              subtitle: subtitle,
              colorA: Colors.indigo,
              colorB: Colors.indigo,
            ),
          ],
        ),
      ),
    ));
    return tester.getSize(find.byType(HubHeader)).height;
  }

  testWidgets('tingginya tetap di bawah batas', (tester) async {
    final tinggi = await tinggiHeader(tester,
        subtitle: 'Owner • kaatatemanjajan@gmail.com');
    expect(tinggi, lessThan(batas),
        reason: 'Header $tinggi px — menumpuk lagi, dan menu kerja '
            'pertama ikut turun ke separuh bawah layar.');
  });

  testWidgets('logo, nama, dan email berbagi satu baris', (tester) async {
    // Kalau nama berdiri di bawah logo alih-alih di sebelahnya,
    // menambahkan subtitle akan menambah tinggi header sebesar satu
    // baris penuh. Berbagi baris berarti tambahannya nol.
    final tanpa = await tinggiHeader(tester);
    final dengan = await tinggiHeader(tester,
        subtitle: 'Owner • kaatatemanjajan@gmail.com');
    expect(dengan, tanpa,
        reason: 'Subtitle menambah tinggi header, berarti teksnya tidak '
            'berbagi baris dengan logonya.');
  });

  testWidgets('nama panjang dipotong, bukan membuat header tumbuh',
      (tester) async {
    // Dibungkus Column, sama seperti pemakaian sungguhannya di beranda.
    //
    // HubHeader selebar layar tanpa tinggi tetap: ditaruh langsung
    // sebagai `body:`, ia memenuhi seluruh Scaffold dan yang terukur 600
    // px — tinggi layarnya, bukan tinggi headernya.
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: Column(
          children: [
            HubHeader(
              logo: SizedBox(width: 64, height: 64),
              title: 'Warung Nasi Uduk Ibu Haji Sumiati Cabang Depok Dua',
              subtitle: 'Owner • namayangsangatpanjangsekali@gmail.com',
              colorA: Colors.indigo,
              colorB: Colors.indigo,
            ),
          ],
        ),
      ),
    ));
    expect(tester.takeException(), isNull);
    expect(tester.getSize(find.byType(HubHeader)).height, lessThan(batas));
  });
}
