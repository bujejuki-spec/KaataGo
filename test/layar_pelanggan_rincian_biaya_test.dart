import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:pos_app/db/customer_display_repository.dart';

/// Layar pelanggan menyebut dari mana totalnya berasal, dan berhenti
/// menawarkan QR yang sudah dibayar.
void main() {
  final layar =
      File('lib/screens/customer_display_screen.dart').readAsStringSync();
  final checkout = File('lib/screens/checkout_screen.dart').readAsStringSync();
  final sql =
      File('supabase/layar_pelanggan_rincian_biaya.sql').readAsStringSync();

  group('rinciannya', () {
    // PPN sudah menempel di harga tiap menu. Menyebutnya lagi sebagai
    // baris tersendiri berarti menjumlahkannya dua kali di mata orang
    // yang membacanya — jadi ia jadi catatan, bukan baris.
    test('PPN tidak jadi baris tambahan', () {
      const r = RincianBiaya(subtotal: 111000, ppn: 11000, ppnPercent: 11);
      expect(r.adaBaris, isFalse);
      expect(r.kosong, isFalse);
    });

    test('service dan diskon jadi baris', () {
      const service = RincianBiaya(subtotal: 111000, service: 10000);
      expect(service.adaBaris, isTrue);

      const diskon = RincianBiaya(subtotal: 111000, discount: 5000);
      expect(diskon.adaBaris, isTrue);
    });

    // Tagihan tanpa pajak, tanpa service, tanpa potongan: totalnya
    // memang persis jumlah barisnya. Daftar rincian berisi satu baris
    // yang mengulang angka di atasnya cuma menambah yang harus dibaca.
    test('tanpa biaya tambahan apa pun, tidak ada yang perlu dirinci', () {
      expect(const RincianBiaya(subtotal: 50000).kosong, isTrue);
    });

    test('bolak-balik lewat jsonb tanpa kehilangan apa pun', () {
      const asal = RincianBiaya(
        subtotal: 111000,
        service: 10000,
        ppn: 12100,
        discount: 5000,
        discountName: 'Promo Jumat',
        ppnPercent: 11,
        servicePercent: 10,
      );
      final ulang = RincianBiaya.fromMap(asal.toMap());
      expect(ulang.subtotal, 111000);
      expect(ulang.service, 10000);
      expect(ulang.discount, 5000);
      expect(ulang.discountName, 'Promo Jumat');
      expect(ulang.ppnPercent, 11);
      expect(ulang.servicePercent, 10);
    });

    // Yang sebelum pajak tidak pernah dilihat pelanggan di mana pun.
    // Menaruhnya di baris "Subtotal" membuat tidak satu pun angka di
    // layar ini bisa dijumlahkan ke bawah.
    test('subtotalnya harga menu, bukan nilai sebelum pajak', () {
      expect(checkout, contains('subtotal: cart.total,'));
      expect(checkout, isNot(contains('subtotal: biaya.base')));
    });

    // Service membawa PPN-nya sendiri; barisan yang dijumlahkan maju
    // meleset dari totalnya persis sebesar pajak itu.
    test('baris service dihitung mundur dari totalnya', () {
      expect(layar, contains('total + rincian.discount - subtotal'));
    });
  });

  group('QR-nya hilang setelah kasir mengakui pembayarannya', () {
    test('checkout menyatakan lunas, bukan menunggu layarnya ditutup', () {
      expect(checkout, contains('_layarDepan\n          .lunas('));
    });

    test('dan dikosongkan setelah struknya ditutup', () {
      final sesudah = checkout.substring(checkout.indexOf('ReceiptScreen('));
      expect(sesudah, contains('kosongkan('));
    });

    // qr_string ditimpa apa adanya, tidak di-coalesce seperti rincian —
    // jadi pernyataan lunas yang tidak membawa QR memang menghapusnya.
    test('pernyataan lunas menghapus QR-nya di baris layarnya', () {
      expect(sql, contains('qr_string = excluded.qr_string'));
    });
  });

  // `create or replace` dengan daftar parameter yang berbeda TIDAK
  // menimpa apa pun — ia membuat fungsi KEDUA dengan nama yang sama.
  test('fungsi lamanya dibuang lebih dulu', () {
    expect(
      sql.indexOf('drop function if exists set_customer_display'),
      lessThan(sql.indexOf('create or replace function set_customer_display')),
    );
  });
}
