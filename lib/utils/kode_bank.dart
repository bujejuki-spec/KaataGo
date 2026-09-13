/// Sandi bank tiga digit dari Bank Indonesia.
///
/// Dipakai di slip gaji dan daftar transfer payroll. Bagian keuangan yang
/// mengunggah daftar gaji ke internet banking diminta kode banknya, bukan
/// namanya — dan nama bank yang ditulis tanpa kodenya membuat pekerjaan
/// mencarinya berpindah ke orang yang sedang memproses puluhan baris.
///
/// ── Dari mana angkanya ───────────────────────────────────────────────
///
/// Sandi bank BI, yaitu kode yang sama yang dipakai kliring, RTGS, dan
/// BI-FAST. Angkanya dicocokkan dengan daftar sandi bank yang diterbitkan
/// ulang oleh bank dan penyedia transfer; yang di sini disalin untuk bank
/// yang memang ada di [kDaftarBank] saja.
///
/// Bank yang berganti nama memakai sandi lamanya: Allo Bank memakai 567
/// dari Bank Harda Internasional, dan itu memang benar — yang berganti
/// namanya, bukan banknya.
///
/// ── Yang sengaja tidak punya kode ────────────────────────────────────
///
/// Dompet digital tidak punya sandi bank BI. GoPay, OVO, DANA,
/// ShopeePay, dan LinkAja memang menerima transfer, tapi lewat jalur
/// yang kodenya ditentukan masing-masing penyedia dan berbeda-beda antar
/// bank pengirim.
///
/// Yang tidak punya kode dibiarkan null, bukan diisi tebakan. Kode bank
/// yang salah tidak pernah muncul sebagai galat: uangnya terkirim, dan
/// yang ketahuan belakangan cuma bahwa gajinya tidak sampai.
library;

/// Sandi bank per nama di [kDaftarBank]. Null berarti memang tidak ada.
const _kode = <String, String?>{
  'BCA': '014',
  'Mandiri': '008',
  'BRI': '002',
  'BNI': '009',
  'BSI': '451',
  'CIMB Niaga': '022',
  'Permata': '013',
  'Danamon': '011',
  'BTN': '200',
  'Panin': '019',
  'OCBC': '028',
  'Maybank': '016',
  'BTPN': '213',
  'Mega': '426',
  'Sinarmas': '153',
  'Bukopin': '441',
  'Muamalat': '147',

  // Bank pembangunan daerah. Sandinya berurutan mulai 110 — bukan
  // kebetulan, memang dikelompokkan begitu oleh BI.
  'BJB': '110',
  'DKI': '111',
  'Jateng': '113',
  'Jatim': '114',
  'Nagari': '118',
  'Sumut': '117',
  'Sumsel Babel': '120',
  'Riau Kepri': '119',
  'Kalbar': '123',
  'Kaltimtara': '124',
  'Kalsel': '122',
  'Sulselbar': '126',
  'NTB Syariah': '128',
  'Bali': '129',
  'Papua': '132',

  'Artha Graha': '037',
  'Commonwealth': '950',
  'DBS Indonesia': '046',
  'HSBC Indonesia': '041',
  'UOB Indonesia': '023',
  'Standard Chartered': '050',
  'Citibank Indonesia': '031',

  // Bank digital.
  'Jago': '542',
  'Seabank': '535',
  'Allo Bank': '567',
  'Neo Commerce': '490',
  'Blu BCA Digital': '501',
  'Krom': '459',
  'Superbank': '562',

  // Dompet digital — tidak punya sandi bank BI.
  'GoPay': null,
  'OVO': null,
  'DANA': null,
  'ShopeePay': null,
  'LinkAja': null,
};

/// Sandi banknya, atau null kalau memang tidak ada.
///
/// Dicocokkan tanpa memperhatikan besar-kecil huruf dan spasi di ujung:
/// rekening lama diketik tangan sebelum daftar banknya ada, dan "bca "
/// yang tersimpan sejak dulu tetap harus ketemu kodenya.
String? kodeBank(String? namaBank) {
  final nama = namaBank?.trim() ?? '';
  if (nama.isEmpty) return null;
  for (final e in _kode.entries) {
    if (e.key.toLowerCase() == nama.toLowerCase()) return e.value;
  }
  return null;
}

/// "014 — BCA", atau namanya saja kalau tidak ada kodenya.
///
/// Satu kolom, bukan dua. Kolom kode yang sebagian besarnya terisi lalu
/// kosong di beberapa baris terbaca seperti data yang gagal dimuat —
/// padahal memang tidak ada yang bisa diisi di sana.
String bankBerkode(String? namaBank) {
  final nama = namaBank?.trim() ?? '';
  if (nama.isEmpty) return '-';
  final kode = kodeBank(nama);
  return kode == null ? nama : '$kode — $nama';
}
