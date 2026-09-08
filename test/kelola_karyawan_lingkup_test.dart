import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Kelola Karyawan untuk Owner dan Admin merchant.
///
/// Yang dijaga di sini bukan tampilannya melainkan batasnya: seorang
/// Admin tidak boleh menyentuh karyawan resto yang bukan miliknya, dan
/// tidak boleh mengangkat KaataGo Admin — peran yang tidak terikat
/// merchant mana pun, jadi memberikannya berarti memberi akses ke
/// seluruh merchant.
///
/// Penyaringan di layar bukan pengamanannya; RLS yang menegakkan. Yang
/// dijaga tes ini adalah keduanya tetap sejalan, supaya layarnya tidak
/// menawarkan pilihan yang pasti ditolak server.
void main() {
  final layar =
      File('lib/screens/employee_management_screen.dart').readAsStringSync();
  final menu = File('lib/screens/web_menu.dart').readAsStringSync();

  group('lingkupnya sebatas resto sendiri', () {
    test('daftarnya disaring menurut resto yang dipetakan', () {
      final blok = layar.substring(
          layar.indexOf('Future<void> _load()'), layar.indexOf('String _restoName'));
      expect(blok, contains('auth.isSuperAdmin'));
      expect(blok, contains('_restoSaya.contains(r.id)'));
      expect(blok, contains('_restoSaya.contains(e.restoId)'));
    });

    test('KaataGo Admin tidak tampil di sisi merchant', () {
      final blok = layar.substring(
          layar.indexOf('Future<void> _load()'), layar.indexOf('String _restoName'));
      expect(blok, contains('e.restoId != null'));
    });

    test('hanya KaataGo Admin yang bisa mengangkat KaataGo Admin', () {
      expect(layar, contains("widget.bolehSuperAdmin || e.key != 'super_admin'"));
      expect(layar, contains('bolehSuperAdmin: _semuaMerchant'));
    });
  });

  // Menu yang tidak ada berarti fiturnya tidak ada, seberapa pun benar
  // izinnya di server.
  test('menunya ada di sidebar Owner dan Admin, bukan cuma Super Admin', () {
    expect("judul: 'Kelola Karyawan'".allMatches(menu).length, 3);
  });
}
