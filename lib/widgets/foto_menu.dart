import 'package:flutter/material.dart';

import '../models/product.dart';
import '../utils/gambar_base64.dart';

/// Satu tempat yang memutuskan gambar mana yang dipakai sebuah produk.
///
/// Selama masa peralihan ada dua sumber sekaligus: `photoUrl` di
/// Supabase Storage untuk yang sudah dipindahkan, dan `photoBase64` di
/// baris tabelnya untuk yang belum. Menaruh keputusan itu di tiap tempat
/// yang menggambar foto berarti salah satunya akan ketinggalan saat
/// cadangannya nanti dicabut — dan yang ketinggalan justru terlihat
/// sebagai menu tanpa gambar, bukan sebagai galat.
///
/// Urutannya sengaja: tautan lebih dulu. Produk yang sudah dipindahkan
/// tapi base64-nya belum dibersihkan punya keduanya, dan yang benar
/// dipakai adalah yang tidak melewati Postgres.
class FotoMenu extends StatelessWidget {
  final Product product;

  /// Digambar saat produknya memang tidak punya foto, dan saat fotonya
  /// gagal dimuat. Keduanya sama bagi yang melihat: tidak ada gambar.
  final Widget kosong;

  final BoxFit fit;

  const FotoMenu({
    super.key,
    required this.product,
    required this.kosong,
    this.fit = BoxFit.cover,
  });

  /// Ada gambarnya, dari sumber mana pun.
  static bool punyaFoto(Product p) =>
      (p.photoUrl != null && p.photoUrl!.isNotEmpty) ||
      (p.photoBase64 != null && p.photoBase64!.isNotEmpty);

  @override
  Widget build(BuildContext context) {
    final url = product.photoUrl;
    if (url != null && url.isNotEmpty) {
      return Image.network(
        url,
        width: double.infinity,
        fit: fit,
        // Ruangnya dipegang selama gambarnya turun, bukan dibiarkan
        // kosong lalu tiba-tiba terisi: daftar menu yang tingginya
        // berubah saat digulir memindahkan barang yang sedang mau
        // diketuk orangnya.
        loadingBuilder: (context, child, kemajuan) =>
            kemajuan == null ? child : kosong,
        // Jaringan mati, berkasnya terhapus, tautannya kedaluwarsa —
        // semuanya berakhir di sini. Kalau base64-nya masih ada, ia
        // dipakai; kalau tidak, tempatnya kosong tapi menunya tetap
        // terbaca.
        errorBuilder: (_, __, ___) => _dariBase64() ?? kosong,
      );
    }
    return _dariBase64() ?? kosong;
  }

  Widget? _dariBase64() {
    final b64 = product.photoBase64;
    if (b64 == null || b64.isEmpty) return null;
    return Image.memory(
      byteGambar(b64),
      width: double.infinity,
      fit: fit,
      // Isi kolom yang rusak melempar galat saat digambar, dan tanpa ini
      // ia mengosongkan seluruh daftarnya, bukan cuma satu kartunya.
      errorBuilder: (_, __, ___) => kosong,
    );
  }
}
