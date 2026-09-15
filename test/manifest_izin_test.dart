import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Penjaga untuk manifest Android.
///
/// Bentrokan manifest tidak terlihat dari `flutter analyze` maupun
/// `flutter test` — keduanya tidak pernah menggabungkan manifest. Yang
/// menemukannya `flutter build apk`, di tahap processReleaseMainManifest,
/// setelah Dart selesai dikompilasi: dua puluh menit lebih setelah rilis
/// dimulai.
void main() {
  final manifest =
      File('android/app/src/main/AndroidManifest.xml').readAsStringSync();

  test('izin menulis penyimpanan memenangkan nilai kita sendiri', () {
    // camera_android_camerax membawa WRITE_EXTERNAL_STORAGE dengan
    // maxSdkVersion 28. Tanpa tools:replace, Gradle menolak menggabungkan
    // dua nilai yang berbeda dan build-nya gagal.
    final awal = manifest.indexOf(
        'android:name="android.permission.WRITE_EXTERNAL_STORAGE"');
    expect(awal, greaterThan(-1));
    final elemen = manifest.substring(awal, manifest.indexOf('/>', awal));

    expect(elemen, contains('tools:replace="android:maxSdkVersion"'),
        reason: 'Tanpa tools:replace, manifest merger gagal karena paket '
            'camera membawa maxSdkVersion yang berbeda.');

    // 29, bukan 28: gal masih butuh izin ini di Android 10 untuk
    // menyimpan struk ke galeri.
    expect(elemen, contains('android:maxSdkVersion="29"'));
  });

  test('awalan tools dideklarasikan', () {
    // tools:replace tanpa xmlns:tools adalah galat XML — build tetap
    // gagal, cuma dengan pesan yang berbeda.
    expect(manifest,
        contains('xmlns:tools="http://schemas.android.com/tools"'));
  });
}
