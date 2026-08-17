import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pos_app/models/cart_item.dart';
import 'package:pos_app/models/discount.dart';
import 'package:pos_app/models/product.dart';

Product _p({
  int price = 25000,
  List<Topping> toppings = const [],
  int maxToppings = 0,
}) =>
    Product(
      id: 'p1',
      name: 'Nasi Goreng',
      category: 'Makanan',
      price: price,
      toppings: toppings,
      maxToppings: maxToppings,
    );

const _keju = Topping(name: 'Keju', price: 5000);
const _telur = Topping(name: 'Telur', price: 3000);
const _kerupuk = Topping(name: 'Kerupuk');

CartItem _line(Product p, {List<String>? topping, int qty = 1}) => CartItem(
      lineId: 'l1',
      product: p,
      quantity: qty,
      selectedToppings: topping,
    );

void main() {
  group('harga topping', () {
    test('menambah harga per topping yang dipilih', () {
      final p = _p(toppings: const [_keju, _telur]);
      expect(_line(p, topping: ['Keju']).effectiveUnitPrice, 30000);
      expect(_line(p, topping: ['Keju', 'Telur']).effectiveUnitPrice, 33000);
    });

    test('topping gratis tetap boleh dipilih', () {
      // Menuliskannya tetap berguna: pelanggan jadi tahu ia ada.
      final p = _p(toppings: const [_kerupuk]);
      expect(_line(p, topping: ['Kerupuk']).effectiveUnitPrice, 25000);
    });

    test('ikut terkali jumlah pesanan', () {
      final p = _p(toppings: const [_keju]);
      expect(_line(p, topping: ['Keju'], qty: 3).subtotal, 90000);
    });

    test('harga dibaca dari produknya, bukan dari yang dikirim', () {
      // Harga yang datang bersama pilihan bisa diubah siapa pun yang mau
      // menambahkan keju seharga nol rupiah.
      final p = _p(toppings: const [_keju]);
      expect(p.toppingPrice('Keju'), 5000);
      expect(p.toppingPrice('Keju Palsu'), 0);
    });

    test('topping yang tidak dikenal tidak menambah apa pun', () {
      final p = _p(toppings: const [_keju]);
      expect(_line(p, topping: ['Entah']).effectiveUnitPrice, 25000);
    });
  });

  group('batas jumlah topping', () {
    test('nol berarti sebanyak yang ditawarkan', () {
      final p = _p(toppings: const [_keju, _telur, _kerupuk]);
      expect(p.effectiveMaxToppings, 3);
    });

    test('batas yang disetel dipakai apa adanya', () {
      final p = _p(toppings: const [_keju, _telur, _kerupuk], maxToppings: 2);
      expect(p.effectiveMaxToppings, 2);
    });

    test('menu tanpa topping tidak punya batas yang berarti', () {
      expect(_p().effectiveMaxToppings, 0);
    });
  });

  group('baris keranjang', () {
    test('urutan topping tidak membuat dua baris berbeda', () {
      // Keju+telur dan telur+keju adalah pesanan yang sama; tanpa
      // diurutkan keduanya jadi dua baris di keranjang dan dua tiket di
      // dapur.
      final p = _p(toppings: const [_keju, _telur]);
      expect(_line(p, topping: ['Keju', 'Telur']).variantKey,
          _line(p, topping: ['Telur', 'Keju']).variantKey);
    });

    test('topping berbeda tetap jadi baris berbeda', () {
      final p = _p(toppings: const [_keju, _telur]);
      expect(_line(p, topping: ['Keju']).variantKey,
          isNot(_line(p, topping: ['Telur']).variantKey));
    });

    test('tanpa topping berbeda dari yang pakai topping', () {
      final p = _p(toppings: const [_keju]);
      expect(_line(p).variantKey, isNot(_line(p, topping: ['Keju']).variantKey));
    });

    test('toppingnya tertulis di tiket dapur', () {
      final p = _p(toppings: const [_keju, _telur]);
      expect(_line(p, topping: ['Keju', 'Telur']).noteSummary,
          contains('Topping: Keju, Telur'));
    });

    test('menu tanpa topping tidak menuliskan apa pun', () {
      expect(_line(_p()).noteSummary, isNull);
    });
  });

  group('tersimpan dan terbaca kembali', () {
    test('bolak-balik lewat peta', () {
      final map = _p(toppings: const [_keju, _telur], maxToppings: 2).toMap();
      final lagi = Product.fromMap({...map, 'id': 'p1'});
      expect(lagi.toppings.length, 2);
      expect(lagi.toppings.first.name, 'Keju');
      expect(lagi.toppings.first.price, 5000);
      expect(lagi.maxToppings, 2);
    });

    test('menu tanpa topping tidak menulis kolomnya', () {
      expect(_p().toMap()['toppings'], isNull);
    });

    test('bentuk daftar dari Postgres ikut terbaca', () {
      // sqflite menyimpannya sebagai teks JSON, Postgres mengembalikannya
      // sebagai daftar. Keduanya harus terbaca oleh satu pembaca yang
      // sama.
      final lagi = Product.fromMap({
        'id': 'p1',
        'name': 'A',
        'category': 'K',
        'price': 1000,
        'toppings': [
          {'name': 'Keju', 'price': 5000},
        ],
      });
      expect(lagi.toppings.single.name, 'Keju');
    });

    test('produk lama tanpa kolom topping tetap terbaca', () {
      final lagi = Product.fromMap({
        'id': 'p1',
        'name': 'A',
        'category': 'K',
        'price': 1000,
      });
      expect(lagi.toppings, isEmpty);
      expect(lagi.maxToppings, 0);
    });
  });

  group('penyimpanan', () {
    test('kolomnya ada di Postgres maupun sqflite', () {
      final sql = File('supabase/product_toppings.sql').readAsStringSync();
      expect(sql, contains('add column if not exists toppings'));
      expect(sql, contains('add column if not exists max_toppings'));

      final lokal = File('lib/db/database_helper.dart').readAsStringSync();
      expect(lokal, contains('version: 13'));
      expect(lokal, contains('ADD COLUMN toppings TEXT'));
      expect(lokal, contains('ADD COLUMN max_toppings'));
    });
  });

  group('diskon menyasar level atau topping', () {
    // "Gratis ukuran besar": menunya tetap dibayar penuh, yang hilang
    // cuma selisih ukurannya.
    int dasar(DiscountItem item, Product p, {int qty = 1}) {
      if (item.toppingName != null) {
        return p.toppingPrice(item.toppingName!) * qty;
      }
      if (item.levelOption != null) {
        return p.priceDeltaFor(item.levelGroup!, item.levelOption!) * qty;
      }
      return p.price * qty;
    }

    final p = Product(
      id: 'p1',
      name: 'Kopi',
      category: 'Minuman',
      price: 25000,
      levelGroups: const ['Ukuran'],
      levelPrices: const {
        'Ukuran': {'Besar': 5000, 'Regular': 0}
      },
      toppings: const [_keju],
    );

    test('sasaran level memotong tambahannya saja', () {
      const item = DiscountItem(
          productId: 'p1', levelGroup: 'Ukuran', levelOption: 'Besar');
      expect(dasar(item, p), 5000);

      final promo = Discount(
        id: 'd1',
        restoId: 'r1',
        name: 'Gratis Ukuran Besar',
        basis: DiscountBasis.products,
        kind: DiscountKind.percent,
        value: 100,
        items: const [item],
        createdAt: DateTime(2026, 8, 1),
      );
      // 100% dari 5.000, bukan dari 30.000 — menunya tetap dibayar.
      expect(promo.amountFor(dasar(item, p)), 5000);
    });

    test('sasaran topping memotong harga toppingnya saja', () {
      const item = DiscountItem(productId: 'p1', toppingName: 'Keju');
      expect(dasar(item, p), 5000);
    });

    test('tanpa sasaran, seluruh harga menunya yang dipotong', () {
      const item = DiscountItem(productId: 'p1');
      expect(dasar(item, p), 25000);
      expect(item.targetsAddOn, isFalse);
    });

    test('sasarannya punya nama untuk ditampilkan', () {
      expect(
        const DiscountItem(
                productId: 'p1', levelGroup: 'Ukuran', levelOption: 'Besar')
            .targetLabel,
        'Ukuran: Besar',
      );
      expect(
        const DiscountItem(productId: 'p1', toppingName: 'Keju').targetLabel,
        'Topping: Keju',
      );
      expect(const DiscountItem(productId: 'p1').targetLabel, isNull);
    });

    test('sasarannya ikut tersimpan dan terbaca kembali', () {
      const item = DiscountItem(
          productId: 'p1', levelGroup: 'Ukuran', levelOption: 'Besar');
      final lagi = DiscountItem.fromMap(item.toMap());
      expect(lagi.levelGroup, 'Ukuran');
      expect(lagi.levelOption, 'Besar');
      expect(lagi.toppingName, isNull);
    });

    test('promo lama tanpa sasaran tetap mengenai seluruh menu', () {
      final lagi = DiscountItem.fromMap({'product_id': 'p1', 'qty': 1});
      expect(lagi.targetsAddOn, isFalse);
    });

    test('mengganti sasaran membuang sasaran sebelumnya', () {
      // Tanpa ini, sebuah item bisa menunjuk level DAN topping sekaligus
      // — dua sasaran untuk satu potongan, dan yang menang tergantung
      // urutan pemeriksaan.
      const semula = DiscountItem(
          productId: 'p1', levelGroup: 'Ukuran', levelOption: 'Besar');
      final jadi = semula.copyWith(
          levelGroup: null, levelOption: null, toppingName: 'Keju');
      expect(jadi.levelOption, isNull);
      expect(jadi.toppingName, 'Keju');
    });
  });

}
