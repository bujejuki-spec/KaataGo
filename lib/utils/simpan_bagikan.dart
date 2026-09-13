library;

/// Menyerahkan berkas jadi ke orangnya.
///
/// Diimpor bersyarat. `dart:io` dan `path_provider` tidak ada di
/// peramban, dan mengimpornya tanpa syarat membuat konsol web gagal
/// dibangun seluruhnya — padahal justru di konsol itulah laporan
/// absensi paling sering diunduh.
export 'simpan_bagikan_web.dart'
    if (dart.library.io) 'simpan_bagikan_io.dart';
