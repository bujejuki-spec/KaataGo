import 'dart:typed_data';

/// Hasil satu pemindaian wajah.
class HasilWajah {
  /// Sidik wajahnya — deret angka keluaran model.
  final List<double> sidik;

  /// Wajah yang sudah dipotong dan diluruskan, untuk disimpan sebagai
  /// bukti yang bisa dilihat manusia.
  final Uint8List potongan;

  const HasilWajah({required this.sidik, required this.potongan});
}

/// Wajah tidak bisa dipindai di sini.
class WajahGagal implements Exception {
  final String pesan;

  const WajahGagal(this.pesan);

  @override
  String toString() => pesan;
}

/// Sisi web: tidak pernah dipakai.
///
/// Ada supaya layar yang memanggilnya tetap bisa dibangun untuk web
/// tanpa percabangan `kIsWeb` di tempat pemakaiannya. Konsol web
/// menampilkan laporan absensi, bukan melakukan absennya.
class MesinWajah {
  static const tersedia = false;

  static const namaModel = 'mobilefacenet-192';

  static Future<bool> siap() async => false;

  static Future<HasilWajah> pindai(String jalurGambar) async =>
      throw const WajahGagal(
          'Absen wajah hanya bisa lewat aplikasi KaataGo di HP.');

  static Future<void> tutup() async {}
}
