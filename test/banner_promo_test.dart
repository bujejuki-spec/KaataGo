import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Banner promo tidak boleh mengambil alih halaman menu.
///
/// Di tablet, 16:9 selebar layar berarti banner ratusan piksel
/// tingginya — menunya sendiri terdorong keluar layar sebelum sempat
/// terlihat.
void main() {
  const maxLebar = 560.0;

  Widget kotak(double rasio) => MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: maxLebar),
                  child: AspectRatio(
                    aspectRatio: rasio,
                    child: Container(key: const Key('banner'), color: Colors.blue),
                  ),
                ),
              ),
            ],
          ),
        ),
      );

  Future<Size> ukur(WidgetTester tester, Size layar, double rasio) async {
    tester.view.physicalSize = layar;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(kotak(rasio));
    return tester.getSize(find.byKey(const Key('banner')));
  }

  testWidgets('di tablet, tingginya berhenti jauh di bawah setengah layar',
      (tester) async {
    final s = await ukur(tester, const Size(1280, 800), 16 / 9);
    expect(s.width, maxLebar);
    expect(s.height, lessThan(800 * 0.45),
        reason: 'banner memakan terlalu banyak tinggi layar');
  });

  testWidgets('di HP, batas lebarnya tidak berpengaruh', (tester) async {
    final s = await ukur(tester, const Size(400, 800), 16 / 9);
    expect(s.width, 400, reason: 'di HP banner tetap selebar layar');
  });

  testWidgets('banner jangkung tetap tidak menghabiskan layar',
      (tester) async {
    // Rasio terkecil yang diizinkan sesudah dijepit.
    final s = await ukur(tester, const Size(400, 800), 1.6);
    expect(s.height, lessThan(800 * 0.45));
  });

  group('kategori menu', () {
    final daftar =
        File('lib/widgets/product_category_list.dart').readAsStringSync();

    test('terbuka sejak awal', () {
      // Menu yang bersembunyi di balik judul kategori adalah menu yang
      // tidak ditemukan — dan halaman berisi tiga baris judul terbaca
      // seperti resto yang belum mengisi menunya.
      expect(daftar, contains('initiallyExpanded: true,'));
      expect(daftar, isNot(contains('initiallyExpanded: false,')));
    });

    test('masih bisa dilipat', () {
      // Yang sudah tahu isinya boleh merapikan layarnya sendiri.
      expect(daftar, contains('ExpansionTile('));
    });

    test('berlaku untuk kasir maupun pelanggan', () {
      for (final f in [
        'lib/screens/pos_home_screen.dart',
        'lib/screens/customer_home_screen.dart',
      ]) {
        expect(File(f).readAsStringSync(), contains('ProductCategoryList('),
            reason: f);
      }
    });

    test('admin dan owner memakai layar input pesanan yang sama', () {
      // Bukan salinan layar kasir. Kalau salinan, tiap perbaikan tata
      // letak harus diingat tiga kali dan yang ketiga selalu
      // ketinggalan.
      for (final f in [
        'lib/screens/admin_home_screen.dart',
        'lib/screens/owner_home_screen.dart',
        'lib/screens/kasir_home_screen.dart',
      ]) {
        expect(File(f).readAsStringSync(), contains('PosHomeScreen()'),
            reason: f);
      }
    });
  });

  group('sumbernya', () {
    final berkas =
        File('lib/widgets/promo_banner_carousel.dart').readAsStringSync();

    test('rasionya dibaca dari gambarnya, bukan dipatok', () {
      expect(berkas, contains('decodeImageFromList'));
      expect(berkas, contains('aspectRatio: _rasio ?? 16 / 9,'));
    });

    test('memakai bentuk paling jangkung di antara bannernya', () {
      // Kotak yang lebih pendek dari salah satu gambarnya menyisakan
      // pita untuk gambar itu.
      expect(berkas, contains('if (paling == null || r < paling) paling = r;'));
    });

    test('dijepit supaya banner salah ukuran tidak mengambil alih', () {
      expect(berkas, contains('.clamp(1.6, 3.2)'));
    });

    test('lebarnya dibatasi dan ditengahkan', () {
      expect(berkas, contains('maxWidth: 560'));
      expect(berkas, contains('Center('));
    });

    test('gambarnya tetap utuh, tidak dipotong', () {
      // Yang terpotong biasanya justru nominal diskon atau tanggal
      // berlakunya, yang ditaruh perancangnya di tepi gambar.
      expect(berkas, contains('fit: BoxFit.contain,'));
    });

    test('satu banner rusak tidak menghentikan pembacaan yang lain', () {
      expect(berkas, contains('} catch (_) {'));
    });
  });
}
