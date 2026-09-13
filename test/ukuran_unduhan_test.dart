import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:pos_app/services/app_updater.dart';

/// Ukuran berkas yang ditampilkan ke orang dibaca dari unduhannya
/// sendiri, bukan ditulis tangan di layar.
///
/// ── Kenapa berkas ini ada ────────────────────────────────────────────
///
/// Layar pembaruan menyebut "sekitar 80 MB" selama berbulan-bulan
/// setelah APK-nya tumbuh jadi 154 MB. Angkanya ditulis tangan sebagai
/// bagian dari kalimat, jadi tidak ada satu pun yang menagihnya berubah
/// saat rilis berikutnya membengkak — bukan galat, bukan tes yang
/// merah, cuma kalimat yang diam-diam berhenti benar.
void main() {
  group('teks ukurannya', () {
    test('null selama panjangnya belum diketahui', () {
      final u = AppUpdater.instance;
      u.totalBytes = null;
      expect(u.ukuranTeks, isNull);
      u.totalBytes = 0;
      expect(u.ukuranTeks, isNull);
    });

    test('dibulatkan ke MB terdekat', () {
      final u = AppUpdater.instance;
      u.totalBytes = 161600000;
      expect(u.ukuranTeks, '154 MB');
      u.totalBytes = 81788928;
      expect(u.ukuranTeks, '78 MB');
      u.totalBytes = null;
    });
  });

  // Angka yang ditulis tangan tertinggal pada rilis berikutnya. Yang
  // boleh menyebut ukuran cuma yang membacanya dari unduhannya.
  test('tidak ada ukuran yang ditulis tangan di layar pembaruan', () {
    final angka = RegExp(r'\d+\s*MB');
    for (final jalur in [
      'lib/widgets/update_download_banner.dart',
      'lib/widgets/update_download_button.dart',
    ]) {
      final teks = File(jalur)
          .readAsLinesSync()
          // Komentar boleh menyebut angka sebagai contoh; yang tidak
          // boleh cuma yang benar-benar tampil di layar.
          .where((b) => !b.trimLeft().startsWith('//') &&
              !b.trimLeft().startsWith('///'))
          .join('\n');
      expect(angka.hasMatch(teks), isFalse,
          reason: '$jalur menulis ukuran berkas sebagai teks tetap — '
              'pakai AppUpdater.ukuranTeks supaya ikut berubah sendiri');
    }
  });

  // Panjangnya dilaporkan terpisah dari kemajuannya: yang ditampilkan
  // bukan pecahan melainkan angka MB.
  test('unduhannya melaporkan panjang berkasnya', () {
    final apk = File('lib/utils/apk_updater.dart').readAsStringSync();
    expect(apk, contains('void Function(int? total)? onTotal'));
    expect(apk, contains('onTotal?.call(total)'));

    final app = File('lib/services/app_updater.dart').readAsStringSync();
    expect(app, contains('onTotal: (t)'));
    expect(app, contains('if (keadaan.total > 0) totalBytes = keadaan.total'));
  });
}
