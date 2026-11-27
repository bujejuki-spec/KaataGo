/// Alamat konsol web KaataGo.
///
/// Dipakai sebagai isi QR meja, jadi mengubahnya membuat seluruh stiker
/// yang sudah tercetak menunjuk ke tempat yang salah. Kalau alamatnya
/// pindah, jalur lama harus tetap dilayani — bukan sekadar dialihkan
/// sekali lalu dilupakan.
/// ── Catatan untuk saat pindah ke kaatago.app nanti ───────────────────
///
/// Domainnya sudah dibeli dan DNS-nya sudah disiapkan, tapi pindahnya
/// ditunda. Tiga hal yang mahal dipelajari ulang:
///
/// 1. Berkas `CNAME` HARUS ditulis oleh `.github/workflows/web.yml`,
///    bukan dipasang sekali lewat UI GitHub. Langkah dorong di workflow
///    melakukan `git init` lalu `push --force` — ia mengganti seluruh
///    isi repo situs, jadi CNAME dari UI hilang pada deploy berikutnya
///    dan domainnya lepas tanpa satu pun galat.
///
/// 2. Sebaliknya, CNAME berisi domain yang DNS-nya belum siap membuat
///    Pages berhenti melayani alamat github.io dan mengalihkannya ke
///    domain yang belum hidup. Situsnya mati total, dan itu sudah
///    pernah terjadi. Jadi CNAME dan DNS harus siap bersamaan — bukan
///    CNAME dulu.
///
/// 3. Seluruh TLD `.app` ada di daftar HSTS preload peramban: tidak ada
///    `http://` sama sekali. Sebelum sertifikatnya jadi, alamatnya
///    tidak bisa dibuka — bukan terbuka tanpa kunci.
///
/// Dan pindahnya mengubah alamat landing page juga, karena situs proyek
/// dilayani di bawah domain situs pengguna — lihat
/// `SetelanPlatformRepository.tautanSitusBawaan`.
const kAlamatWeb = 'https://bujejuki-spec.github.io/';

/// Isi QR meja: tautan, bukan teks biasa.
///
/// Bentuk lamanya `RESTO:<id>|TABLE:<n>` hanya berarti sesuatu bagi
/// pemindai di dalam aplikasi KaataGo. Dipindai kamera bawaan HP — yang
/// dipakai hampir semua orang yang belum memasang aplikasinya — hasilnya
/// cuma sebaris teks aneh tanpa satu pun tombol untuk melanjutkan.
///
/// Sebagai tautan, kamera bawaan menawarkan membukanya, dan yang membuka
/// langsung sampai di menu meja itu tanpa memasang apa pun.
String tautanMeja(String restoId, String meja) {
  final u = Uri.parse(kAlamatWeb);
  return u.replace(queryParameters: {
    ...u.queryParameters,
    'resto': restoId,
    'meja': meja,
  }).toString();
}

/// Membaca isi QR meja, bentuk baru maupun lama.
///
/// Bentuk lamanya tetap diterima selamanya. Stiker yang sudah tertempel
/// di meja tidak ikut berubah saat aplikasinya diperbarui, dan merchant
/// yang mencetaknya tahun lalu tidak punya alasan mencetak ulang —
/// menolaknya berarti membuat meja yang tadinya bisa dipakai jadi tidak
/// bisa, tanpa satu pun perubahan di meja itu.
({String restoId, String meja})? bacaTautanMeja(String mentah) {
  final teks = mentah.trim();

  final lama = RegExp(r'^RESTO:([^|]+)\|TABLE:(.+)$').firstMatch(teks);
  if (lama != null) {
    return (restoId: lama.group(1)!.trim(), meja: lama.group(2)!.trim());
  }

  final u = Uri.tryParse(teks);
  if (u == null || !u.hasScheme) return null;
  final resto = u.queryParameters['resto']?.trim();
  final meja = u.queryParameters['meja']?.trim();
  if (resto == null || resto.isEmpty || meja == null || meja.isEmpty) {
    return null;
  }
  return (restoId: resto, meja: meja);
}
