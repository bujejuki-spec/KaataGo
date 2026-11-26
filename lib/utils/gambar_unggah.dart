import 'dart:convert';
import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// Gambar yang ditolak, berikut alasan yang bisa dibaca orang.
class GambarDitolak implements Exception {
  final String pesan;

  const GambarDitolak(this.pesan);

  @override
  String toString() => pesan;
}

/// Memeriksa dan menyiapkan gambar yang diunggah, lalu mengubahnya jadi
/// base64.
///
/// ── Kenapa formatnya diperiksa dari ISINYA ───────────────────────────
///
/// Nama berkas bisa apa saja. `.jpg` di ujung nama tidak menjadikan
/// isinya JPEG — dan yang menolaknya nanti bukan aplikasi ini melainkan
/// peramban pelanggan yang gagal menggambarnya, berbulan-bulan kemudian,
/// tanpa petunjuk apa pun tentang sebabnya.
///
/// Jadi yang dibaca beberapa byte pertamanya: tiap format punya tanda
/// pengenalnya sendiri di awal berkas.
///
/// ── Kenapa batasnya diperiksa SESUDAH dikecilkan ─────────────────────
///
/// Foto dari kamera HP sekarang lazim 4-8 MB. Menolaknya mentah-mentah
/// berarti menyuruh orang mengecilkan fotonya sendiri — dan yang sedang
/// berdiri di depan kasir tidak akan melakukannya.
///
/// Yang 2 MB itu batas setelah dikecilkan, bukan batas berkas aslinya.
class GambarUnggah {
  /// Batas akhir, sesudah dikecilkan.
  static const maksBytes = 2 * 1024 * 1024;

  /// Yang diterima. Bukan daftar nama berkas — daftar isi.
  static const formatDiterima = ['JPEG', 'PNG'];

  /// Mengenali format dari tanda pengenal di awal berkas.
  ///
  /// Null berarti bukan salah satu yang diterima.
  static String? format(Uint8List b) {
    if (b.length >= 3 && b[0] == 0xFF && b[1] == 0xD8 && b[2] == 0xFF) {
      return 'JPEG';
    }
    if (b.length >= 8 &&
        b[0] == 0x89 &&
        b[1] == 0x50 &&
        b[2] == 0x4E &&
        b[3] == 0x47) {
      return 'PNG';
    }
    return null;
  }

  /// Memeriksa, mengecilkan seperlunya, lalu mengembalikan base64-nya.
  ///
  /// [sisiMaks] adalah sisi terpanjang yang diizinkan. Bukti transfer
  /// perlu lebih besar daripada foto menu: angkanya harus tetap terbaca
  /// oleh mata orang yang memutuskan uangnya sudah masuk atau belum.
  static String siapkan(
    Uint8List asli, {
    int sisiMaks = 1280,
    int mutu = 80,
  }) {
    final jenis = format(asli);
    if (jenis == null) {
      throw const GambarDitolak(
          'Format gambarnya tidak didukung. Pakai JPG atau PNG.');
    }

    final gambar = img.decodeImage(asli);
    if (gambar == null) {
      throw const GambarDitolak('Gambarnya tidak terbaca. Coba berkas lain.');
    }

    // Dikecilkan hanya kalau memang lebih besar. Memperbesar yang kecil
    // cuma menambah ukuran tanpa menambah satu pun detail.
    final perluKecil = gambar.width > sisiMaks || gambar.height > sisiMaks;
    final dipakai = perluKecil
        ? img.copyResize(
            gambar,
            width: gambar.width >= gambar.height ? sisiMaks : null,
            height: gambar.height > gambar.width ? sisiMaks : null,
            interpolation: img.Interpolation.average,
          )
        : gambar;

    // Selalu keluar sebagai JPEG, termasuk yang masuk sebagai PNG.
    //
    // PNG tidak merugi saat dimampatkan, dan foto yang disimpan sebagai
    // PNG bisa sepuluh kali lebih besar daripada JPEG yang terlihat
    // sama. Yang diunggah di sini foto dan tangkapan layar, bukan logo
    // bertepi tajam yang memang menuntut PNG.
    var byte = Uint8List.fromList(img.encodeJpg(dipakai, quality: mutu));

    // Masih terlalu besar? Turunkan mutunya bertahap.
    //
    // Berhenti di 40: di bawah itu angka pada bukti transfer mulai
    // berbayang, dan gambar yang tidak terbaca sama saja dengan tidak
    // ada gambar.
    var mutuKini = mutu;
    while (byte.length > maksBytes && mutuKini > 40) {
      mutuKini -= 15;
      byte = Uint8List.fromList(img.encodeJpg(dipakai, quality: mutuKini));
    }

    if (byte.length > maksBytes) {
      throw const GambarDitolak(
          'Gambarnya terlalu besar, bahkan setelah dikecilkan. '
          'Coba foto yang lain.');
    }

    return base64Encode(byte);
  }
}
