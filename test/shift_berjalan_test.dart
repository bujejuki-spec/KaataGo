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
  // Letak dan geserannya diuji dengan benar-benar dipasang, bukan
  // dicocokkan sebagai teks — lihat shift_banner_terpasang_test.dart.
  //
  // Dua pengujian yang dulu berdiri di sini mencocokkan `bottom: _tepi`
  // dan `onPanUpdate:` sebagai potongan teks. Keduanya lulus pada versi
  // 3.9.0 yang justru menutupi seluruh layar dengan kotak galat: teksnya
  // memang ada, dan widgetnya memang tidak pernah digambar satu kali pun
  // oleh pengujian mana pun.
  test('penandanya dipasang lewat pembungkus yang bisa diuji sendiri', () {
    expect(banner, contains('PenandaMengambang('));
    expect(File('lib/widgets/penanda_mengambang.dart').existsSync(), isTrue);
  });

  // Kasir yang menu-menunya belum muncul mengira aplikasinya belum
  // selesai memuat, lalu menunggu sesuatu yang tidak akan datang.
  group('pil "buka shift dulu"', () {
    test('mengambang, bukan kartu yang ikut tergulir', () {
      expect(banner, contains('_PilMenunggu'));
      expect(
          File('lib/screens/kasir_home_screen.dart').readAsStringSync(),
          isNot(contains('class _MenungguShift')));
    });

    // Peran lain memang bekerja tanpa membuka shift.
    test('hanya untuk kasir', () {
      expect(banner, contains('auth.isKasir'));
      expect(banner, contains('kasir && shift.diketahui'));
    });

    // "Tidak ada shift" adalah jawaban; "belum sempat bertanya" bukan.
    test('menunggu jawabannya datang dulu', () {
      expect(kontrol, contains('bool get diketahui => _diketahui'));
      expect(kontrol, contains('_diketahui = true'));
    });
  });

  // Layar Shift Kasir bisa dibuka dari pilnya — dan waktu itu beranda
  // kasir tidak ikut dilewati saat kembali, jadi menunya tetap terbuka
  // padahal shiftnya sudah ditutup.
  test('beranda kasir ikut penandanya, bukan cuma memeriksa saat kembali',
      () {
    final beranda = File('lib/screens/kasir_home_screen.dart').readAsStringSync();
    expect(beranda, contains('ShiftBerjalan.instance.addListener(_ikutPenanda)'));
    expect(beranda,
        contains('ShiftBerjalan.instance.removeListener(_ikutPenanda)'));
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

  group('waktunya berdetak', () {
    // Timer satu menit yang dimulai sembarang waktu membuat angkanya
    // tertinggal sampai 59 detik — dan penanda yang terlihat berhenti
    // sebentar lalu melompat dua menit sekaligus terbaca seperti
    // aplikasi yang macet.
    test('detak pertamanya disetel ke pergantian menit', () {
      expect(banner, contains('lewat.inSeconds % 60'));
      expect(banner, contains('Timer.periodic(const Duration(minutes: 1)'));
    });

    // Tidak ada yang berdetak saat tidak ada yang perlu dihitung.
    test('timernya mati bersama pilnya', () {
      expect(banner, contains('_detak?.cancel()'));
      expect(banner, contains('void dispose()'));
    });
  });
}
