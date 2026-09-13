import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:pos_app/widgets/penanda_mengambang.dart';

/// Penanda mengambang benar-benar dipasang, bukan cuma dibaca sebagai
/// teks.
///
/// ── Kenapa berkas ini ada ────────────────────────────────────────────
///
/// Versi 3.9.0 terbit dengan Positioned yang dibungkus LayoutBuilder di
/// dalam Stack. Positioned adalah ParentDataWidget: ia menempelkan data
/// posisinya ke render object induknya, dan LayoutBuilder punya render
/// object sendiri di antaranya. Yang terjadi bukan tata letak yang
/// meleset melainkan galat — dan di build release galat itu digambar
/// sebagai kotak abu-abu 94% yang menutupi seluruh layar.
///
/// Penanda ini dipasang di atas Navigator, jadi yang tertutup bukan satu
/// layar melainkan seluruh aplikasi, untuk setiap peran.
///
/// Seluruh pengujian yang ada waktu itu membaca berkasnya sebagai teks —
/// mencocokkan `bottom: _tepi` dan `onPanUpdate:` yang memang ada di
/// sana, dan semuanya lulus. Yang tidak dilakukan satu pun: memasangnya
/// lalu melihat apakah ia menggambar.
void main() {
  Future<void> pasang(WidgetTester tester, {Widget? isi}) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        home: Stack(
          children: [
            const Scaffold(body: Center(child: Text('isi aplikasi'))),
            PenandaMengambang(
              child: isi ??
                  Material(
                    color: Colors.amber,
                    child: InkWell(
                      onTap: () {},
                      child: const Padding(
                        padding: EdgeInsets.all(10),
                        child: Text('Akhiri'),
                      ),
                    ),
                  ),
            ),
          ],
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('tergambar tanpa galat', (tester) async {
    await pasang(tester);
    expect(tester.takeException(), isNull);
    expect(find.text('isi aplikasi'), findsOneWidget);
    expect(find.text('Akhiri'), findsOneWidget);
  });

  // Inilah bentuk kegagalan yang lolos ke rilis: bukan pengecualian yang
  // terlihat di log, melainkan ErrorWidget yang diam-diam menggantikan
  // subtree-nya dan menutupi apa pun di bawahnya.
  testWidgets('tidak menyisipkan ErrorWidget ke pohonnya', (tester) async {
    await pasang(tester);
    expect(find.byType(ErrorWidget), findsNothing);
  });

  // Positioned harus jadi anak LANGSUNG Stack-nya. Kalau suatu hari ada
  // yang menyisipkan pembungkus ber-render-object di antaranya lagi,
  // pengujian ini yang menangkapnya — bukan tangkapan layar dari HP
  // orang.
  testWidgets('Positioned menempel langsung ke Stack', (tester) async {
    await pasang(tester);

    final positioned = tester.element(find.byType(Positioned).first);
    Element? induk;
    positioned.visitAncestorElements((e) {
      if (e is RenderObjectElement) {
        induk = e;
        return false;
      }
      return true;
    });
    expect(induk?.widget, isA<Stack>(),
        reason: 'Positioned harus jadi anak langsung Stack — pembungkus '
            'ber-render-object di antaranya membuat seluruh layar '
            'tertutup kotak galat di build release');
  });

  // Bawaannya di bawah, bukan di atas: yang di atas menutupi judul layar
  // dan tombol kembali.
  testWidgets('bawaannya duduk di bawah layar', (tester) async {
    await pasang(tester);
    final kotak = tester.getRect(find.text('Akhiri'));
    expect(kotak.center.dy, greaterThan(600),
        reason: 'pilnya harus di paruh bawah layar setinggi 800');
  });

  testWidgets('bisa digeser dan tetap tergambar', (tester) async {
    await pasang(tester);
    final sebelum = tester.getRect(find.text('Akhiri')).center;

    await tester.drag(find.text('Akhiri'), const Offset(-40, -300));
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.byType(ErrorWidget), findsNothing);

    final sesudah = tester.getRect(find.text('Akhiri')).center;
    expect(sesudah.dy, lessThan(sebelum.dy),
        reason: 'digeser ke atas seharusnya benar-benar naik');
  });

  // Pil yang bisa digeser keluar layar adalah pil yang tidak bisa
  // dikembalikan.
  testWidgets('tidak bisa digeser keluar layar', (tester) async {
    await pasang(tester);

    await tester.drag(find.text('Akhiri'), const Offset(-4000, -4000));
    await tester.pump();

    final kotak = tester.getRect(find.text('Akhiri'));
    expect(kotak.left, greaterThanOrEqualTo(0));
    expect(kotak.top, greaterThanOrEqualTo(0));
    expect(tester.takeException(), isNull);
  });
}
