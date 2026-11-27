import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Berkas gabungan tidak boleh membawa fungsi versi lama.
///
/// ── Masalah yang sebenarnya ──────────────────────────────────────────
///
/// 47 dari 161 fungsi di `supabase/` didefinisikan di lebih dari satu
/// berkas, dan itu memang gaya migrasi repo ini: tiap berkas menyatakan
/// ulang fungsi yang diubahnya, lalu yang terbaru menang menurut urutan
/// di `scripts/gabung_sql.sh`. Selama dijalankan berurutan dari atas,
/// hasilnya benar.
///
/// Yang berbahaya adalah berkas gabungan. Ia memuat SEBAGIAN berkas, di
/// luar urutan penuhnya. Begitu ia membawa `paket_langganan.sql` —
/// yang memuat `keadaan_langganan` versi lama — tanpa membawa
/// `hentikan_langganan.sql` yang menggantinya, menjalankannya
/// mengembalikan fungsi itu ke versi sebelum ada fitur berhenti
/// berlangganan.
///
/// Kemarin Postgres menolaknya, dan itu keberuntungan: bentuk
/// kembaliannya kebetulan sudah berbeda. Kalau yang berubah cuma isi
/// badannya, ia akan berjalan tanpa satu pun galat dan fiturnya mati
/// diam-diam.
///
/// Jadi yang dijaga di sini bukan duplikasinya — itu konvensinya —
/// melainkan gabungan yang membawa salinan yang sudah ada penggantinya.
void main() {
  /// Urutan jalannya berkas, menurut satu-satunya tempat yang
  /// menentukannya.
  List<String> urutan() {
    final sh = File('scripts/gabung_sql.sh').readAsStringSync();
    final awal = sh.indexOf('FILES=(');
    expect(awal, isNot(-1), reason: 'FILES=( tidak ditemukan');
    final blok = sh.substring(awal + 7, sh.indexOf('\n)', awal));
    return [
      for (final b in blok.split('\n'))
        if (b.trim().endsWith('.sql') && !b.trim().startsWith('#')) b.trim(),
    ];
  }

  final namaFungsi =
      RegExp(r'^create or replace function\s+([A-Za-z0-9_]+)\s*\(',
          multiLine: true);

  /// Siapa saja yang mendefinisikan sebuah fungsi.
  Map<String, List<String>> pendefinisi(List<String> berkas) {
    final hasil = <String, List<String>>{};
    for (final n in berkas) {
      final f = File('supabase/$n');
      if (!f.existsSync()) continue;
      for (final m in namaFungsi.allMatches(f.readAsStringSync())) {
        hasil.putIfAbsent(m.group(1)!, () => []).add(n);
      }
    }
    return hasil;
  }

  /// Judul bagian, satu-satunya bentuk yang diakui.
  ///
  /// Bentuknya ditentukan `scripts/gabung_sql.sh`, dan gabungan yang
  /// dirakit tangan mengikuti bentuk yang sama. Pola yang lebih longgar
  /// — sekadar nama berkas di awal baris — ikut menangkap baris prosa
  /// seperti "-- qris_statis.sql. Aman diulang.", dan penjaga yang
  /// salah menebak asal bagiannya akan melaporkan setiap fungsi sebagai
  /// basi sekaligus melewatkan yang betul-betul basi.
  final judulBagian =
      RegExp(r'^-- BAGIAN \d+ dari \d+ — ([a-z0-9_]+\.sql)', multiLine: true);

  final semuaGabungan = Directory('supabase')
      .listSync()
      .whereType<File>()
      .where((f) {
        final n = f.uri.pathSegments.last;
        return n.startsWith('GABUNGAN') || n.startsWith('JALANKAN');
      })
      .toList()
    ..sort((a, b) => b.statSync().modified.compareTo(a.statSync().modified));

  /// Gabungan yang menyebutkan berkas asalnya, jadi bisa ditelusuri.
  ///
  /// Beberapa potret lama ditulis tangan, bukan dirakit dari berkas, dan
  /// tidak menyebut asalnya sama sekali. Yang begitu tidak bisa
  /// diperiksa — dan memang tidak perlu: ia sudah dijalankan berbulan
  /// lalu dan tidak akan dijalankan ulang.
  bool bisaDitelusuri(File f) =>
      judulBagian.hasMatch(f.readAsStringSync());

  final gabungan = semuaGabungan.where(bisaDitelusuri).toList();

  test('yang terbaru selalu termasuk yang diperiksa', () {
    // Pengujian yang tidak menemukan apa pun untuk diperiksa akan lulus
    // selamanya tanpa pernah menguji apa pun. Dan yang paling perlu
    // dijaga justru gabungan yang baru dibuat — itu yang akan
    // dijalankan orang.
    expect(semuaGabungan, isNotEmpty);
    expect(gabungan, isNotEmpty);
    expect(
      semuaGabungan.first.uri.pathSegments.last,
      gabungan.first.uri.pathSegments.last,
      reason: 'gabungan terbaru tidak menyebut berkas asalnya, jadi tidak '
          'bisa diperiksa — beri tiap bagiannya judul "-- <berkas>.sql"',
    );
  });

  for (final f in gabungan) {
    final nama = f.uri.pathSegments.last;

    test('$nama tidak membawa fungsi yang sudah ada penggantinya', () {
      final berkas = urutan();
      final siapa = pendefinisi(berkas);
      final isi = f.readAsStringSync();

      // Berkas asal yang ikut ke dalam gabungan ini, dibaca dari judul
      // bagiannya. Judulnya boleh berketerangan ("— HANYA daftar
      // menunya"); yang diambil nama berkasnya saja.
      final bagian =
          judulBagian.allMatches(isi).map((m) => m.group(1)!).toSet();
      expect(bagian, isNotEmpty, reason: 'judul bagian tidak terbaca di $nama');

      final keluhan = <String>[];
      for (final m in namaFungsi.allMatches(isi)) {
        final fungsi = m.group(1)!;
        final semua = siapa[fungsi];
        if (semua == null || semua.isEmpty) continue;

        // Pemilik sahnya yang terakhir jalan.
        final pemilik = semua.last;
        if (bagian.contains(pemilik)) continue;

        keluhan.add('$fungsi — gabungan memakai salinan dari '
            '${semua.where(bagian.contains).join(", ")}, '
            'padahal $pemilik menggantinya sesudahnya');
      }

      expect(keluhan, isEmpty, reason: '\n  ${keluhan.join("\n  ")}\n');
    });

    test('$nama seimbang begin/commit-nya', () {
      // Tiap bagian membawa transaksinya sendiri, disengaja supaya satu
      // galat di bagian keenam tidak membatalkan lima yang sudah benar.
      // Yang ganjil berarti ada bagian yang terpotong saat dirakit.
      final isi = f.readAsStringSync();
      int hitung(String p) =>
          RegExp('^$p;', multiLine: true).allMatches(isi).length;
      expect(hitung('begin'), hitung('commit'), reason: nama);
    });
  }
}
