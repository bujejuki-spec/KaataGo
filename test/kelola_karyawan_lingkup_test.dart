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
  //
  // Diperiksa PER PERAN, bukan dengan menghitung jumlah kemunculannya.
  //
  // Dulu tes ini menuntut angkanya tepat tiga. Angka itu benar saat
  // ditulis, lalu merah pada hari peran HR mendapat konsol webnya —
  // padahal yang terjadi justru penambahan, bukan kehilangan. Dan
  // sebaliknya: memindahkan menunya dari Admin ke peran lain tetap
  // menghasilkan tiga, jadi angka itu tidak pernah benar-benar menjaga
  // apa yang dimaksud judulnya.
  group('menunya ada di sidebar peran yang mengurus karyawan', () {
    /// Isi satu daftar menu, dipotong dari deklarasinya sampai penutupnya.
    String daftar(String nama) {
      final mulai = menu.indexOf('const $nama = <MenuWeb>[');
      expect(mulai, greaterThan(-1), reason: 'Daftar menu $nama tidak ada.');
      return menu.substring(mulai, menu.indexOf('\n];', mulai));
    }

    for (final peran in ['_superAdmin', '_owner', '_admin', '_hr']) {
      test('$peran punya Kelola Karyawan', () {
        expect(daftar(peran), contains("judul: 'Kelola Karyawan'"));
      });
    }

    // Finance mengurus uang, bukan orang. Batas itu ditegakkan RLS juga,
    // dan menu yang menawarkannya cuma menyodorkan layar yang isinya
    // akan ditolak server.
    test('_finance tidak punya Kelola Karyawan', () {
      expect(daftar('_finance'), isNot(contains("judul: 'Kelola Karyawan'")));
    });
  });
}
