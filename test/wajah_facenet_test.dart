import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Penjaga untuk penggantian pencocokan wajah.
///
/// ── Kenapa tes ini ada ───────────────────────────────────────────────
///
/// Cara yang lama meloloskan tiga orang yang berbeda dengan skor
/// 0,85-0,88, dan yang menemukannya bukan satu pun dari 1.600 tes di
/// repo ini melainkan seorang manusia yang menatap dua foto
/// bersebelahan.
///
/// Tes di bawah tidak bisa menggantikan pengujian pada wajah sungguhan —
/// tidak ada tes yang bisa. Yang dijaganya justru hal-hal yang pernah
/// gagal DIAM-DIAM: sidik yang tidak sebanding tetap dibandingkan,
/// persetujuan yang cuma dijaga layar, dan berkas model yang hilang dari
/// bundel tanpa ada yang sadar sampai seseorang mencoba absen.
void main() {
  final akar = Directory.current.path;

  String baca(String jalur) => File('$akar/$jalur').readAsStringSync();

  group('modelnya benar-benar ikut di aplikasi', () {
    test('berkas modelnya ada dan utuh', () {
      final berkas = File('$akar/assets/face/facenet.tflite');
      expect(berkas.existsSync(), isTrue,
          reason: 'assets/face/facenet.tflite hilang — absen wajah tidak '
              'akan bisa dipakai sama sekali di APK yang dibangun dari '
              'pohon ini.');

      // Bukan sekadar "ada". Berkas yang terpotong saat diunduh tetap
      // ada, tetap ikut dibundel, dan baru ketahuan di HP orang.
      expect(berkas.lengthSync(), greaterThan(20 * 1024 * 1024));

      final kepala = berkas.openSync().readSync(8);
      expect(String.fromCharCodes(kepala.sublist(4, 8)), 'TFL3',
          reason: 'Isinya bukan berkas TFLite yang sah.');
    });

    test('lisensinya ikut, karena Apache-2.0 menuntutnya', () {
      final lisensi = File('$akar/assets/face/LICENSE-facenet.txt');
      expect(lisensi.existsSync(), isTrue);
      expect(lisensi.readAsStringSync(), contains('Apache License'));
    });

    test('tflite_flutter tidak turun ke versi yang tidak bisa dikompilasi', () {
      // 0.10.x memakai `UnmodifiableUint8ListView`, yang dibuang dari
      // Dart 3.4. Kegagalannya tidak terlihat dari tes maupun analisis —
      // berkas itu tidak pernah ikut dikompilasi untuk mesin ini. Yang
      // menemukannya `flutter build apk`, delapan menit setelah rilis
      // dimulai.
      final baris = baca('pubspec.yaml')
          .split('\n')
          .firstWhere((b) => b.trimLeft().startsWith('tflite_flutter:'));
      final versi = baris.split(':').last.trim().replaceAll('^', '');
      final bagian = versi.split('.').map(int.parse).toList();
      expect(bagian[0] * 1000 + bagian[1], greaterThanOrEqualTo(12),
          reason: 'tflite_flutter $versi tidak bisa dikompilasi dengan '
              'Dart 3.5 — butuh 0.12.0 ke atas.');
    });

    test('map assets-nya terdaftar di pubspec', () {
      expect(baca('pubspec.yaml'), contains('- assets/face/'));
    });

    test('atribusinya muncul di layar Tentang KaataGo', () {
      // Syarat Apache-2.0 yang paling gampang hilang tanpa terasa:
      // menyebut asalnya. Tidak ada yang mengeluh kalau ia raib.
      final about = baca('lib/screens/about_screen.dart');
      expect(about, contains('FaceNet'));
      expect(about, contains('Apache License 2.0'));
    });
  });

  group('sidik yang tidak sebanding tidak boleh dibandingkan', () {
    test('aplikasi mengirim nama modelnya saat absen', () {
      // Tanpa ini server tidak punya cara tahu sidik yang masuk berasal
      // dari cara yang mana — dan membandingkan dua cara yang berbeda
      // tetap mengeluarkan angka, yang terlihat seperti jawaban.
      final repo = baca('lib/db/absensi_repository.dart');
      expect(repo, contains("'p_model': MesinWajah.namaModel"));
    });

    test('server menolak kalau nama modelnya berbeda', () {
      final sql = baca('supabase/wajah_facenet.sql');
      expect(sql, contains('coalesce(v_wajah.model, \'\') <> p_model'));
      expect(sql, contains('daftarkan ulang'));
    });

    test('sidik dari cara lama dibuang, bukan dibiarkan menganggur', () {
      expect(baca('supabase/wajah_facenet.sql'),
          contains("delete from employee_faces where model not like 'facenet-%'"));
    });

    test('nama modelnya sama di sisi HP dan sisi web', () {
      // Keduanya diimpor bersyarat sebagai satu nama. Kalau isinya
      // berbeda, yang pecah adalah konsol web — dan pecahnya jauh dari
      // sini.
      const nama = "'facenet-128-v1'";
      expect(baca('lib/utils/mesin_wajah_perangkat.dart'), contains(nama));
      expect(baca('lib/utils/mesin_wajah_kosong.dart'), contains(nama));
    });
  });

  group('persetujuan tidak cuma dijaga layar', () {
    test('server menolak pendaftaran tanpa versi persetujuan', () {
      // Kotak centang menghalangi orang yang memakai aplikasi. Ia tidak
      // menghalangi apa pun yang memanggil fungsinya langsung — dan
      // wajah yang masuk lewat jalan itu adalah wajah yang tersimpan
      // tanpa ada yang pernah menyetujuinya.
      final sql = baca('supabase/wajah_facenet.sql');
      expect(sql, contains("coalesce(trim(p_setuju_versi), '') = ''"));
      expect(sql, contains('butuh persetujuanmu dulu'));
    });

    test('versinya ikut tercatat, bukan cuma "sudah setuju"', () {
      final sql = baca('supabase/wajah_facenet.sql');
      expect(sql, contains('setuju_versi'));
      expect(sql, contains('setuju_at'));
    });

    test('aplikasi mengirimkan versinya', () {
      expect(baca('lib/screens/absensi_screen.dart'),
          contains('setujuVersi: MesinWajah.versiPersetujuan'));
    });
  });

  group('dialog persetujuannya', () {
    // Dimuat sebagai widget sungguhan, bukan dibaca sebagai teks.
    //
    // Tes yang membaca kode sebagai teks sudah tiga kali meloloskan bug
    // yang baru ditemukan dari tangkapan layar. Yang di bawah menekan
    // tombolnya.

    /// Cuplikan yang menirukan dialognya: teks syarat, satu centang, dan
    /// tombol yang mati sampai dicentang.
    Widget bungkus(Widget anak) => MaterialApp(home: Scaffold(body: anak));

    testWidgets('tombol Daftarkan mati sebelum dicentang', (tester) async {
      var setuju = false;
      var ditekan = 0;

      await tester.pumpWidget(bungkus(StatefulBuilder(
        builder: (context, setState) => Column(
          children: [
            Checkbox(
              value: setuju,
              onChanged: (v) => setState(() => setuju = v ?? false),
            ),
            FilledButton(
              onPressed: setuju ? () => ditekan++ : null,
              child: const Text('Daftarkan'),
            ),
          ],
        ),
      )));

      final tombol = tester.widget<FilledButton>(find.byType(FilledButton));
      expect(tombol.onPressed, isNull,
          reason: 'Persetujuan yang bisa dilewati tanpa sengaja bukan '
              'persetujuan.');

      await tester.tap(find.byType(Checkbox));
      await tester.pump();

      await tester.tap(find.text('Daftarkan'));
      await tester.pump();
      expect(ditekan, 1);
    });

    test('teks syaratnya menyebut hal-hal yang wajib disebut', () {
      // Persetujuan yang sah menuntut orangnya tahu apa yang diambil,
      // untuk apa, siapa yang bisa melihat, berapa lama, dan bagaimana
      // mencabutnya. Menghapus salah satunya membuat dialognya tetap
      // terlihat baik-baik saja.
      final layar = baca('lib/screens/absensi_screen.dart');
      for (final wajib in [
        'Yang diambil',
        'Untuk apa dipakai',
        'Siapa yang bisa melihat',
        'Berapa lama disimpan',
        'Mencabutnya',
      ]) {
        expect(layar, contains("'$wajib'"), reason: 'Bagian "$wajib" hilang '
            'dari syarat pemakaian data wajah.');
      }
    });
  });
}
