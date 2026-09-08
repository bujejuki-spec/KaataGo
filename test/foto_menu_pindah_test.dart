import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Pemindahan foto menu ke Storage.
///
/// Dua kekeliruan yang sudah benar-benar terjadi dijaga di sini, dan
/// keduanya sama-sama melapor "berhasil" sambil tidak mengerjakan
/// apa-apa — bentuk kegagalan yang paling mahal, karena yang membacanya
/// berhenti memeriksa.
void main() {
  final layar =
      File('lib/screens/product_list_screen.dart').readAsStringSync();
  final provider =
      File('lib/providers/product_provider.dart').readAsStringSync();

  /// Badan fungsinya saja — bukan sejak tombol yang memanggilnya, yang
  /// namanya kebetulan sama dan letaknya jauh di atas.
  final blok = layar.substring(
      layar.indexOf('Future<void> _pindahkanFoto('),
      layar.indexOf('\n  }\n}', layar.indexOf('Future<void> _pindahkanFoto(')));

  test('yang perlu dipindah ditentukan server, bukan salinan lokal', () {
    final potong = blok.substring(0, blok.indexOf('final perlu'));
    expect(potong, contains('getAllOnce('),
        reason: 'Salinan lokal sempat mengaku sudah punya tautan padahal '
            'kirimannya ke server hilang — dan tombolnya lalu menjawab '
            '"semua sudah ada" selamanya.');
    expect(blok, isNot(contains('provider.products')));
  });

  test('tautannya ditunggu sampai server menerimanya', () {
    expect(blok, contains('await provider.simpanTautanFoto('));
    // updateProduct mengirimnya tanpa ditunggu; perulangan berpuluh
    // produk selesai jauh sebelum kirimannya sampai.
    expect(blok, isNot(contains('provider.updateProduct(')));
  });

  test('simpanTautanFoto menunggu tulisan ke server', () {
    final fungsi =
        provider.substring(provider.indexOf('Future<void> simpanTautanFoto('));
    final badan = fungsi.substring(0, fungsi.indexOf('\n  }'));
    expect(badan, contains('await _firestoreRepo.upsert('));
  });

  // Base64 dipertahankan sampai versi barunya tersebar: aplikasi lama
  // membacanya dan tidak tahu apa-apa soal photo_url.
  test('base64 tidak ikut dikosongkan saat memindahkan', () {
    expect(blok, isNot(contains('photoBase64: null')));
  });
}
