import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Penanda mengambang "shift masih berjalan".
///
/// Shift dibuka pagi di layar Shift Kasir, lalu layar itu tidak dibuka
/// lagi sampai tutup toko. Penanda yang hanya ada di sana berarti tidak
/// ada yang mengingatkan — dan shift yang tidak ditutup membuat laci
/// tidak pernah dihitung, selisih harinya tidak pernah ketahuan, dan
/// kasir berikutnya tidak bisa membuka shiftnya sendiri.
void main() {
  final banner =
      File('lib/widgets/shift_berjalan_banner.dart').readAsStringSync();
  final kontrol = File('lib/utils/shift_berjalan.dart').readAsStringSync();
  final utama = File('lib/main.dart').readAsStringSync();
  final layar =
      File('lib/screens/cashier_shift_screen.dart').readAsStringSync();

  test('dipasang di atas Navigator, bukan di satu layar', () {
    expect(utama, contains('ShiftBerjalanBanner('));
    expect(utama, contains('builder: (context, child)'));
  });

  // Owner dan Admin bisa MEMBACA shift siapa pun. Penanda "shiftmu
  // masih berjalan" yang muncul untuk shift orang lain adalah ajakan
  // menutup sesuatu yang bukan haknya.
  test('hanya muncul untuk shift milik orang yang sedang masuk', () {
    expect(kontrol, contains('shift.employeeEmail.toLowerCase() =='));
    expect(kontrol, contains('emailSaya.toLowerCase()'));
  });

  // Menutup shift berarti menghitung uang laci lebih dulu. Tombol yang
  // menutupnya sekali ketuk melahirkan selisih yang tidak pernah
  // dihitung siapa pun.
  test('diketuk membuka layar Shift Kasir, bukan menutup langsung', () {
    expect(banner, contains('const CashierShiftScreen()'));
    expect(banner, isNot(contains('close_shift')));
    expect(banner, isNot(contains('.tutup(')));
  });

  // Bagian bawah layar sudah ditempati tombol Support, penanda
  // unduhan, dan tombol mengambang tiap layar.
  test('duduk di atas, supaya tidak bertumpuk dengan penanda lain', () {
    expect(banner, contains('top: 8'));
    expect(banner, contains('Alignment.topCenter'));
  });

  // Penanda yang hilang karena jaringan buruk mengajari orang
  // mengabaikannya.
  test('gagal bertanya tidak memadamkan penandanya', () {
    final blok = kontrol.substring(kontrol.indexOf('Future<void> segarkan'));
    final catchBlok = blok.substring(
        blok.indexOf('} catch (_) {'), blok.indexOf('void tandaiTutup'));
    expect(catchBlok, isNot(contains('_set(')));
  });

  test('layar Shift Kasir menyegarkan penandanya', () {
    expect(layar, contains('ShiftBerjalan.instance.segarkan'));
    expect(layar, contains('ShiftBerjalan.instance.tandaiTutup()'));
  });
}
