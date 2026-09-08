/// Mengupas kalimat yang layak dibaca orang dari galat Postgres.
///
/// Yang dilempar Supabase datang dengan bungkusnya:
///
///   PostgrestException(message: Nasi Goreng sudah habis. Hapus dari
///   keranjang lalu pesan lagi., code: P0001, details: ..., hint: null)
///
/// Yang perlu dibaca orang yang sedang memegang HP-nya cuma kalimat di
/// dalamnya. Sisanya ditulis untuk yang menulis programnya, dan
/// menampilkannya utuh di layar membuat pesan yang sebenarnya ramah
/// terbaca seperti aplikasi yang rusak.
///
/// Ditaruh di satu tempat karena sudah disalin dua kali, dan salinan
/// ketiga berarti perbaikan berikutnya pasti melewatkan salah satunya.
String pesanGalat(Object e) {
  final teks = e.toString();
  final i = teks.indexOf('message: ');
  if (i >= 0) {
    final sisa = teks.substring(i + 9);
    final akhir = sisa.indexOf(', code:');
    return akhir > 0 ? sisa.substring(0, akhir) : sisa;
  }
  return teks;
}
