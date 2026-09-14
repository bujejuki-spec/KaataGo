import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:pos_app/models/menu_access.dart';
import 'package:pos_app/utils/akses_menu.dart';
import 'package:pos_app/widgets/hub_menu_tile.dart';
import 'package:pos_app/widgets/tampak_menu.dart';

/// Jarak antarkartu disisipkan SESUDAH menu yang dicabut UAM dibuang.
///
/// ── Kenapa berkas ini ada ────────────────────────────────────────────
///
/// Beranda Owner menuliskan jaraknya sendiri di antara kartu. Selama
/// semua menunya muncul, hasilnya rapi. Begitu paket Basic mencabut
/// beberapa menu, kartunya hilang tapi dua `SizedBox` pengapitnya tetap
/// tinggal — dan yang terlihat lubang selebar dua kali jarak biasa.
///
/// Pengujian jarak yang sudah ada membaca berkasnya sebagai teks dan
/// mencari dua `SizedBox` berurutan. Yang ini tidak ketemu begitu:
/// sumbernya benar, yang salah hasilnya setelah disaring. Jadi di sini
/// daftarnya benar-benar dibangun lalu jaraknya dihitung.
void main() {
  HubMenuTile kartu(String judul) => HubMenuTile(
        icon: Icons.circle,
        title: judul,
        subtitle: judul,
        color: Colors.blue,
        onTap: () {},
      );

  /// Membangun daftar dengan [dicabut] disembunyikan UAM.
  Future<List<Widget>> bangun(
    WidgetTester tester,
    List<String> judul,
    Set<String> dicabut,
  ) async {
    late List<Widget> hasil;
    await tester.pumpWidget(
      MaterialApp(
        home: AksesMenu(
          peta: {for (final d in dicabut) d: TingkatAkses.tidakAda},
          child: Builder(
            builder: (context) {
              hasil = tileBerjarak(context, [for (final j in judul) kartu(j)]);
              return Column(children: hasil);
            },
          ),
        ),
      ),
    );
    return hasil;
  }

  testWidgets('tanpa yang dicabut, jaraknya satu di antara tiap kartu',
      (tester) async {
    final hasil = await bangun(tester, ['A', 'B', 'C'], {});
    expect(hasil.whereType<HubMenuTile>().length, 3);
    expect(hasil.whereType<SizedBox>().length, 2);
  });

  // Inilah bentuk yang terlihat di layar Owner paket Basic: lubang
  // selebar dua kali jarak biasa, tepat di tempat menu yang dicabut.
  testWidgets('kartu yang dicabut tidak meninggalkan jarak', (tester) async {
    final hasil = await bangun(tester, ['A', 'B', 'C'], {'B'});
    expect(hasil.whereType<HubMenuTile>().length, 2,
        reason: 'kartu yang dicabut harus benar-benar hilang');
    expect(hasil.whereType<SizedBox>().length, 1,
        reason: 'dua kartu tersisa cuma butuh satu jarak — dua berarti '
            'SizedBox milik kartu yang hilang ikut tertinggal');
  });

  testWidgets('kartu pertama dan terakhir yang dicabut juga bersih',
      (tester) async {
    expect((await bangun(tester, ['A', 'B', 'C'], {'A'}))
        .whereType<SizedBox>()
        .length, 1);
    expect((await bangun(tester, ['A', 'B', 'C'], {'C'}))
        .whereType<SizedBox>()
        .length, 1);
  });

  testWidgets('satu kartu tersisa tidak punya jarak sama sekali',
      (tester) async {
    final hasil = await bangun(tester, ['A', 'B', 'C'], {'A', 'C'});
    expect(hasil.whereType<HubMenuTile>().length, 1);
    expect(hasil.whereType<SizedBox>(), isEmpty);
  });

  // Beranda Owner menyusun daftarnya sendiri, bukan lewat HubMenuLayout.
  // Kalau suatu hari ada yang menuliskan jaraknya lagi di sana, lubang
  // itu kembali.
  test('beranda Owner tidak menuliskan jaraknya sendiri', () {
    final s = File('lib/screens/owner_home_screen.dart').readAsStringSync();
    expect(s, contains('tileBerjarak(context, ['));
    expect(s, isNot(contains('const SizedBox(height: 12),')),
        reason: 'jaraknya harus disisipkan tileBerjarak, sesudah menu yang '
            'dicabut UAM dibuang');
  });
}
