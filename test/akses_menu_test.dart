import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_app/models/menu_access.dart';
import 'package:pos_app/utils/akses_menu.dart';
import 'package:pos_app/utils/katalog_menu.dart';
import 'package:pos_app/widgets/dialog_actions.dart';
import 'package:pos_app/widgets/hub_menu_tile.dart';
import 'package:pos_app/widgets/responsive.dart';

/// Parameter akses menu (UAM).
///
/// Yang dijaga di sini adalah arah gagalnya. Parameter ini tidak memberi
/// hak — RLS tetap lantai keamanannya — jadi satu-satunya kerusakan yang
/// mungkin ia timbulkan adalah mengunci orang dari pekerjaannya. Karena
/// itu setiap keadaan yang tidak jelas harus jatuh ke "boleh": peta
/// kosong, nilai asing, menu yang tidak terdaftar, layar yang lupa
/// dibungkus.
void main() {
  group('yang tidak diatur berarti penuh', () {
    test('peta kosong tidak membatasi apa pun', () {
      const akses = AksesMenu(peta: {}, child: SizedBox());
      expect(akses.bolehLihat('Kelola Produk'), isTrue);
      expect(akses.bolehUbah('Kelola Produk'), isTrue);
    });

    test('nilai yang tidak dikenali dibaca sebagai penuh', () {
      expect(TingkatAkses.dari('tidak-ada-nilai-ini'), TingkatAkses.ubah);
      expect(TingkatAkses.dari(null), TingkatAkses.ubah);
    });

    test('menu di luar peta tetap terbuka', () {
      const akses = AksesMenu(
        peta: {'Kelola Produk': TingkatAkses.tidakAda},
        child: SizedBox(),
      );
      expect(akses.bolehLihat('Diskon'), isTrue);
    });
  });

  group('tingkatannya', () {
    test('tidak ada berarti tidak terlihat', () {
      expect(TingkatAkses.tidakAda.bolehLihat, isFalse);
      expect(TingkatAkses.tidakAda.bolehUbah, isFalse);
    });

    test('lihat berarti terlihat tapi tidak bisa diubah', () {
      expect(TingkatAkses.lihat.bolehLihat, isTrue);
      expect(TingkatAkses.lihat.bolehUbah, isFalse);
    });
  });

  testWidgets('menu yang dicabut hilang dari beranda', (tester) async {
    Widget bungkus(Map<String, TingkatAkses> peta) => MaterialApp(
          home: AksesMenu(
            peta: peta,
            child: Scaffold(
              body: HubMenuTile(
                icon: Icons.inventory_2_outlined,
                title: 'Kelola Produk',
                subtitle: 'apa saja',
                color: Colors.blue,
                onTap: () {},
              ),
            ),
          ),
        );

    await tester.pumpWidget(bungkus(const {}));
    expect(find.text('Kelola Produk'), findsOneWidget);

    await tester
        .pumpWidget(bungkus(const {'Kelola Produk': TingkatAkses.tidakAda}));
    expect(find.text('Kelola Produk'), findsNothing);

    // 'Lihat' tetap muncul — kalau tidak, ia tidak berbeda dari
    // 'Tidak Ada'.
    await tester
        .pumpWidget(bungkus(const {'Kelola Produk': TingkatAkses.lihat}));
    expect(find.text('Kelola Produk'), findsOneWidget);
  });

  testWidgets('tombol simpan mati di menu yang cuma boleh dilihat',
      (tester) async {
    Widget bungkus(TingkatAkses tingkat) => MaterialApp(
          home: AksesMenu(
            peta: {'Kelola Produk': tingkat},
            child: Builder(
              builder: (context) => berdasarkanAkses(
                context,
                'Kelola Produk',
                Scaffold(
                  body: DialogActions(
                    confirmLabel: 'Simpan',
                    onConfirm: () {},
                  ),
                ),
              ),
            ),
          ),
        );

    await tester.pumpWidget(bungkus(TingkatAkses.ubah));
    expect(
        tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNotNull);

    await tester.pumpWidget(bungkus(TingkatAkses.lihat));
    await tester.pump();
    expect(
        tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull);
  });

  testWidgets('layar yang tidak dibungkus tidak pernah terkunci',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: DialogActions(confirmLabel: 'Simpan', onConfirm: () {}),
      ),
    ));
    expect(
        tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNotNull);
  });

  testWidgets('kartu yang dicabut tidak meninggalkan jarak kosong',
      (tester) async {
    // Lebar ponsel, supaya yang diuji susunan satu kolom — di sanalah
    // pemisah 12 piksel disisipkan satu per satu.
    tester.view.physicalSize = const Size(400, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    // Kartu menyembunyikan dirinya sendiri, tapi jarak di antaranya
    // disisipkan tata letaknya — dan jarak milik kartu yang menghilang
    // tetap berdiri, meninggalkan lubang selebar dua jarak. Lubang itu
    // terbaca sebagai menu yang gagal dimuat.
    Widget bungkus(Map<String, TingkatAkses> peta) => MaterialApp(
          home: AksesMenu(
            peta: peta,
            child: const Scaffold(
              body: HubMenuLayout(
                tiles: [
                  HubMenuTile(
                    icon: Icons.point_of_sale,
                    title: 'Shift Kasir',
                    subtitle: '',
                    color: Colors.orange,
                    onTap: _kosong,
                  ),
                  HubMenuTile(
                    icon: Icons.local_offer_outlined,
                    title: 'Diskon',
                    subtitle: '',
                    color: Colors.green,
                    onTap: _kosong,
                  ),
                  HubMenuTile(
                    icon: Icons.inbox_outlined,
                    title: 'Kotak Masuk',
                    subtitle: '',
                    color: Colors.blue,
                    onTap: _kosong,
                  ),
                ],
              ),
            ),
          ),
        );

    await tester.pumpWidget(bungkus(const {}));
    await tester.pumpAndSettle();
    final utuh = tester.getTopLeft(find.text('Kotak Masuk')).dy -
        tester.getTopLeft(find.text('Shift Kasir')).dy;

    await tester.pumpWidget(bungkus(const {'Diskon': TingkatAkses.tidakAda}));
    await tester.pumpAndSettle();
    expect(find.text('Diskon'), findsNothing);

    final sesudah = tester.getTopLeft(find.text('Kotak Masuk')).dy -
        tester.getTopLeft(find.text('Shift Kasir')).dy;

    // Jaraknya menyusut sebesar satu kartu penuh — bukan cuma sebesar
    // kartunya sambil menyisakan pemisahnya.
    final tinggiKartu = tester.getSize(find.byType(Card).first).height;
    expect(sesudah, lessThan(utuh));
    expect(utuh - sesudah, closeTo(tinggiKartu + 12, 1));
  });

  group('katalognya', () {
    test('Super Admin tidak bisa diatur', () {
      // Peran yang bisa mengunci dirinya sendiri dari layar
      // pengaturannya adalah pintu yang kuncinya tertinggal di dalam.
      expect(katalogMenu.containsKey('super_admin'), isFalse);
    });

    test('Tampilan dan Keluar tidak bisa dicabut', () {
      for (final menu in katalogMenu.values) {
        expect(menu, isNot(contains('Tampilan')));
        expect(menu, isNot(contains('Keluar')));
      }
    });

    test('judul di katalog memang ada sebagai menu di aplikasi', () {
      // Kuncinya adalah judul menunya sendiri. Judul yang salah tulis
      // menghasilkan baris parameter yang tidak pernah cocok dengan apa
      // pun — pembatasan yang tersimpan rapi dan tidak berpengaruh.
      final sumber = StringBuffer();
      for (final f in Directory('lib/screens').listSync()) {
        if (f is File && f.path.endsWith('.dart')) {
          sumber.write(f.readAsStringSync());
        }
      }
      final isi = sumber.toString();
      for (final e in katalogMenu.entries) {
        for (final menu in e.value) {
          expect(isi.contains("'$menu'"), isTrue,
              reason: '${e.key}: "$menu" tidak ada sebagai judul menu');
        }
      }
    });
  });

  group('yang ditegakkan server tetap server', () {
    final sql = File('supabase/uam_menu.sql').readAsStringSync();

    test('hanya Super Admin yang boleh menulisnya', () {
      expect(sql, contains('"menu_access: super admin write"'));
      expect(sql,
          contains('for all using (is_super_admin()) with check (is_super_admin())'));
    });

    test('pegawai merchant boleh membacanya', () {
      // Perangkat kasir yang tidak bisa membaca parameternya sendiri
      // akan menampilkan seluruh menu — pembatasannya jadi tidak ada.
      expect(sql, contains('"menu_access: staff read"'));
    });
  });
}

void _kosong() {}
