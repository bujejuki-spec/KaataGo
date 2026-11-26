import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_app/widgets/hub_group_tile.dart';
import 'package:pos_app/widgets/hub_menu_tile.dart';

/// Kelompok menu yang tersisa satu kartu membubarkan dirinya.
///
/// ── Kenapa dipasang, bukan dibaca ────────────────────────────────────
///
/// Yang menentukan bukan jumlah yang ditulis di beranda melainkan jumlah
/// yang BENAR-BENAR tampil sesudah UAM menyaring. Tes yang membaca kode
/// akan selalu melihat tiga kartu di dalam kelompok, termasuk saat dua
/// di antaranya dicabut dan yang tersisa satu pintu berisi satu menu —
/// persis keadaan yang mau dihindari.
void main() {
  HubMenuTile menu(String judul) => HubMenuTile(
        icon: Icons.circle,
        title: judul,
        subtitle: 'keterangan $judul',
        color: Colors.indigo,
        onTap: () {},
      );

  Future<void> pasang(WidgetTester tester, List<Widget> isi) =>
      tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: ListView(
            children: [
              HubGroupTile(
                icon: Icons.folder,
                title: 'Pengelolaan',
                subtitle: 'isi kelompoknya',
                color: Colors.indigo,
                tiles: () => isi,
              ),
            ],
          ),
        ),
      ));

  testWidgets('satu menu: kelompoknya hilang, menunya naik', (tester) async {
    await pasang(tester, [menu('Kelola Produk')]);

    expect(find.text('Kelola Produk'), findsOneWidget);
    expect(find.text('Pengelolaan'), findsNothing,
        reason: 'Pintu yang di baliknya cuma satu kartu menambah satu '
            'ketukan tanpa menyembunyikan apa pun.');
    // Keterangan menunya ikut naik, bukan keterangan kelompoknya.
    expect(find.text('keterangan Kelola Produk'), findsOneWidget);
    expect(find.text('isi kelompoknya'), findsNothing);
  });

  testWidgets('dua menu: kelompoknya tetap berdiri', (tester) async {
    await pasang(tester, [menu('Kelola Produk'), menu('Kategori')]);

    expect(find.text('Pengelolaan'), findsOneWidget);
    // Isinya baru terlihat sesudah pintunya diketuk.
    expect(find.text('Kelola Produk'), findsNothing);
    expect(find.text('Kategori'), findsNothing);
  });

  testWidgets('pintunya masih bisa dibuka saat berisi dua', (tester) async {
    await pasang(tester, [menu('Kelola Produk'), menu('Kategori')]);

    await tester.tap(find.text('Pengelolaan'));
    await tester.pumpAndSettle();

    expect(find.text('Kelola Produk'), findsOneWidget);
    expect(find.text('Kategori'), findsOneWidget);
  });

  testWidgets('kelompok kosong tidak meninggalkan apa pun', (tester) async {
    await pasang(tester, const []);

    expect(find.text('Pengelolaan'), findsNothing);
    expect(find.byType(HubMenuTile), findsNothing);
  });
}
