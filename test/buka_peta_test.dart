import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Membuka peta seharusnya membuka aplikasi petanya, bukan tab peramban
/// yang memuat ulang seluruh Google Maps versi web.
void main() {
  final sumber = File('lib/utils/resto_location.dart').readAsStringSync();

  group('openInMaps', () {
    // geo: dijawab langsung oleh aplikasi peta yang terpasang.
    test('mencoba skema geo lebih dulu', () {
      expect(sumber, contains("Uri.parse('geo:"));
      final geo = sumber.indexOf("Uri.parse('geo:");
      final web = sumber.indexOf("Uri.https('www.google.com'");
      expect(web, lessThan(geo),
          reason: 'tautan web disiapkan dulu, tapi geo: yang dicoba duluan');
      expect(sumber.indexOf('return launchUrl(web'), greaterThan(geo));
    });

    // Google Maps memperlakukan id tempat kosong sebagai id yang tidak
    // ditemukan: halamannya terbuka, petanya kosong.
    test('tidak mengirim query_place_id kosong', () {
      // Bentuk parameternya yang diperiksa, bukan katanya — kata itu
      // masih ada di komentar yang menjelaskan kenapa ia dibuang.
      expect(sumber, isNot(contains("'query_place_id':")));
    });

    // iOS tidak mengenal geo:, dan web jelas tidak.
    test('masih punya jalan lewat peramban', () {
      expect(sumber, contains('if (!kIsWeb)'));
      expect(sumber, contains('return launchUrl(web'));
    });

    // externalApplication di web berarti window.open, dan tab baru
    // itulah halaman kosongnya — sering ditahan penghalang popup, dan
    // kalaupun lolos, Android tidak menyerahkannya ke aplikasi Maps.
    test('di web memindahkan tab yang ada, bukan membuka tab baru', () {
      expect(sumber, contains("webOnlyWindowName: '_self'"));
      final web = sumber.indexOf('if (kIsWeb) {');
      expect(web, greaterThan(0));
      final cabang = sumber.substring(web, sumber.indexOf('}', web));
      expect(cabang, isNot(contains('LaunchMode.externalApplication')));
    });

    test('nama resto jadi label pin, bukan dibuang', () {
      expect(sumber, contains('Uri.encodeComponent(nama)'));
    });
  });

  // Sejak Android 11, canLaunchUrl menjawab "tidak ada" untuk skema yang
  // tidak disebutkan di manifes — pada HP yang jelas punya Google Maps.
  test('manifes menyebut skema geo di <queries>', () {
    final manifes =
        File('android/app/src/main/AndroidManifest.xml').readAsStringSync();
    final blok = manifes.substring(
        manifes.indexOf('<queries>'), manifes.indexOf('</queries>'));
    expect(blok, contains('android:scheme="geo"'));
    expect(blok, contains('android.intent.action.VIEW'));
  });
}
