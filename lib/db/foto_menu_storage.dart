import 'dart:convert';
import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

/// Foto menu di Supabase Storage.
///
/// Sebelumnya fotonya tersimpan sebagai `products.photo_base64`. Aliran
/// realtime Supabase tidak bisa memilih kolom — `.stream()` selalu
/// mengambil baris utuh, dan payload perubahannya juga baris utuh — jadi
/// selama isinya di sana, tiap foto terkirim ulang tiap kali seorang
/// pelanggan membuka menu DAN tiap kali satu produk berubah. Menandai
/// satu barang habis mengirim ulang seluruh album ke semua orang yang
/// sedang membuka menu.
///
/// Di Storage ia disajikan lewat CDN: tidak melewati Postgres, tidak
/// menempati ukuran database, dan yang membukanya kedua kali tidak
/// mengunduhnya lagi.
class FotoMenuStorage {
  static const ember = 'menu-foto';

  final _client = Supabase.instance.client;

  /// Jalur berkasnya: `<resto_id>/<product_id>.jpg`.
  ///
  /// Segmen pertama bukan kerapian — policy Storage membacanya untuk
  /// menentukan siapa yang boleh menulis. Tanpa itu, karyawan resto mana
  /// pun bisa menimpa foto menu resto lain.
  String jalur(String restoId, String productId) => '$restoId/$productId.jpg';

  /// Mengunggah, lalu mengembalikan tautan publiknya.
  ///
  /// `upsert` menyala: produk yang fotonya diganti menimpa berkas lamanya
  /// alih-alih meninggalkan yatim yang tidak pernah dibaca siapa pun tapi
  /// tetap menghabiskan kuota.
  Future<String> unggah({
    required String restoId,
    required String productId,
    required Uint8List bytes,
  }) async {
    final nama = jalur(restoId, productId);
    try {
      await _client.storage.from(ember).uploadBinary(
            nama,
            bytes,
            fileOptions: const FileOptions(
              contentType: 'image/jpeg',
              upsert: true,
            ),
          );
    } catch (e) {
      // Berkasnya sudah ada dan penimpaan ditolak.
      //
      // `upsert` seharusnya sudah cukup, tapi tidak semua penolakan
      // berbunyi sama: penimpaan bisa gagal karena aturan pada baris
      // objek yang lama, bukan karena unggahannya sendiri. Kalau itu
      // yang terjadi, yang lama dibuang dulu lalu ditulis sebagai
      // berkas baru — hasil akhirnya sama, dan yang diminta memang
      // menggantinya.
      //
      // Dicoba SEKALI. Yang gagal dua kali berarti sebabnya bukan
      // berkas lamanya, dan mengulanginya cuma menunda pesan galat yang
      // memang harus dibaca orang.
      if (!_karenaSudahAda(e)) rethrow;
      await _client.storage.from(ember).remove([nama]);
      await _client.storage.from(ember).uploadBinary(
            nama,
            bytes,
            fileOptions: const FileOptions(
              contentType: 'image/jpeg',
              upsert: true,
            ),
          );
    }

    // Penanda versi di belakang tautannya.
    //
    // Berkasnya bernama tetap, jadi foto yang diganti punya URL yang
    // sama persis dengan yang lama — dan CDN maupun cache HP akan terus
    // menyajikan gambar lama entah sampai kapan. Angka yang berubah tiap
    // unggahan memaksa keduanya mengambil yang baru.
    final dasar = _client.storage.from(ember).getPublicUrl(nama);
    return '$dasar?v=${DateTime.now().millisecondsSinceEpoch}';
  }

  /// Memindahkan satu foto base64 yang sudah ada ke Storage.
  ///
  /// Mengembalikan tautannya, atau null kalau produk itu memang tidak
  /// punya foto — bukan kegagalan, cuma tidak ada yang dipindahkan.
  Future<String?> pindahkan({
    required String restoId,
    required String productId,
    required String? base64,
  }) async {
    if (base64 == null || base64.isEmpty) return null;
    final Uint8List bytes;
    try {
      bytes = base64Decode(base64);
    } catch (_) {
      // Isi kolomnya rusak. Dilewati, bukan menghentikan pemindahan
      // seluruh menu demi satu baris yang memang sudah tidak terbaca.
      return null;
    }
    return unggah(restoId: restoId, productId: productId, bytes: bytes);
  }

  /// Penolakan yang artinya "berkasnya sudah ada di sana".
  ///
  /// Diperiksa dari teksnya karena itulah yang tersedia: Storage
  /// mengembalikan pesan, bukan kode yang bisa dibandingkan. Sengaja
  /// sempit — yang tidak cocok dilempar apa adanya, supaya galat lain
  /// tidak diam-diam berubah jadi hapus-lalu-tulis-ulang.
  bool _karenaSudahAda(Object e) {
    final teks = e.toString().toLowerCase();
    return teks.contains('already exists') ||
        teks.contains('duplicate') ||
        teks.contains('resource already');
  }

  Future<void> hapus(String restoId, String productId) async {
    await _client.storage.from(ember).remove([jalur(restoId, productId)]);
  }
}
