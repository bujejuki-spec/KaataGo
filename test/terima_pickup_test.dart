import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pos_app/models/cash_deposit.dart';

/// Serah terima cash pickup, dan privasi shift kasir.
void main() {
  final sqlPickup = File('supabase/terima_cash_pickup.sql').readAsStringSync();
  final sqlShift = File('supabase/shift_privasi.sql').readAsStringSync();
  final sqlBuku = File('supabase/tutup_buku_harian.sql').readAsStringSync();

  CashDeposit buat({DateTime? diterima, int? jumlahTerima}) => CashDeposit(
        id: 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee',
        restoId: 'r1',
        amount: 500000,
        method: 'pickup',
        pickedUpBy: 'Budi',
        receivedAt: diterima,
        receivedAmount: jumlahTerima,
        createdBy: 'kasir@contoh.com',
        createdAt: DateTime(2026, 9, 12),
      );

  group('statusnya', () {
    test('pending sampai ada yang menerimanya', () {
      expect(buat().statusPickup, 'Pending');
      expect(buat().sudahDiterima, isFalse);
    });

    test('completed setelah diterima', () {
      final d = buat(diterima: DateTime(2026, 9, 13), jumlahTerima: 500000);
      expect(d.statusPickup, 'Completed');
      expect(d.selisihTerima, 0);
    });

    // Angka yang dipaksa sama dengan catatan awal tidak pernah bisa
    // menemukan apa pun. Yang dihitung penerima boleh berbeda, dan
    // bedanya justru temuannya.
    test('beda hitungan terbaca sebagai selisih', () {
      expect(buat(diterima: DateTime(2026, 9, 13), jumlahTerima: 480000)
          .selisihTerima, -20000);
      expect(buat(diterima: DateTime(2026, 9, 13), jumlahTerima: 510000)
          .selisihTerima, 10000);
    });
  });

  group('uangnya singgah dulu, tidak langsung sampai', () {
    // Pickup yang langsung dianggap mendarat di Total Saldo membuat
    // pertanyaan "mana uang yang dijemput Selasa lalu" tidak bisa
    // ditanyakan — jadi jawabannya tidak pernah dicari.
    test('pickup masuk GL Cash Pickup, setoran ke Total Saldo', () {
      expect(sqlPickup, contains("case when v_pickup then 'cash_pickup' else 'total_balance' end"));
    });

    test('serah terima memindahkannya ke Saldo Cash Perusahaan', () {
      expect(sqlPickup, contains("_gl_account_for(v_row.resto_id, 'cash_pickup')"));
      expect(sqlPickup, contains("_gl_account_for(v_row.resto_id, 'company_cash')"));
    });

    test('kedua akunnya punya nomor GL sendiri', () {
      expect(sqlPickup, contains("'2100004', 'GL Cash Pickup'"));
      expect(sqlPickup, contains("'1990002', 'GL Saldo Cash Perusahaan'"));
    });
  });

  group('siapa yang boleh menerima', () {
    // Yang membuat pickup adalah kasir atau admin. Kalau ia juga yang
    // menyatakan uangnya diterima, tidak ada tangan kedua di sepanjang
    // jalannya uang itu.
    test('hanya Finance dan Owner', () {
      final blok = sqlPickup.substring(
          sqlPickup.indexOf('create or replace function terima_pickup'),
          sqlPickup.indexOf('revoke all on function terima_pickup'));
      expect(blok, contains("array['owner', 'finance']"));
      expect(blok, isNot(contains('kasir')));
    });

    test('bukti terima dan jumlahnya wajib, ditolak server', () {
      expect(sqlPickup, contains('Bukti terima wajib dilampirkan.'));
      expect(sqlPickup, contains('Jumlah yang diterima wajib diisi.'));
    });

    test('yang sudah diterima tidak bisa diterima dua kali', () {
      expect(sqlPickup, contains('Pickup ini sudah diterima.'));
    });

    // Tanda terima yang isinya ikut berubah saat orangnya berganti nama
    // bukan tanda terima.
    test('nama penerimanya dibekukan dari data karyawan', () {
      expect(sqlPickup, contains('received_by_name = coalesce'));
      expect(sqlPickup, contains('from employees e'));
    });
  });

  group('shift kasir', () {
    // Riwayat shift menyebut selisih setiap orang yang pernah memegang
    // laci. Untuk sesama kasir itu catatan kinerja orang lain.
    test('kasir cuma melihat barisnya sendiri', () {
      expect(sqlShift, contains('"cashier_shifts: read"'));
      expect(sqlShift, contains("is_resto_employee(resto_id, array['kasir'])"));
      expect(sqlShift, contains("lower(coalesce(employee_email, ''))"));
    });

    test('selisih kasir ikut aturan yang sama', () {
      expect(sqlShift, contains('"cash_variances: read"'));
    });

    // Tanpa ini tombol Buka Shift terpajang, ditekan, lalu ditolak
    // server — dan penolakan setelah tombol ditekan terbaca sebagai
    // aplikasi yang rusak.
    test('ada tidaknya shift terbuka dijawab tanpa menyebut siapa', () {
      expect(sqlShift, contains('function shift_terbuka_ringkas'));
      expect(sqlShift, contains('returns table (ada boolean, milik_saya boolean)'));
      expect(sqlShift, isNot(contains('employee_name')));
    });

    test('layarnya menahan tombolnya, bukan menunggu galat', () {
      final layar =
          File('lib/screens/cashier_shift_screen.dart').readAsStringSync();
      expect(layar, contains('_dipegangOrangLain'));
      expect(layar, contains('utang > 0 || terkunci ? null : _buka'));
    });
  });

  group('tutup buku', () {
    test('Admin ikut boleh menutup dan membuka hari', () {
      expect(sqlBuku, contains("array['owner', 'finance', 'admin'])) then"));
      expect(sqlBuku,
          contains("is_resto_employee(resto_id, array['owner', 'finance', 'admin'])"));
    });
  });
}
