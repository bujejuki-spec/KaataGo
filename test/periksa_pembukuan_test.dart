import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Pemeriksa konsistensi pembukuan, dan mode "Lihat" yang kini berlaku
/// di seluruh layar yang bisa menulis.
void main() {
  final sql = File('supabase/periksa_pembukuan.sql').readAsStringSync();
  final layar =
      File('lib/screens/periksa_pembukuan_screen.dart').readAsStringSync();

  group('pemeriksanya', () {
    // Pemeriksa yang sekaligus membetulkan akan menyembunyikan sebab
    // kesalahannya — dan yang perlu diperbaiki hampir selalu kodenya,
    // bukan barisnya.
    test('memeriksa saja, tidak memperbaiki apa pun', () {
      final fungsi = sql.substring(sql.indexOf('create or replace function periksa_pembukuan'));
      for (final tulis in ['insert into', 'update ', 'delete from']) {
        expect(fungsi.toLowerCase(), isNot(contains(tulis)),
            reason: 'pemeriksa tidak boleh menulis apa pun');
      }
      expect(sql, contains('stable'));
    });

    test('hanya melaporkan yang dilanggar', () {
      expect(sql, contains('if v_nilai <> 0 then'));
      expect(sql, contains('return next;'));
    });

    test('keenam aturannya ada', () {
      for (final a in [
        'GL Suspense Setoran tidak nol',
        'GL Cash Pickup tidak nol',
        'Perusahaan minus',
        'Saldo Cash laci minus',
        'Penjualan non-tunai belum masuk Saldo Bank',
        'Pengeluaran tanpa lawan akun',
      ]) {
        expect(sql, contains(a), reason: '"$a" tidak diperiksa');
      }
    });

    // Penjualan hari ini memang belum dijalani tugas jam 5 pagi;
    // melaporkannya sebagai temuan berarti layar itu selalu merah.
    test('penjualan hari ini tidak dihitung sebagai temuan', () {
      expect(sql, contains("date_trunc('day', now() at time zone 'Asia/Jakarta')"));
    });

    test('hanya Owner dan Finance yang bisa menjalankannya', () {
      expect(sql, contains("array['owner', 'finance']"));
    });

    // Layar yang cuma berbunyi "aman" tanpa menyebutkan apa yang
    // diperiksanya menuntut orang percaya begitu saja.
    test('layarnya menyebutkan apa yang diperiksa saat bersih', () {
      expect(layar, contains("Text('Yang diperiksa'"));
      expect(layar, contains('class _YangDiperiksa'));
    });

    // Temuan tanpa arah cuma memindahkan kebingungan dari angka ke
    // kalimat.
    test('tiap temuan menyebut ke mana harus melihat', () {
      expect(sql, contains('petunjuk :='));
      expect(layar, contains('temuan.petunjuk'));
    });
  });

  group('mode Lihat berlaku di semua layar yang bisa menulis', () {
    // Pembatasan yang kadang bekerja lebih berbahaya daripada yang
    // jelas-jelas tidak ada: yang menyetelnya akan mengira sudah aman.
    test('tiap layar dengan tombol tulis membungkus dirinya', () {
      const wajib = [
        'restaurant_info_screen.dart',
        'publish_announcement_screen.dart',
        'finance_gl_mapping_screen.dart',
        'finance_gateway_settlement_screen.dart',
        'settings_screen.dart',
        'pending_payment_screen.dart',
        'category_management_screen.dart',
        'level_management_screen.dart',
        'billing_screen.dart',
        'product_list_screen.dart',
        'employee_management_screen.dart',
        'discount_screen.dart',
        'cash_deposit_screen.dart',
        'saldo_perusahaan_screen.dart',
        'terima_pickup_screen.dart',
        'tutup_buku_screen.dart',
        'rekonsiliasi_screen.dart',
        'bank_account_screen.dart',
      ];
      for (final f in wajib) {
        final isi = File('lib/screens/$f').readAsStringSync();
        expect(isi, contains('berdasarkanAkses('),
            reason: '$f belum dibungkus mode akses');
      }
    });

    test('pintu masuk mode ubah ikut terkunci', () {
      for (final f in [
        'restaurant_info_screen.dart',
        'settings_screen.dart',
        'finance_gl_mapping_screen.dart',
      ]) {
        final isi = File('lib/screens/$f').readAsStringSync();
        expect(isi, contains('bolehUbahDiSini(context) ? _startEdit : null'),
            reason: '$f masih menawarkan tombol Edit');
      }
    });

    test('tombol tambah dan bayar ikut terkunci', () {
      final kategori =
          File('lib/screens/category_management_screen.dart').readAsStringSync();
      final level =
          File('lib/screens/level_management_screen.dart').readAsStringSync();
      final tagihan =
          File('lib/screens/billing_screen.dart').readAsStringSync();
      final pending =
          File('lib/screens/pending_payment_screen.dart').readAsStringSync();
      for (final isi in [kategori, level, tagihan, pending]) {
        expect(isi, contains('bolehUbahDiSini(context)'));
      }
    });
  });
}
