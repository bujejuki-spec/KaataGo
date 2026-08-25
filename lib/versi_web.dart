/// Versi konsol web, terpisah dari versi aplikasi.
///
/// Keduanya memang tidak pernah sejalan. APK terbit sesekali lewat
/// release.sh dan nomornya menempel pada berkas yang sudah terpasang di
/// HP orang; konsol web terbit tiap push dan yang dibuka orang selalu
/// yang terakhir. Memakai satu nomor untuk keduanya berarti nomor itu
/// berbohong tentang salah satunya — dan yang paling sering ditanya
/// saat ada yang aneh adalah "kamu pakai versi berapa?".
///
/// Dinaikkan tangan, sama seperti catatan rilis. Yang menaikkannya tahu
/// apakah perubahan kemarin layak disebut versi baru; penghitung
/// otomatis tidak.
const kVersiWeb = '1.0.0';

/// Penanda build dari CI — tujuh huruf pertama commit-nya.
///
/// Nomor versi saja tidak cukup untuk menjawab "yang kamu buka itu
/// yang mana": dalam satu versi yang sama bisa ada belasan build, dan
/// yang melaporkan masalah hampir selalu sedang membuka salah satunya
/// yang bukan terbaru. Kosong saat dibangun di mesin sendiri.
const kBuildWeb = String.fromEnvironment('BUILD_WEB');

/// Yang ditulis di kaki sidebar.
String get labelVersiWeb =>
    kBuildWeb.isEmpty ? 'Web v$kVersiWeb' : 'Web v$kVersiWeb · $kBuildWeb';
