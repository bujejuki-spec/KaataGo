/// Memeriksa apakah sebuah teks benar-benar payload QRIS.
///
/// Yang diunggah merchant adalah foto atau tangkapan layar QR-nya, dan
/// tanpa pemeriksaan apa pun yang tersimpan bisa saja foto struk, foto
/// kucing, atau QR milik orang lain. Kekeliruannya baru ketahuan saat
/// pelanggan pertama berdiri di kasir memandangi gambar yang tidak bisa
/// dipindai — dan yang menanggung malunya kasir, bukan yang mengunggah.
///
/// QRIS mengikuti EMVCo Merchant Presented Mode. Bentuknya rangkaian
/// "tag-panjang-nilai": dua digit tag, dua digit panjang, lalu isinya
/// sepanjang itu, berulang sampai habis.
library;

/// Hasil pemeriksaan, berikut alasannya kalau ditolak.
class HasilPeriksaQris {
  final bool sah;
  final String? alasan;

  /// Nama merchant yang tertulis di dalam QR-nya (tag 59), kalau ada.
  /// Ditunjukkan setelah unggah supaya yang mengunggah bisa memastikan
  /// QR-nya memang miliknya, bukan milik kios sebelah.
  final String? namaMerchant;

  const HasilPeriksaQris.sah({this.namaMerchant})
      : sah = true,
        alasan = null;

  const HasilPeriksaQris.ditolak(this.alasan)
      : sah = false,
        namaMerchant = null;
}

/// Memeriksa payload hasil pemindaian.
///
/// Sengaja tidak menghitung ulang CRC-nya. Pemeriksaan yang terlalu
/// ketat menolak QR yang sebenarnya sah — sebagian penerbit menuliskan
/// CRC dengan huruf kecil, sebagian pemindai mengembalikan payload yang
/// sudah dipangkas spasinya — dan QR sah yang ditolak jauh lebih
/// merepotkan daripada QR asing yang lolos, karena yang kedua ketahuan
/// saat itu juga dari nama merchantnya.
HasilPeriksaQris periksaPayloadQris(String? payload) {
  final teks = (payload ?? '').trim();
  if (teks.isEmpty) {
    return const HasilPeriksaQris.ditolak(
        'Gambarnya tidak berisi QR yang bisa dibaca.');
  }

  // Tag 00 wajib ada di paling depan, panjang 02, isinya "01" — penanda
  // format payload EMVCo. Semua QRIS diawali persis "000201".
  if (!teks.startsWith('000201')) {
    return const HasilPeriksaQris.ditolak(
        'QR ini bukan QRIS. Yang terbaca QR biasa — pastikan yang '
        'diunggah QRIS dari penyedia pembayaranmu.');
  }

  final tag = _uraikan(teks);
  if (tag == null) {
    return const HasilPeriksaQris.ditolak(
        'Isi QR-nya tidak lengkap atau rusak. Coba foto ulang lebih '
        'terang dan tegak lurus.');
  }

  // Tag 52 (kode kategori merchant) dan 53 (mata uang) selalu ada pada
  // QRIS. Yang tidak punya keduanya bukan QR pembayaran.
  if (!tag.containsKey('53')) {
    return const HasilPeriksaQris.ditolak(
        'QR ini tidak menyebutkan mata uang, jadi bukan QR pembayaran.');
  }
  // 360 = Rupiah.
  if (tag['53'] != '360') {
    return const HasilPeriksaQris.ditolak(
        'QR ini bukan dalam Rupiah, jadi bukan QRIS Indonesia.');
  }

  // QRIS punya identitas penyelenggaranya di salah satu tag 26–51.
  final adaPenyelenggara = tag.keys.any((k) {
    final n = int.tryParse(k);
    return n != null && n >= 26 && n <= 51;
  });
  if (!adaPenyelenggara) {
    return const HasilPeriksaQris.ditolak(
        'QR ini tidak berisi identitas penyelenggara QRIS.');
  }

  return HasilPeriksaQris.sah(namaMerchant: tag['59']);
}

/// Menguraikan rangkaian tag-panjang-nilai jadi peta.
///
/// Mengembalikan null kalau susunannya tidak utuh — panjang yang
/// menunjuk ke luar teks, atau tag yang terpotong di tengah. Payload
/// yang tidak bisa diuraikan tidak bisa dipercaya isinya.
Map<String, String>? _uraikan(String teks) {
  final hasil = <String, String>{};
  var i = 0;
  while (i + 4 <= teks.length) {
    final tag = teks.substring(i, i + 2);
    final panjang = int.tryParse(teks.substring(i + 2, i + 4));
    if (panjang == null) return null;
    final mulai = i + 4;
    final akhir = mulai + panjang;
    if (akhir > teks.length) return null;
    hasil[tag] = teks.substring(mulai, akhir);
    i = akhir;
  }
  // Ada sisa yang tidak membentuk satu tag utuh.
  if (i != teks.length) return null;
  return hasil.isEmpty ? null : hasil;
}
