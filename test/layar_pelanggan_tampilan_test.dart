import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Tampilan layar yang menghadap pelanggan.
void main() {
  final layar =
      File('lib/screens/customer_display_screen.dart').readAsStringSync();

  group('nama merchant', () {
    test('dibaca dari barisnya sendiri, bukan setelan', () {
      // Nilai bawaan SettingsProvider "Toko Kamu" — nama yang jelas
      // bukan nama tempat itu, di layar yang justru paling dilihat
      // orang luar.
      expect(layar, contains('_merchantRepo.getOnce(restoId)'));
      // Namanya masih disebut di komentar sebagai catatan; yang tidak
      // boleh kembali pemakaiannya.
      expect(layar, isNot(contains('watch<SettingsProvider>()')));
      expect(layar, isNot(contains("Text(nama)")));
    });

    test('kosong lebih baik daripada nama yang salah', () {
      expect(layar, contains('if (nama != null)'));
    });

    test('gagal membacanya tidak menjatuhkan layarnya', () {
      expect(layar, contains('} catch (_) {'));
    });
  });

  group('QR-nya', () {
    test('memakai kartu KaataGo, bukan kotak putih polos', () {
      // Bingkai, logo, dan tulisannya sudah dirancang untuk dipindai
      // dari seberang meja.
      expect(layar, contains('KaataQrCard('));
      expect(layar, isNot(contains('QrImageView(')));
    });

    test('berada di tengah', () {
      // Lebarnya dipatok sendiri oleh kartunya, jadi tanpa Center ia
      // menempel ke kiri pada layar yang lebih lebar.
      final blok = layar.substring(layar.indexOf('if (tampilan.adaQr)'));
      expect(blok.indexOf('Center('), lessThan(blok.indexOf('KaataQrCard(')));
    });

    test('judulnya nama merchant-nya', () {
      expect(layar, contains("title: nama ?? 'Pembayaran'"));
    });

    test('tetap memberi arahan kalau QR-nya tidak ada', () {
      expect(layar, contains("'Silakan bayar di kasir'"));
    });
  });
}
