import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Pilihan tema pindah ke header, tepat di bawah barisan "Peran • email".
///
/// Sebelumnya ia satu menu bernama "Tampilan" di antara menu-menu kerja.
/// Yang mencarinya harus menggulir melewati kasir, keuangan, dan
/// pengelolaan untuk sampai ke sana — dan menemukannya di situ
/// menyiratkan ia sederajat dengan menutup shift.
void main() {
  const hub = [
    'super_admin_home_screen',
    'owner_home_screen',
    'kasir_home_screen',
    'customer_home_screen',
    'finance_home_screen',
    'admin_home_screen',
  ];

  final header = File('lib/widgets/hub_menu_tile.dart').readAsStringSync();
  final tombol =
      File('lib/widgets/language_theme_toggle.dart').readAsStringSync();

  test('headernya menampilkannya di bawah subtitle', () {
    final i = header.indexOf('if (subtitle != null)');
    final j = header.indexOf('if (tampilkanTema)');
    expect(j, greaterThan(i));
  });

  for (final layar in hub) {
    test('$layar menyalakannya', () {
      final isi = File('lib/screens/$layar.dart').readAsStringSync();
      expect(isi, contains('tampilkanTema: true'));
    });
  }

  // Dialog yang harus dibuka lalu ditutup tiap kali mencoba membuat
  // orang berhenti mencoba sebelum menemukan yang dia mau.
  test('langsung tiga tombol, bukan pintu ke dialog', () {
    expect(tombol, contains('class TemaHeader'));
    expect(tombol, contains('prefs.setThemeMode(mode)'));
    final mulai = tombol.indexOf('class TemaHeader');
    final blok = tombol.substring(mulai, tombol.indexOf('\nclass ', mulai + 1));
    expect(blok, isNot(contains('showAppearanceDialog')));
  });

  // Menu "Tampilan" tidak lagi berdiri sendiri di daftar menu — dua
  // tempat mengatur hal yang sama berarti yang satu suatu hari
  // ketinggalan.
  test('menu Tampilan tidak lagi mengulangnya', () {
    for (final layar in hub) {
      final isi = File('lib/screens/$layar.dart').readAsStringSync();
      expect(isi, isNot(contains('showAppearanceDialog')),
          reason: '$layar masih punya menu Tampilan sendiri');
    }
  });

  // Layar dapur menyala sepanjang hari menghadap juru masak, punya
  // bilah atasnya sendiri, dan tidak memakai HubHeader sama sekali.
  test('layar chef tidak ikut diubah', () {
    final chef = File('lib/screens/chef_home_screen.dart').readAsStringSync();
    expect(chef, isNot(contains('HubHeader')));
    expect(chef, contains('AppearanceIconButton()'));
  });
}
