import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Stok diambil sebelum pesanannya dibuat, bukan sesudahnya.
///
/// Urutannya yang menentukan seluruh perilakunya, dan urutan tidak
/// terlihat dari hasil satu pesanan mana pun — ia hanya terlihat saat
/// tiga orang menekan tombol dalam detik yang sama, keadaan yang tidak
/// muncul di pengujian tangan. Karena itu yang dijaga di sini letaknya
/// di kode, bukan hasilnya.
void main() {
  final provider =
      File('lib/providers/customer_cart_provider.dart').readAsStringSync();

  group('pesanan pelanggan mengambil stok lebih dulu', () {
    test('ambilStok dipanggil sebelum pesanannya dibuat', () {
      final ambil = provider.indexOf('ambilStok(');
      final buat = provider.indexOf('_orderRepo.create(');

      expect(ambil, greaterThan(-1),
          reason: 'Pesanan pelanggan harus mengambil stok lewat ambilStok.');
      expect(buat, greaterThan(-1));
      expect(ambil, lessThan(buat),
          reason: 'Stok yang diambil setelah pesanannya dibuat berarti '
              'pemeriksaannya terjadi sesudah keputusannya diambil — '
              'tiga pemesan barang terakhir akan berhasil semua.');
    });

    test('pesanan yang gagal disimpan mengembalikan stoknya', () {
      expect(provider, contains('kembalikanStok('));
    });

    // decrement_stock memakai greatest(stock - qty, 0): ia tidak pernah
    // menolak, dan angkanya berhenti di nol alih-alih turun ke minus —
    // jadi kelebihan pesanan tidak meninggalkan jejak sama sekali.
    test('tidak lagi memakai pengurangan yang tidak bisa menolak', () {
      expect(provider, isNot(contains('decrementStockForOrder(')));
    });
  });
}
