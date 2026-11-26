import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../utils/gambar_unggah.dart';

/// Foto menu, tersimpan sebagai base64 di tabelnya sendiri.
///
/// ── Kenapa bukan di baris produknya ──────────────────────────────────
///
/// Kolom `products.photo_base64` masih ada, dan justru kolom itulah yang
/// dulu jadi masalah: aliran realtime Supabase tidak bisa memilih kolom.
/// `.stream()` selalu mengirim BARIS UTUH, dan payload perubahannya juga
/// baris utuh. Selama fotonya di sana, menandai satu barang habis
/// berarti mengirim ulang seluruh album ke setiap pelanggan yang sedang
/// membuka menu.
///
/// Dengan batas 2 MB per foto, menu berisi 30 produk berarti puluhan MB
/// terkirim ulang tiap kali stok berubah. Itu bukan kelambatan kecil;
/// itu kuota pelanggan.
///
/// Di tabel terpisah, baris produk tetap ringan: fotonya diambil sekali
/// per merchant lalu diingat, dan perubahan stok tidak membawanya.
class FotoMenuRepository {
  final _client = Supabase.instance.client;

  /// Foto yang sudah diambil, per id produk.
  ///
  /// Statis supaya satu layar yang memuatnya cukup untuk semua layar
  /// lain: menu pelanggan, daftar produk, dan layar kasir menggambar
  /// produk yang sama.
  static final Map<String, String> _ingatan = {};

  /// Merchant yang fotonya sudah pernah diambil seluruhnya.
  static final Set<String> _sudahMuat = {};

  static String? base64(String productId) => _ingatan[productId];

  static bool get kosong => _ingatan.isEmpty;

  /// Dilupakan saat merchant berganti atau foto diubah, supaya yang
  /// tergambar berikutnya bukan foto lama.
  static void lupakan([String? productId]) {
    if (productId == null) {
      _ingatan.clear();
      _sudahMuat.clear();
    } else {
      _ingatan.remove(productId);
    }
  }

  /// Mengambil seluruh foto milik satu merchant, sekali saja.
  ///
  /// Sekali per merchant, bukan sekali per produk: satu permintaan untuk
  /// tiga puluh foto jauh lebih murah daripada tiga puluh permintaan,
  /// dan menu dibuka dengan seluruh produknya sekaligus.
  Future<void> muat(String restoId, {bool paksa = false}) async {
    if (!paksa && _sudahMuat.contains(restoId)) return;
    final rows = await _client
        .from('product_photos')
        .select('product_id, base64')
        .eq('resto_id', restoId);
    for (final r in rows) {
      final id = r['product_id']?.toString();
      final b = r['base64']?.toString();
      if (id != null && b != null && b.isNotEmpty) _ingatan[id] = b;
    }
    _sudahMuat.add(restoId);
  }

  /// Menyimpan foto sebuah produk.
  ///
  /// Memeriksa format dan ukurannya lebih dulu — yang sampai ke basis
  /// data sudah JPG yang dikecilkan.
  Future<void> simpan({
    required String restoId,
    required String productId,
    required Uint8List bytes,
  }) async {
    // Foto menu boleh jauh lebih kecil daripada bukti transfer: ia
    // digambar seukuran kartu, dan tidak ada angka yang harus terbaca
    // di dalamnya. Yang besar cuma memperlambat menu tanpa menambah
    // satu pun yang terlihat.
    final b64 = GambarUnggah.siapkan(bytes, sisiMaks: 800, mutu: 78);
    await _client.from('product_photos').upsert({
      'product_id': productId,
      'resto_id': restoId,
      'base64': b64,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    });
    _ingatan[productId] = b64;
  }

  Future<void> hapus(String productId) async {
    await _client.from('product_photos').delete().eq('product_id', productId);
    _ingatan.remove(productId);
  }
}
