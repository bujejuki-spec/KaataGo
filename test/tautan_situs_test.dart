import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pos_app/db/setelan_platform_repository.dart';

/// Tautan situs KaataGo disetel dari KaataGo Admin, bukan ditulis mati.
void main() {
  group('tautan yang sah', () {
    // Tautan ini dibuka apa adanya oleh setiap HP yang membaca layar
    // Tentang — termasuk dari halaman login, oleh orang yang belum punya
    // akun dan belum punya alasan untuk curiga.
    test('https diterima', () {
      expect(
          SetelanPlatformRepository.tautanSah(
              'https://bujejuki-spec.github.io/KaataGo-LandingPage/'),
          isTrue);
      expect(SetelanPlatformRepository.tautanSah('https://kaatago.id'), isTrue);
    });

    test('yang bukan https ditolak', () {
      for (final t in [
        'http://kaatago.id',
        'javascript:alert(1)',
        'kaatago.id',
        'https://',
        'https://kaata go.id',
        '',
      ]) {
        expect(SetelanPlatformRepository.tautanSah(t), isFalse, reason: t);
      }
    });

    test('bawaannya sendiri sah', () {
      // Bawaan yang tidak lolos pemeriksaannya sendiri berarti tombolnya
      // rusak persis pada saat basis data tidak bisa dibaca.
      expect(
          SetelanPlatformRepository.tautanSah(
              SetelanPlatformRepository.tautanSitusBawaan),
          isTrue);
    });
  });

  group('dijaga di basis data juga', () {
    final sql = File('supabase/setelan_platform.sql').readAsStringSync();

    test('cuma KaataGo Admin yang bisa mengubah', () {
      // Tautan yang bisa diubah merchant bisa diarahkan ke halaman palsu
      // yang meminta kata sandi, dari dalam aplikasi resmi.
      expect(sql, contains('with check (is_super_admin())'));
    });

    test('bisa dibaca sebelum login', () {
      expect(sql, contains('grant select on setelan_platform to anon'));
    });

    test('https dipaksa di basis data, bukan cuma di layar', () {
      expect(sql, contains("nilai ~ '^https://"));
    });
  });

  test('layar Tentang tidak lagi menulis tautannya mati', () {
    final about = File('lib/screens/about_screen.dart').readAsStringSync();
    expect(about, contains('SetelanPlatformRepository().tautanSitus()'));
    expect(about, isNot(contains("static const _url =")));
  });
}
