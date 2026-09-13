import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Menyetel saldo awal kas dan rekening perusahaan.
///
/// Saldo Bank menjumlahkan uang yang PERNAH MASUK, bukan yang masih ada:
/// pengeluaran dari rekening sebelum aplikasi ini mencatatnya tidak
/// punya barisnya di mana pun. Angka yang tidak bisa dipakai mengambil
/// keputusan lebih berbahaya daripada angka yang tidak ada, karena ia
/// tetap dibaca orang.
void main() {
  final sql = File('supabase/saldo_awal.sql').readAsStringSync();
  final layar =
      File('lib/screens/saldo_perusahaan_screen.dart').readAsStringSync();

  group('cara menyetelnya', () {
    // Menghapus baris lama demi merapikan satu angka berarti menukar
    // angka yang salah dengan riwayat yang bohong.
    test('menambah penyesuaian, tidak menghapus riwayat', () {
      final fungsi =
          sql.substring(sql.indexOf('create or replace function setel_saldo_awal'));
      expect(fungsi.toLowerCase(), isNot(contains('delete from')));
      expect(fungsi, contains('Penyesuaian saldo awal'));
    });

    // Pergerakan sesudah tanggal itu berjalan di atas saldo awalnya.
    test('yang dibandingkan hanya sampai tanggal yang disebut', () {
      expect(sql, contains('and j.entry_date <= p_tanggal'));
    });

    // Jurnal timpang membuat Jurnal GL berhenti bisa dibaca sebagai
    // pasangan debit-kredit.
    test('punya lawan akun, arah kebalikannya', () {
      expect(sql, contains("_gl_account_for(p_resto_id, 'opening_balance')"));
      expect(sql, contains("case when v_selisih > 0 then 'credit' else 'debit' end"));
      expect(sql, contains("case when v_selisih > 0 then 'debit' else 'credit' end"));
    });

    // Baris penyesuaian bernilai nol cuma menambah baris yang harus
    // dibaca orang nanti — dan membuat penyetelan ulang menumpuk.
    test('tidak menulis apa-apa kalau sudah cocok', () {
      expect(sql, contains('if v_selisih = 0 then'));
      expect(sql, contains('return 0;'));
    });

    test('tanggal yang belum terjadi ditolak', () {
      expect(sql, contains('Tanggalnya belum terjadi.'));
    });

    // Menyatakan berapa isi rekening perusahaan adalah pernyataan
    // pembukuan, bukan pekerjaan operasional.
    test('hanya Owner dan Finance', () {
      expect(sql, contains("array['owner', 'finance']"));
      expect(sql, contains('Hanya Owner dan Finance yang bisa menyetel'));
    });
  });

  group('di layarnya', () {
    // Tombol yang selalu terpampang untuk hal yang dilakukan setahun
    // sekali cuma mengundang orang menekannya.
    test('ada di menu tiga titik, bukan tombol tetap', () {
      expect(layar, contains("value: 'saldo-awal'"));
      expect(layar, contains('PopupMenuButton<String>'));
    });

    test('ikut terkunci di mode Lihat', () {
      expect(layar, contains('if (bolehUbahDiSini(context))'));
    });

    test('memberitahu hasilnya, termasuk saat tidak ada yang berubah', () {
      expect(layar, contains('Sudah cocok — tidak ada penyesuaian'));
    });
  });

  test('akunnya bisa dipetakan dan ada bawaannya', () {
    final mapping =
        File('lib/screens/finance_gl_mapping_screen.dart').readAsStringSync();
    expect(mapping, contains("_openingBalanceMethod = 'opening_balance'"));
    expect(mapping, contains("label: 'GL Saldo Awal'"));
    for (final f in ['default_gl_accounts.sql', 'cash_variance.sql']) {
      expect(File('supabase/$f').readAsStringSync(),
          contains("('opening_balance',  '1990004', 'GL Saldo Awal')"));
    }
  });
}
