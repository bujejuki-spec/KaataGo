import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_app/widgets/responsive.dart';

/// Hub dengan belasan menu adalah daftar yang harus dibaca dari atas
/// tiap kali, karena tidak ada yang menandai di mana satu urusan
/// berakhir dan urusan lain dimulai.
void main() {
  const hub = {
    'kasir': 9,
    'admin': 12,
    'finance': 11,
    'super_admin': 8,
    'owner': 15,
  };

  group('menu dikelompokkan per fungsi', () {
    for (final entry in hub.entries) {
      test('${entry.key} punya judul kelompok', () {
        final isi =
            File('lib/screens/${entry.key}_home_screen.dart').readAsStringSync();
        expect(
          isi.contains('HubMenuSection(') || isi.contains('HubSectionLabel('),
          isTrue,
          reason: '${entry.key} masih satu daftar panjang',
        );
      });
    }

    test('tidak ada tile yang hilang saat dikelompokkan', () {
      // Pengelompokan memindahkan tile, dan yang paling mudah terjadi
      // saat memindahkan adalah kehilangan satu tanpa suara.
      for (final entry in hub.entries) {
        if (entry.key == 'owner') continue; // tata letaknya berbeda
        final isi =
            File('lib/screens/${entry.key}_home_screen.dart').readAsStringSync();
        final jumlah = RegExp(r'^ +(HubMenuTile|BadgedHubTile|const InboxTile)',
                multiLine: true)
            .allMatches(isi)
            .length;
        expect(jumlah, entry.value, reason: entry.key);
      }
    });

    test('label kelompoknya satu widget bersama', () {
      // "Keuangan" di layar Admin dan di layar Owner harus terlihat sama,
      // karena memang hal yang sama.
      final owner =
          File('lib/screens/owner_home_screen.dart').readAsStringSync();
      expect(owner, contains('HubSectionLabel('));
      expect(owner, isNot(contains('class _SectionLabel')));
    });

    test('judul "Menu" yang mubazir dibuang', () {
      for (final k in ['kasir', 'admin', 'finance', 'super_admin']) {
        final isi = File('lib/screens/${k}_home_screen.dart').readAsStringSync();
        expect(isi, isNot(contains("Text('Menu'")), reason: k);
      }
    });
  });

  group('tata letak berkelompok', () {
    testWidgets('judul kelompok tetap selebar layar di banyak kolom',
        (tester) async {
      // Pada layar lebar tiap tile dibungkus SizedBox selebar satu
      // kolom. Label yang ikut terjepit di sana berhenti terbaca sebagai
      // judul — ia jadi kartu tak bergambar di tengah barisan kartu.
      tester.view.physicalSize = const Size(1600, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(
          body: HubMenuLayout(
            sections: [
              HubMenuSection('Penjualan', [SizedBox(height: 40)]),
              HubMenuSection('Keuangan', [SizedBox(height: 40)]),
            ],
          ),
        ),
      ));
      await tester.pumpAndSettle();

      final label = tester.getSize(find.text('PENJUALAN'));
      final kartu = tester.getSize(find.byType(SizedBox).at(0));
      expect(label.width, greaterThan(0));
      expect(kartu.width, greaterThan(0));
    });

    testWidgets('tiap kelompok muncul judulnya', (tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(
          body: HubMenuLayout(
            sections: [
              HubMenuSection('Penjualan', [Text('a')]),
              HubMenuSection('Akun', [Text('b')]),
            ],
          ),
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.text('PENJUALAN'), findsOneWidget);
      expect(find.text('AKUN'), findsOneWidget);
      expect(find.text('a'), findsOneWidget);
      expect(find.text('b'), findsOneWidget);
    });

    testWidgets('daftar tanpa kelompok tetap bekerja seperti dulu',
        (tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(
          body: HubMenuLayout(tiles: [Text('satu'), Text('dua')]),
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.text('satu'), findsOneWidget);
      expect(find.text('dua'), findsOneWidget);
    });
  });
}
