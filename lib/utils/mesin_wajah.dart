library;

/// Mesin pengenal wajah di perangkat.
///
/// Diimpor bersyarat. `tflite_flutter` berdiri di atas `dart:ffi` dan
/// `google_mlkit_face_detection` di atas kode Android/iOS — keduanya
/// tidak punya wujud apa pun di peramban, dan mengimpornya tanpa syarat
/// membuat konsol web gagal dibangun seluruhnya.
///
/// Absensi memang hanya di aplikasi HP, dan itu bukan keterbatasan yang
/// disesali: yang diperlukan absen wajah berlokasi adalah kamera depan
/// dan GPS yang dibawa orangnya, bukan peramban di komputer kasir yang
/// duduk di tempat yang sama sepanjang hari.
export 'mesin_wajah_kosong.dart'
    if (dart.library.io) 'mesin_wajah_tflite.dart';
