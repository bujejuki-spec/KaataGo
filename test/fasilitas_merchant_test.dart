import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pos_app/models/restaurant.dart';

void main() {
  group('fasilitas', () {
    test('terbaca dari daftar Postgres', () {
      final r = Restaurant.fromMap('r1', {
        'name': 'Kaata',
        'facilities': ['AC', 'Live Music'],
      });
      expect(r.facilities, ['AC', 'Live Music']);
    });

    test('terbaca dari teks JSON sqflite', () {
      // Kolom yang sama sampai dalam bentuk berbeda tergantung dari mana
      // barisnya datang.
      final r = Restaurant.fromMap('r1', {
        'name': 'Kaata',
        'facilities': '["AC","WiFi Gratis"]',
      });
      expect(r.facilities, ['AC', 'WiFi Gratis']);
    });

    test('isi rusak tidak menjatuhkan seluruh barisnya', () {
      final r = Restaurant.fromMap('r1', {
        'name': 'Kaata',
        'facilities': 'bukan json',
      });
      expect(r.facilities, isEmpty);
    });

    test('yang kosong dibuang, bukan jadi kartu hampa', () {
      final r = Restaurant.fromMap('r1', {
        'name': 'Kaata',
        'facilities': ['AC', '  ', ''],
      });
      expect(r.facilities, ['AC']);
    });

    test('ikut terkirim saat disimpan', () {
      final r = Restaurant(
          id: 'r1', name: 'Kaata', address: 'Jl', facilities: const ['AC']);
      expect(r.toMap()['facilities'], ['AC']);
    });

    test('kolomnya bawaan daftar kosong, bukan null', () {
      final sql =
          File('supabase/resto_facilities.sql').readAsStringSync();
      expect(sql, contains("default '[]'::jsonb"));
      expect(sql, contains('not null'));
    });

    test('daftarnya bebas, bukan pilihan tetap', () {
      // Daftar yang menghambat pemiliknya menggambarkan tempatnya
      // sendiri lebih buruk daripada daftar yang sesekali salah ketik.
      final sql = File('supabase/resto_facilities.sql').readAsStringSync();
      expect(sql, isNot(contains('create table facilities')));
      expect(sql, isNot(contains('check (facilities')));
    });
  });

  group('di layar', () {
    test('bisa disunting di Info Merchant', () {
      final layar =
          File('lib/screens/restaurant_info_screen.dart').readAsStringSync();
      expect(layar, contains('_fasilitas'));
      expect(layar, contains('_fasilitasUmum'));
      expect(layar, contains('facilities: List<String>.from(_fasilitas)'));
    });

    test('yang sama tidak masuk dua kali', () {
      final layar =
          File('lib/screens/restaurant_info_screen.dart').readAsStringSync();
      expect(layar, contains('f.toLowerCase() == teks.toLowerCase()'));
    });

    test('tampil berwarna di daftar pilih merchant', () {
      // Keterangan yang sepucat alamat akan terlewat oleh mata yang
      // sedang menyapu daftar.
      final daftar =
          File('lib/screens/restaurant_list_screen.dart').readAsStringSync();
      expect(daftar, contains('_FasilitasChip'));
      expect(daftar, contains('resto.facilities.take(4)'));
    });

    test('warnanya tetap sama untuk fasilitas yang sama', () {
      // Diacak tiap gambar berarti mata harus membaca ulang tiap baris.
      final daftar =
          File('lib/screens/restaurant_list_screen.dart').readAsStringSync();
      expect(daftar, contains('nama.toLowerCase().hashCode.abs() % _palet.length'));
    });
  });

  group('penggantian kata', () {
    test('teks yang dilihat pengguna memakai merchant', () {
      final beranda =
          File('lib/screens/restaurant_list_screen.dart').readAsStringSync();
      expect(beranda, contains('Merchant'));
    });

    test('nama kolom dan pengenal tidak ikut berubah', () {
      // resto_id ada di seluruh basis data; menggantinya berarti migrasi
      // yang menyentuh hampir tiap tabel.
      final repo = File('lib/db/order_repository.dart').readAsStringSync();
      expect(repo, contains('resto_id'));
    });
  });
}
