import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:pos_app/models/product.dart';

/// Bentuk baris produk yang dikirim ke server.
///
/// `toppings` di Postgres berupa `jsonb not null default '[]'`, dan nilai
/// bawaan hanya berlaku saat kolomnya tidak disebut sama sekali — null
/// yang dikirim tegas tetap melanggar not-null.
///
/// Selama ini produk tanpa topping mengirimkan null, jadi SETIAP
/// penyimpanan produk semacam itu ditolak server dengan "null value in
/// column toppings violates not-null constraint". Penolakannya tidak
/// pernah terlihat karena kirimannya tidak ditunggu dan galatnya ditelan;
/// yang terlihat cuma akibatnya — perubahan tersimpan di HP dan tidak
/// pernah sampai ke server.
void main() {
  Product produk({List<Topping> toppings = const []}) => Product(
        id: 'p1',
        name: 'Es Teh',
        category: 'Minuman',
        price: 5000,
        toppings: toppings,
      );

  test('produk tanpa topping mengirim [] , bukan null', () {
    final map = produk().toMap();
    expect(map['toppings'], isNotNull);
    expect(map['toppings'], '[]');
    expect(jsonDecode(map['toppings'] as String), isEmpty);
  });

  test('produk bertopping tetap mengirim isinya', () {
    final map = produk(toppings: [
      const Topping(name: 'Boba', price: 3000),
    ]).toMap();
    final isi = jsonDecode(map['toppings'] as String) as List;
    expect(isi.length, 1);
    expect(isi.first['name'], 'Boba');
  });

  // Bolak-balik lewat toMap/fromMap harus menghasilkan produk yang sama.
  test('kosong dan berisi sama-sama pulang utuh', () {
    expect(Product.fromMap(produk().toMap()).toppings, isEmpty);
    final berisi = produk(toppings: [const Topping(name: 'Keju', price: 5000)]);
    expect(Product.fromMap(berisi.toMap()).toppings.first.name, 'Keju');
  });
}
