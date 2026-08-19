import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Catatan rilis dan penamaan berkas APK.
void main() {
  Map<String, dynamic> jalankan(String versi) {
    final hasil = Process.runSync('python3', [
      'scripts/catatan_rilis.py',
      'docs/CATATAN-RILIS.md',
      versi,
    ]);
    expect(hasil.exitCode, 0, reason: hasil.stderr.toString());
    return jsonDecode(hasil.stdout.toString()) as Map<String, dynamic>;
  }

  group('catatan rilis', () {
    test('versi yang punya catatannya membawa poin-poinnya', () {
      final j = jalankan('2.8.0');
      expect(j['version'], '2.8.0');
      expect(j['body'], contains('Yang berubah:'));
      expect(j['body'], contains('Nomor pesanan harian'));
    });

    test('tidak membawa catatan versi lain', () {
      // Judul berikutnya menutup bagiannya; tanpa itu catatan versi lama
      // ikut terbawa ke pengumuman versi baru.
      final j = jalankan('2.8.0');
      expect(j['body'], isNot(contains('Super Admin dan Owner yang belum')));
    });

    test('versi tanpa catatan tetap terbit, tanpa body', () {
      // Menahan rilis karena catatannya belum ditulis menukar
      // ketidaknyamanan kecil dengan satu rilis yang gagal terbit.
      final j = jalankan('9.9.9');
      expect(j['version'], '9.9.9');
      expect(j.containsKey('body'), isFalse);
    });

    test('keluarannya JSON yang sah untuk dikirim apa adanya', () {
      final j = jalankan('2.7.0');
      expect(j['body'], isA<String>());
    });

    test('dipakai skrip rilisnya', () {
      final sh = File('scripts/release.sh').readAsStringSync();
      expect(sh, contains('scripts/catatan_rilis.py'));
      expect(sh, contains('-d "\$ANNOUNCE_BODY"'));
    });
  });

  group('nama berkas APK', () {
    final rilis = File('scripts/github_release.py').readAsStringSync();
    final sh = File('scripts/release.sh').readAsStringSync();

    test('diunggah dengan nomor versinya', () {
      // Folder unduhan berisi lima "KaataGo.apk (3)" tidak memberi tahu
      // siapa pun mana yang terbaru.
      expect(rilis, contains('f"KaataGo-{versi}.apk"'));
    });

    test('nama tetapnya ikut diunggah supaya tautan lama tidak mati', () {
      expect(rilis, contains('"KaataGo.apk"'));
      expect(rilis, contains('for nama in ('));
    });

    test('tautan di web menunjuk yang bernomor versi', () {
      expect(sh, contains("KaataGo-{version}.apk"));
      expect(sh, contains("var APK_URL"));
    });

    test('penanda tautannya diperiksa sebelum ditulis ulang', () {
      // Penanda yang hilang berarti halamannya diam-diam terus menunjuk
      // versi lama.
      expect(sh, contains("'var APK_URL'"));
    });
  });
}
