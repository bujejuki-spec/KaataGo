import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pos_app/models/cart_item.dart';
import 'package:pos_app/models/product.dart';

/// Topping harus terbaca di seluruh jalur yang dilewatinya.
///
/// Harganya sudah lama ikut terhitung, jadi kesalahannya tidak pernah
/// muncul sebagai angka yang salah — yang terjadi cuma dua baris "Ayam
/// Geprek" berharga berbeda tanpa satu pun keterangan kenapa berbeda.
/// Kekeliruan yang tidak mengubah angka adalah yang paling lama tidak
/// ketahuan.
void main() {
  final produk = Product(
    id: 'p1',
    name: 'Ayam Geprek',
    category: 'Makanan',
    price: 25000,
    toppings: const [
      Topping(name: 'Keju', price: 5000),
      Topping(name: 'Telur', price: 4000),
    ],
    maxToppings: 2,
    levelGroups: const ['Level Pedas'],
  );

  CartItem baris({List<String> topping = const [], String? catatan}) => CartItem(
        lineId: 'l1',
        product: produk,
        selectedLevels: {'Level Pedas': 'Pedas'},
        selectedToppings: topping,
        notes: catatan,
      );

  group('rangkuman yang dibawa ke struk, detail order, dan dapur', () {
    test('topping disebut namanya', () {
      expect(baris(topping: ['Keju', 'Telur']).noteSummary,
          contains('Topping: Keju, Telur'));
    });

    test('level dan topping muncul berdampingan', () {
      final ringkas = baris(topping: ['Keju']).noteSummary!;
      expect(ringkas, contains('Level Pedas: Pedas'));
      expect(ringkas, contains('Topping: Keju'));
    });

    test('catatan bebas tetap terbawa di belakangnya', () {
      expect(baris(topping: ['Keju'], catatan: 'tanpa bawang').noteSummary,
          contains('tanpa bawang'));
    });

    test('tanpa topping tidak menyisakan kata "Topping"', () {
      expect(baris().noteSummary, isNot(contains('Topping')));
    });
  });

  group('harganya ikut topping', () {
    test('tiap topping menambah harga satuannya', () {
      expect(baris().effectiveUnitPrice, 25000);
      expect(baris(topping: ['Keju']).effectiveUnitPrice, 30000);
      expect(baris(topping: ['Keju', 'Telur']).effectiveUnitPrice, 34000);
    });

    // Keju+telur dan telur+keju adalah pesanan yang sama; tanpa urutan
    // yang tetap keduanya jadi dua baris berbeda di dapur.
    test('urutan memilih tidak melahirkan varian baru', () {
      expect(baris(topping: ['Keju', 'Telur']).variantKey,
          baris(topping: ['Telur', 'Keju']).variantKey);
    });
  });

  // Kepingnya di keranjang, lembar varian, dan checkout dibangun satu
  // widget yang sama.
  test('keranjang menampilkan toppingnya, bukan cuma level', () {
    final tile = File('lib/widgets/cart_line_tile.dart').readAsStringSync();
    final blok = tile.substring(tile.indexOf('final options = ['));
    expect(blok.substring(0, blok.indexOf('];')),
        contains('item.selectedToppings'));
  });

  test('struk dan kartu pesanan menuliskan catatannya', () {
    expect(File('lib/utils/receipt_image.dart').readAsStringSync(),
        contains('line.note'));
    expect(File('lib/widgets/order_card.dart').readAsStringSync(),
        contains('item.notes'));
  });
}
