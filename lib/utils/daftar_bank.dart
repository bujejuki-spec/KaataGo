/// Bank dan dompet digital yang bisa dipilih merchant.
///
/// Dipilih dari daftar, bukan diketik. Alasannya bukan kerapian:
/// keunikan rekening di basis data ditentukan pasangan
/// `lower(bank_name)` dan nomor rekeningnya. Selama nama banknya
/// diketik tangan, "BCA", "Bank BCA", dan "bca " adalah tiga bank yang
/// berbeda bagi Postgres — dan rekening yang sama berakhir sebagai tiga
/// baris, masing-masing dengan mutasi yang tertaut sebagian.
///
/// Kekeliruan seperti itu tidak pernah muncul sebagai galat. Yang muncul
/// cuma rekonsiliasi yang tidak pernah cocok, dan tidak ada yang tahu
/// kenapa.
library;

/// Nama resmi singkat, ditulis seperti yang dikenal orang di lapangan.
///
/// Bukan nama hukumnya — "PT Bank Central Asia Tbk" tidak membantu kasir
/// yang sedang mencari BCA di daftar.
const kDaftarBank = <String>[
  // Bank besar, ditaruh di atas karena inilah yang dipakai hampir semua
  // merchant. Daftar yang benar-benar urut abjad memaksa yang mencari
  // BCA menggulir melewati belasan bank daerah lebih dulu.
  'BCA',
  'Mandiri',
  'BRI',
  'BNI',
  'BSI',
  'CIMB Niaga',
  'Permata',
  'Danamon',
  'BTN',
  'Panin',
  'OCBC',
  'Maybank',
  'BTPN',
  'Mega',
  'Sinarmas',
  'Bukopin',
  'Muamalat',
  'BJB',
  'DKI',
  'Jateng',
  'Jatim',
  'Nagari',
  'Sumut',
  'Sumsel Babel',
  'Riau Kepri',
  'Kalbar',
  'Kaltimtara',
  'Kalsel',
  'Sulselbar',
  'NTB Syariah',
  'Bali',
  'Papua',
  'Artha Graha',
  'Commonwealth',
  'DBS Indonesia',
  'HSBC Indonesia',
  'UOB Indonesia',
  'Standard Chartered',
  'Citibank Indonesia',
  'Jago',
  'Seabank',
  'Allo Bank',
  'Neo Commerce',
  'Blu BCA Digital',
  'Krom',
  'Superbank',
  // Dompet digital. Sebagian merchant kecil memang menerima setoran ke
  // sana, dan menolaknya berarti mereka kembali mengetik nama bank
  // sendiri — yang justru ingin dihindari daftar ini.
  'GoPay',
  'OVO',
  'DANA',
  'ShopeePay',
  'LinkAja',
];

/// Daftar pilihan untuk sebuah nilai yang sudah tersimpan.
///
/// Data lama diketik tangan sebelum daftar ini ada, jadi isinya belum
/// tentu ada di sini. Yang tidak ada disisipkan apa adanya supaya
/// menyunting rekening lama tidak diam-diam mengganti banknya jadi yang
/// pertama di daftar — kekeliruan yang tidak terlihat sampai uangnya
/// dikirim ke tempat yang salah.
List<String> daftarBankUntuk(String? tersimpan) {
  final nilai = tersimpan?.trim() ?? '';
  if (nilai.isEmpty) return kDaftarBank;
  final adaSama = kDaftarBank.any((b) => b.toLowerCase() == nilai.toLowerCase());
  return adaSama ? kDaftarBank : [nilai, ...kDaftarBank];
}

/// Nilai yang cocok di daftar, mengabaikan besar-kecil hurufnya.
///
/// Dipakai supaya "bca" yang tersimpan dari data lama tetap terpilih
/// sebagai "BCA", bukan tampil sebagai pilihan kedua yang mirip.
String? bankTerpilih(String? tersimpan, List<String> pilihan) {
  final nilai = tersimpan?.trim() ?? '';
  if (nilai.isEmpty) return null;
  for (final b in pilihan) {
    if (b.toLowerCase() == nilai.toLowerCase()) return b;
  }
  return null;
}
