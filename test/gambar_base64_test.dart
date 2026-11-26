import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:pos_app/utils/gambar_unggah.dart';

/// Gambar unggahan disimpan sebagai base64, dengan batas yang ditegakkan.
void main() {
  String baca(String jalur) => File(jalur).readAsStringSync();

  /// Gambar sungguhan, bukan byte acak — yang diuji pemeriksanya, dan
  /// pemeriksa yang cuma dilewati byte acak tidak membuktikan apa pun.
  Uint8List jpeg(int lebar, int tinggi) {
    final g = img.Image(width: lebar, height: tinggi);
    // Diisi derau supaya tidak termampatkan jadi beberapa byte: gambar
    // polos satu warna mengecil begitu ekstrem sampai batas ukurannya
    // tidak pernah tersentuh.
    for (var y = 0; y < tinggi; y++) {
      for (var x = 0; x < lebar; x++) {
        g.setPixelRgb(x, y, (x * 7) % 256, (y * 13) % 256, (x * y) % 256);
      }
    }
    return Uint8List.fromList(img.encodeJpg(g, quality: 100));
  }

  group('format diperiksa dari isinya', () {
    test('JPEG dan PNG dikenali', () {
      expect(GambarUnggah.format(jpeg(8, 8)), 'JPEG');
      final png = Uint8List.fromList(img.encodePng(img.Image(width: 4, height: 4)));
      expect(GambarUnggah.format(png), 'PNG');
    });

    test('yang bukan gambar ditolak', () {
      // Nama berkas bisa apa saja — `.jpg` di ujung nama tidak
      // menjadikan isinya JPEG. Yang menolaknya nanti bukan aplikasi ini
      // melainkan peramban pelanggan yang gagal menggambarnya,
      // berbulan-bulan kemudian, tanpa petunjuk apa pun.
      final pdf = Uint8List.fromList(utf8.encode('%PDF-1.4 bukan gambar'));
      expect(GambarUnggah.format(pdf), isNull);
      expect(() => GambarUnggah.siapkan(pdf), throwsA(isA<GambarDitolak>()));
    });

    test('GIF ditolak walau ia gambar', () {
      final gif = Uint8List.fromList(
          img.encodeGif(img.Image(width: 4, height: 4)));
      expect(GambarUnggah.format(gif), isNull);
    });
  });

  group('ukurannya ditegakkan', () {
    test('gambar besar dikecilkan, bukan ditolak', () {
      // Foto dari kamera HP lazim 4-8 MB. Menolaknya mentah-mentah
      // berarti menyuruh orang mengecilkan fotonya sendiri — dan yang
      // sedang berdiri di depan kasir tidak akan melakukannya.
      final besar = jpeg(3000, 2000);
      final hasil = GambarUnggah.siapkan(besar, sisiMaks: 800);
      final byte = base64Decode(hasil);

      expect(byte.length, lessThan(GambarUnggah.maksBytes));
      final kecil = img.decodeImage(byte)!;
      expect(kecil.width, lessThanOrEqualTo(800));
      expect(kecil.height, lessThanOrEqualTo(800));
    });

    test('hasilnya selalu di bawah 2 MB', () {
      final hasil = GambarUnggah.siapkan(jpeg(2400, 2400), sisiMaks: 1600);
      expect(base64Decode(hasil).length,
          lessThanOrEqualTo(GambarUnggah.maksBytes));
    });

    test('yang kecil tidak diperbesar', () {
      // Memperbesar yang kecil cuma menambah ukuran tanpa menambah satu
      // pun detail.
      final hasil = GambarUnggah.siapkan(jpeg(200, 150), sisiMaks: 1600);
      final g = img.decodeImage(base64Decode(hasil))!;
      expect(g.width, 200);
      expect(g.height, 150);
    });
  });

  group('foto menu tidak boleh kembali ke baris produk', () {
    // Aliran realtime Supabase selalu mengirim BARIS UTUH. Selama
    // fotonya di baris produk, menandai satu barang habis berarti
    // mengirim ulang seluruh album ke tiap pelanggan yang sedang
    // membuka menu.
    test('disimpan di tabelnya sendiri', () {
      final sql = baca('supabase/gambar_base64.sql');
      expect(sql, contains('create table if not exists product_photos'));

      final repo = baca('lib/db/foto_menu_repository.dart');
      expect(repo, contains("from('product_photos')"));
    });

    test('form produk mengosongkan kolom foto di baris produknya', () {
      final form = baca('lib/screens/product_form_screen.dart');
      final blok = form.substring(form.indexOf('if (_pickedPhoto != null)'));
      final simpan = blok.substring(0, blok.indexOf('} else if'));
      expect(simpan, contains('_fotoMenu.simpan('));
      expect(simpan, contains('photoBase64 = null;'));
      expect(simpan, contains('photoUrl = null;'));
    });

    test('fotonya diambil sekali per merchant, lalu diingat', () {
      final repo = baca('lib/db/foto_menu_repository.dart');
      expect(repo, contains('_sudahMuat'));
      expect(repo, contains('static final Map<String, String> _ingatan'));
    });
  });

  group('batasnya ditegakkan server juga', () {
    final sql = baca('supabase/gambar_base64.sql');

    test('fungsi bukti bayar menolak yang kebesaran', () {
      // Aplikasi memang sudah memeriksa, tapi fungsinya terbuka untuk
      // `anon`: yang memanggilnya langsung bisa mengirim apa saja.
      expect(sql, contains('length(p_jalur) > 3000000'));
    });

    test('pengajuan langganan dan izin ikut dibatasi', () {
      expect(sql, contains("raise exception 'Bukti transfernya terlalu besar.'"));
      expect(sql, contains("raise exception 'Bukti suratnya terlalu besar.'"));
    });
  });
}
