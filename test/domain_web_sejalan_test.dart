import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Alamat web pelanggan dan berkas CNAME harus bercerita hal yang sama.
///
/// Keduanya pernah tidak sama, dan dua arahnya sama-sama mematikan —
/// karena itu yang dijaga di sini dua-duanya, bukan satu.
///
/// ── Arah pertama: CNAME ada, DNS-nya belum ───────────────────────────
///
/// Berkas `CNAME` berisi domain yang belum mengarah ke GitHub membuat
/// Pages BERHENTI melayani alamat bawaannya dan mengalihkan ke domain
/// yang belum hidup. Situsnya mati total — `bujejuki-spec.github.io`
/// menjawab 404 dan setiap QR meja yang dipindai pelanggan gagal.
///
/// Itu sudah terjadi sekali, dan tidak ada satu pun galat yang
/// menyertainya: build sukses, deploy sukses, situs mati.
///
/// ── Arah kedua: domainnya pindah, CNAME-nya hilang ───────────────────
///
/// `.github/workflows/web.yml` menerbitkan situsnya dengan `git init`
/// lalu `push --force` — ia MENGGANTI seluruh isi repo situs. CNAME
/// yang dipasang lewat UI GitHub hilang pada deploy berikutnya, dan QR
/// yang sudah TERCETAK DAN TERTEMPEL menunjuk ke domain yang tidak lagi
/// dilayani siapa pun.
///
/// Jadi: kalau `kAlamatWeb` memakai domain sendiri, workflow WAJIB
/// menulis CNAME yang sama. Kalau ia memakai alamat github.io bawaan,
/// workflow WAJIB tidak menulis CNAME sama sekali.
void main() {
  String baca(String jalur) => File(jalur).readAsStringSync();

  final tautan = baca('lib/utils/tautan_meja.dart');
  final alur = baca('.github/workflows/web.yml');

  String alamatWeb() {
    final m = RegExp(r"const kAlamatWeb = '([^']+)'").firstMatch(tautan);
    expect(m, isNotNull, reason: 'kAlamatWeb tidak ditemukan');
    return m!.group(1)!;
  }

  /// Host yang dituliskan workflow ke berkas CNAME, atau null kalau ia
  /// memang tidak menulisnya.
  ///
  /// Hanya baris yang benar-benar dijalankan. Contoh di dalam komentar
  /// — dan komentar di berkas itu memang memuat contohnya untuk nanti —
  /// bukan langkah, dan membacanya sebagai langkah berarti penjaga ini
  /// menuduh berdasarkan catatan.
  String? hostCname() {
    for (final b in alur.split('\n')) {
      final t = b.trim();
      if (t.startsWith('#')) continue;
      final m = RegExp(r"echo '([^']+)' > build/web/CNAME").firstMatch(t);
      if (m != null) return m.group(1);
    }
    return null;
  }

  test('alamatnya https, bukan http', () {
    // Domain `.app` ada di daftar HSTS preload peramban: `http://`
    // ditolak sebelum permintaannya dikirim, jadi stiker dengan tautan
    // http tidak bisa dibuka sama sekali.
    expect(Uri.parse(alamatWeb()).scheme, 'https');
  });

  test('alamat bawaan github.io berarti TIDAK ada CNAME', () {
    final host = Uri.parse(alamatWeb()).host;
    if (!host.endsWith('.github.io')) return;

    expect(hostCname(), isNull,
        reason: 'kAlamatWeb masih memakai $host, tapi workflow menulis '
            'CNAME "${hostCname()}". Pages akan berhenti melayani $host '
            'dan mengalihkan ke domain itu — kalau DNS-nya belum '
            'mengarah ke GitHub, situsnya mati dan semua QR meja gagal.');
  });

  test('domain sendiri berarti CNAME ada DAN sama persis', () {
    final host = Uri.parse(alamatWeb()).host;
    if (host.endsWith('.github.io')) return;

    expect(hostCname(), isNotNull,
        reason: 'kAlamatWeb memakai $host, tapi workflow tidak menulis '
            'CNAME. Domainnya akan lepas pada deploy berikutnya, karena '
            'langkah dorongnya mengganti seluruh isi repo situs.');
    expect(hostCname(), host,
        reason: 'QR meja menunjuk ke satu domain, situsnya diterbitkan '
            'untuk domain lain');
  });

  test('kalau CNAME ditulis, ia ditulis SEBELUM langkah dorongnya', () {
    if (hostCname() == null) return;
    final posisiCname = alur.indexOf('> build/web/CNAME');
    final posisiDorong = alur.indexOf('Dorong ke repo situs');
    expect(posisiCname, lessThan(posisiDorong),
        reason: 'ditulis sesudah dorong berarti tidak pernah ikut '
            'terdorong — berkasnya ada di runner, tidak ada di repo situs');
  });

  test('bentuk QR lama tetap dibaca', () {
    // Stiker yang tercetak sebelum tautannya berbentuk URL memakai
    // `RESTO:<id>|TABLE:<n>`. Alamatnya berubah tidak boleh ikut
    // mematikan stiker yang bentuknya lebih tua lagi.
    expect(tautan, contains(r'^RESTO:([^|]+)\|TABLE:(.+)$'));
  });
}
