import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Shift kasir: siapa yang boleh menutup, dan apa yang terbuka sebelum
/// shiftnya dibuka.
void main() {
  final sql = File('supabase/tutup_shift_sendiri.sql').readAsStringSync();
  final layar =
      File('lib/screens/cashier_shift_screen.dart').readAsStringSync();
  final beranda =
      File('lib/screens/kasir_home_screen.dart').readAsStringSync();
  final repo =
      File('lib/db/cashier_shift_repository.dart').readAsStringSync();

  group('yang membuka, itu yang menutup', () {
    // Menutup shift berarti menghitung uang laci dan menandatangani
    // selisihnya — dan selisih itu tercatat atas nama kasirnya, lalu
    // jadi tagihan atas namanya kalau kurang. Atasan yang menutup shift
    // orang lain membuat tagihan atas nama orang yang tidak ada di sana
    // saat uangnya dihitung.
    test('atasan pun tidak bisa menutup shift orang lain', () {
      expect(sql, contains("lower(v_email) <> lower(coalesce(v_shift.employee_email, ''))"));
      final blok = sql.substring(sql.indexOf('create or replace function close_shift'));
      expect(blok, isNot(contains("array['owner', 'finance', 'admin']")));
    });

    test('pesannya menyebut siapa yang bisa menutupnya', () {
      expect(sql, contains('Hanya dia yang bisa menutupnya'));
    });

    test('tombol tutupnya hilang untuk shift orang lain', () {
      expect(layar, contains('_shiftMilikSaya'));
      expect(layar,
          contains('(s != null && !_shiftMilikSaya)'));
    });

    // Tanpa kalimat ini, Owner yang membuka layar ini mengira tombolnya
    // hilang karena rusak.
    test('alasannya dikatakan, bukan cuma tombolnya hilang', () {
      expect(layar, contains('yang bisa menutup shift ini'));
    });
  });

  group('riwayatnya sehari, bukan seluruhnya', () {
    test('tanggalnya wajib disebut saat meminta', () {
      expect(repo, contains('required DateTime tanggal'));
      expect(repo, contains("gte('opened_at'"));
      expect(repo, contains("lt('opened_at'"));
    });

    // Shift yang ditutup jam sebelas malam tercatat hari itu juga,
    // bukan besok.
    test('batas harinya WIB, bukan UTC', () {
      expect(repo, contains('const Duration(hours: 7)'));
    });

    test('layarnya mulai dari hari ini dan punya pemilih tanggal', () {
      expect(layar, contains('_tanggalRiwayat = DateTime.now()'));
      expect(layar, contains('showDatePicker'));
      expect(layar, contains('Kembali ke hari ini'));
    });
  });

  group('beranda kasir menunggu shift dibuka', () {
    test('hanya tiga hal sebelum shiftnya ada', () {
      expect(beranda, contains('bool? _shiftSaya'));
      expect(beranda, contains('if (_shiftSaya == true)'));
      // Kotak masuk dan keluar berada di luar gerbangnya.
      final gerbang = beranda.substring(
          beranda.indexOf('if (_shiftSaya == true)'),
          beranda.indexOf('const InboxTile()'));
      expect(gerbang, isNot(contains("title: 'Keluar'")));
    });

    // Menu yang sempat muncul lalu hilang sendiri lebih membingungkan
    // daripada menu yang datang belakangan.
    test('selama belum diketahui, yang tampil tetap yang sempit', () {
      expect(beranda, contains('bool? _shiftSaya;'));
    });

    // Kasir yang jaringannya sedang buruk tetap harus bisa bekerja.
    test('gagal bertanya tidak mengunci', () {
      final blok = beranda.substring(beranda.indexOf('Future<void> _periksaShift'),
          beranda.indexOf('@override', beranda.indexOf('Future<void> _periksaShift')));
      expect(blok, contains('_shiftSaya = true'));
    });

    // Keterangannya pindah ke pil mengambang: keterangan yang ikut
    // tergulir hilang bersama daftarnya, padahal ia yang menjelaskan
    // kenapa daftarnya pendek.
    test('alasannya dijelaskan di pil mengambangnya', () {
      final pil =
          File('lib/widgets/shift_berjalan_banner.dart').readAsStringSync();
      expect(pil, contains('Buka shift dulu'));
    });
  });
}
