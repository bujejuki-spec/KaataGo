import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pos_app/models/cashier_shift.dart';

void main() {
  group('model shift', () {
    CashierShift buat(Map<String, dynamic> tambahan) => CashierShift.fromMap({
          'id': 's1',
          'resto_id': 'r1',
          'employee_email': 'andi@toko.com',
          'opened_at': '2026-08-22T01:00:00Z',
          'opening_cash': 200000,
          ...tambahan,
        });

    test('shift tanpa closed_at masih terbuka', () {
      expect(buat({}).terbuka, isTrue);
      expect(buat({'closed_at': '2026-08-22T09:00:00Z'}).terbuka, isFalse);
    });

    test('selisih nol berarti pas', () {
      expect(buat({'difference': 0}).pas, isTrue);
      expect(buat({'difference': -5000}).pas, isFalse);
      expect(buat({'difference': 5000}).pas, isFalse);
    });

    test('selisih minus berarti uangnya kurang', () {
      expect(buat({'difference': -5000}).kurang, isTrue);
      expect(buat({'difference': 5000}).kurang, isFalse);
    });

    // Pegawai yang berhenti dan barisnya dihapus tidak boleh membuat
    // shift lamanya kehilangan penanggung jawab.
    test('tanpa nama, emailnya yang dipakai', () {
      expect(buat({}).namaTampil, 'andi');
      expect(buat({'employee_name': 'Andi Kasir'}).namaTampil, 'Andi Kasir');
      expect(buat({'employee_name': '  '}).namaTampil, 'andi');
    });

    test('shift yang masih buka belum punya angka apa pun', () {
      final s = buat({});
      expect(s.countedCash, isNull);
      expect(s.expectedCash, isNull);
      expect(s.difference, isNull);
    });
  });

  group('SQL-nya', () {
    final sql = File('supabase/cashier_shift.sql').readAsStringSync();

    test('ikut terangkut ke JALANKAN-INI', () {
      final skrip = File('scripts/gabung_sql.sh').readAsStringSync();
      expect(skrip, contains('cashier_shift.sql'));
    });

    // Dua shift terbuka bersamaan akan menghitung penjualan tunai yang
    // sama dua kali, lalu keduanya sama-sama terlihat kelebihan uang.
    test('satu laci hanya boleh punya satu shift terbuka', () {
      expect(sql, contains('create unique index if not exists '
          'cashier_shifts_satu_terbuka'));
      expect(sql, contains('where closed_at is null'));
    });

    // Angka yang menilai seseorang tidak boleh berasal dari perangkat
    // orang itu.
    test('tidak ada jalan menyunting barisnya langsung', () {
      expect(sql, isNot(contains('for insert')));
      expect(sql, isNot(contains('for update')));
      expect(sql, isNot(contains('for all')));
      expect(sql, contains('for select using'));
    });

    test('menutup shift dihitung server, bukan dikirim aplikasi', () {
      expect(sql, contains('create or replace function close_shift'));
      expect(sql, contains('v_expected := shift_expected_cash('));
      expect(sql, contains('difference = p_counted_cash - v_expected'));
    });

    test('shift yang sudah ditutup tidak bisa ditutup dua kali', () {
      expect(sql, contains('Shift ini sudah ditutup.'));
    });

    test('menutup shift orang lain hanya untuk atasan', () {
      expect(sql, contains("array['owner', 'finance', 'admin']"));
    });

    group('perhitungan uang yang seharusnya ada', () {
      final fn = sql.substring(sql.indexOf('function shift_expected_cash'),
          sql.indexOf('function close_shift'));

      test('dimulai dari modal awal laci', () {
        expect(fn, contains('s.opening_cash'));
      });

      test('hanya penjualan tunai yang lunas', () {
        expect(fn, contains("o.payment_status = 'paid'"));
        expect(fn, contains("o.payment_method = 'cash'"));
      });

      test('dibatasi rentang waktu shiftnya', () {
        expect(fn, contains('o.created_at >= s.opened_at'));
        expect(fn, contains('o.created_at < p_until'));
      });

      // Uang setoran yang ditolak dikembalikan ke laci, jadi ia kembali
      // jadi tanggung jawab shift ini. Aturannya sama persis dengan
      // cashOnHand di lib/utils/cash_balance.dart — dua tempat yang
      // menghitung "tunai di laci" tidak boleh berbeda aturan.
      test('setoran dan petty cash yang ditolak tidak dikurangkan', () {
        expect(fn, contains("d.status <> 'rejected'"));
        expect(fn, contains("p.status <> 'rejected'"));
      });

      test('hanya petty cash yang menarik dari laci', () {
        expect(fn, contains("p.source = 'cash_withdrawal'"));
      });
    });
  });

  group('layarnya', () {
    final layar =
        File('lib/screens/cashier_shift_screen.dart').readAsStringSync();

    // Kasir yang tahu lebih dulu "seharusnya sekian" akan menghitung
    // sampai ketemu angka itu, bukan menghitung apa adanya.
    test('angka yang seharusnya tidak bocor sebelum uangnya dihitung', () {
      final tutup = layar.substring(layar.indexOf('Future<void> _tutup()'));
      final tanya = tutup.indexOf('_tanyaRupiah(');
      final minta = tutup.indexOf('_repo.perkiraan(');
      expect(tanya, greaterThan(0));
      expect(minta, greaterThan(tanya),
          reason: 'perkiraannya diminta sebelum nominalnya ditulis');
    });

    // Salah ketik satu angka nol tercatat selamanya sebagai selisih
    // jutaan rupiah atas nama orang yang tidak melakukan apa-apa. Menutup
    // shift tidak bisa dibatalkan, jadi kesempatan memperbaikinya harus
    // ada sebelum disimpan.
    test('nominalnya masih bisa diperbaiki sebelum tersimpan', () {
      final tutup = layar.substring(
          layar.indexOf('Future<void> _tutup()'),
          layar.indexOf('await _repo.tutup('));
      expect(tutup, contains('_konfirmasiSelisih('));
      expect(tutup, contains('nilaiAwal: awal'));
      expect(layar, contains("cancelLabel: 'Perbaiki Nominal'"));
    });

    test('hasilnya baru ditampilkan setelah tersimpan', () {
      final i = layar.indexOf('await _repo.tutup(');
      expect(layar.indexOf('_tampilkanHasil('), greaterThan(i));
    });

    // Perkiraan yang ditunjukkan sebelum menutup hanya penunjuk. Yang
    // tersimpan tetap dihitung ulang server di dalam close_shift, jadi
    // angka basi atau dipalsukan di perjalanan tidak bisa mengubah
    // selisih yang tercatat.
    test('aplikasi tidak pernah menghitung sendiri', () {
      final repo =
          File('lib/db/cashier_shift_repository.dart').readAsStringSync();
      final fungsi = repo.substring(repo.indexOf('Future<int> perkiraan('));
      expect(fungsi, contains("_client.rpc('shift_expected_cash'"));
      // Tidak ada aritmetika sama sekali — cuma meneruskan jawaban server.
      final badan = fungsi.substring(0, fungsi.indexOf('/// Menutup shift'));
      expect(badan.contains(' - '), isFalse);
      expect(badan.contains(' + '), isFalse);
    });
  });

  group('pintunya', () {
    // Kasir yang memegang laci, tapi atasannya yang menutup shift saat
    // kasirnya sudah pulang — keempatnya butuh pintu ini.
    test('ada di beranda kasir, admin, owner, dan finance', () {
      for (final f in [
        'kasir_home_screen',
        'admin_home_screen',
        'owner_home_screen',
        'finance_home_screen',
      ]) {
        final isi = File('lib/screens/$f.dart').readAsStringSync();
        expect(isi, contains('Shift Kasir'), reason: '$f tanpa pintu shift');
        expect(isi, contains('CashierShiftScreen()'), reason: '$f tanpa tujuan');
      }
    });
  });
}
