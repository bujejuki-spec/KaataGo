import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_app/db/customer_display_repository.dart';
import 'package:pos_app/models/customer_order.dart';
import 'package:pos_app/models/menu_access.dart';
import 'package:pos_app/utils/akses_menu.dart';
import 'package:pos_app/widgets/hub_group_tile.dart';
import 'package:pos_app/widgets/hub_menu_tile.dart';

void main() {
  group('kelompok menu yang isinya habis ikut hilang', () {
    // Menu menyembunyikan dirinya sendiri, tapi kelompoknya tidak ikut
    // tahu. Yang tersisa adalah kartu yang mengundang orang masuk ke
    // halaman kosong — dan halaman kosong tanpa sebab terbaca sebagai
    // aplikasi yang rusak.
    Widget bungkus(Map<String, TingkatAkses> peta) => MaterialApp(
          home: AksesMenu(
            peta: peta,
            child: Scaffold(
              body: HubGroupTile(
                icon: Icons.folder,
                title: 'Keuangan',
                subtitle: 'apa saja',
                color: Colors.blue,
                tiles: () => [
                  const HubMenuTile(
                    icon: Icons.savings,
                    title: 'Setor Saldo Cash',
                    subtitle: '',
                    color: Colors.blue,
                    onTap: _kosong,
                  ),
                ],
              ),
            ),
          ),
        );

    testWidgets('satu-satunya isinya dicabut, kelompoknya ikut hilang',
        (tester) async {
      await tester.pumpWidget(bungkus(const {}));
      expect(find.text('Keuangan'), findsOneWidget);

      await tester.pumpWidget(
          bungkus(const {'Setor Saldo Cash': TingkatAkses.tidakAda}));
      expect(find.text('Keuangan'), findsNothing);
    });

    testWidgets('isinya cuma boleh dilihat, kelompoknya tetap ada',
        (tester) async {
      await tester
          .pumpWidget(bungkus(const {'Setor Saldo Cash': TingkatAkses.lihat}));
      expect(find.text('Keuangan'), findsOneWidget);
    });
  });

  group('layar pelanggan', () {
    test('rincian pesanan bolak-balik lewat peta', () {
      final t = TampilanLayar.fromMap({
        'status': 'awaiting',
        'amount': 40000,
        'payment_method': 'cash',
        'items': [
          {'nama': 'Nasi Uduk', 'qty': 2, 'total': 40000},
        ],
      });
      expect(t.items.single.nama, 'Nasi Uduk');
      expect(t.items.single.qty, 2);
      expect(t.paymentMethod, 'cash');
      expect(t.adaQr, isFalse);
      expect(t.adaGambarQr, isFalse);
    });

    test('QRIS statis dikenali lewat gambarnya, bukan lewat teks QR', () {
      // QR statis milik merchant berupa gambar, bukan teks EMVCo yang
      // bisa digambar ulang jadi kode.
      final t = TampilanLayar.fromMap({
        'status': 'awaiting',
        'payment_method': 'qris_static',
        'qr_image_url': 'https://contoh/qr.png',
      });
      expect(t.adaGambarQr, isTrue);
      expect(t.adaQr, isFalse);
    });

    test('transfer membawa rekeningnya sendiri', () {
      final t = TampilanLayar.fromMap({
        'status': 'awaiting',
        'payment_method': 'transfer',
        'bank_name': 'BCA',
        'account_number': '1234567890',
        'account_holder': 'Warung Contoh',
      });
      expect(t.adaRekening, isTrue);
      expect(t.accountNumber, '1234567890');
    });

    final sql = File('supabase/layar_pelanggan_rinci.sql').readAsStringSync();

    test('fungsi lamanya dibuang, bukan ditimpa', () {
      // `create or replace` dengan daftar parameter berbeda membuat
      // fungsi KEDUA dengan nama yang sama, dan yang lama tetap bisa
      // dipanggil.
      expect(sql,
          contains('drop function if exists set_customer_display(text, text, bigint, text, text)'));
    });

    test('pembaruan susulan tidak menghapus rincian yang sudah ada', () {
      // Layar QRIS memanggilnya untuk kedua kalinya begitu QR-nya
      // terbit, tanpa membawa isi keranjang.
      expect(sql, contains('coalesce(excluded.items, customer_displays.items)'));
    });

    test('dipadamkan berarti benar-benar kosong', () {
      // Tagihan orang sebelumnya tidak boleh tertinggal di depan
      // pelanggan berikutnya.
      expect(sql, contains("case when excluded.status = 'idle' then null"));
    });
  });

  group('stok dilepas sepuluh menit', () {
    final sql = File('supabase/stok_lepas_10_menit.sql').readAsStringSync();

    test('tenggangnya sepuluh menit di server', () {
      expect(sql, contains("interval '10 minutes'"));
      expect(sql, isNot(contains("interval '30 minutes'")));
    });

    test('stoknya dikembalikan, bukan cuma pesanannya dihanguskan', () {
      expect(sql, contains('kembalikan_stok'));
    });

    test('hitung mundur di aplikasi sama dengan tenggang di server', () {
      // Hitung mundur yang lebih panjang dari kenyataannya berarti orang
      // melihat sisa waktu pada pesanan yang sudah hangus.
      expect(CustomerOrder.paymentWindow, const Duration(minutes: 10));
    });
  });
}

void _kosong() {}
