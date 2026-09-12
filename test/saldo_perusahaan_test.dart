import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pos_app/models/expense.dart';

/// Saldo Perusahaan: uang tunai yang dipegang, dan uang di rekening.
void main() {
  final sql = File('supabase/saldo_perusahaan.sql').readAsStringSync();
  final layar =
      File('lib/screens/saldo_perusahaan_screen.dart').readAsStringSync();

  group('satu angka, satu sumber', () {
    // Perhitungan kedua yang berdiri sendiri di layar akan berpisah dari
    // jurnalnya pada perubahan berikutnya — dan dua angka yang sama-sama
    // mengaku menyebut uang perusahaan adalah kekeliruan yang paling
    // sering harus diperbaiki di aplikasi ini.
    test('saldonya dihitung server dari pergerakan akun GL-nya', () {
      expect(sql, contains('create or replace function saldo_perusahaan'));
      expect(sql, contains('returns table (cash bigint, bank bigint)'));
      expect(sql, contains("in ('company_cash', 'company_bank')"));
    });

    test('layarnya tidak menjumlahkan sendiri dari tabel pesanan', () {
      expect(layar, contains('_repo.saldo(restoId)'));
      expect(layar, isNot(contains("from('orders')")));
    });

    // Aturan yang sama dengan seluruh aplikasi, dan dengan layar Jurnal
    // GL: kredit menaikkan, debit menurunkan.
    test('kredit menaikkan, debit menurunkan', () {
      expect(sql,
          contains("case when b.entry_type = 'credit' then b.amount else -b.amount end"));
    });

    test('baris pembatalan tidak ikut dihitung', () {
      expect(sql, contains('coalesce(j.is_reversal, false) = false'));
    });
  });

  group('apa yang mengisi kedua kantongnya', () {
    test('penjualan non-tunai masuk rekening, tunai tidak', () {
      // Tunai masuk laci, dan perjalanannya ke perusahaan lewat setoran
      // atau cash pickup — keduanya sudah punya jurnalnya sendiri.
      expect(sql, contains("v_method in ('qris', 'qris_static', 'transfer')"));
    });

    test('setoran kasir yang disetujui ikut masuk rekening', () {
      expect(sql, contains('Setoran kasir masuk rekening #'));
    });

    test('serah terima cash pickup masuk ke saldo cash', () {
      // Dijurnal di terima_pickup, dan berkas ini tidak boleh
      // mengubahnya jadi sesuatu yang lain.
      final pickup =
          File('supabase/jurnal_cash_pickup_benar.sql').readAsStringSync();
      expect(pickup, contains("_gl_account_for(v_row.resto_id, 'company_cash')"));
    });
  });

  group('setor ke bank', () {
    // `cashOnHand` mengurangi isi laci sebesar setiap baris
    // cash_deposits. Uang yang disetor di sini sudah lama meninggalkan
    // laci, jadi menaruhnya di tabel itu menguranginya dua kali.
    test('tabelnya sendiri, bukan cash_deposits', () {
      expect(sql, contains('create table if not exists company_deposits'));
      expect(sql, contains('company_cash'));
      expect(sql, contains("'company_deposit', new.id::text, new.amount, 'debit'"));
      expect(sql, contains("'company_deposit', new.id::text, new.amount, 'credit'"));
    });

    test('hanya Owner dan Finance', () {
      expect(sql, contains('"company_deposits: finance"'));
      expect(sql, contains("array['owner', 'finance']"));
    });

    test('tidak bisa menyetor lebih dari yang dipegang', () {
      expect(layar, contains('n > widget.saldoCash'));
    });
  });

  group('pengeluaran menyebut sumber dananya', () {
    test('bawaannya petty cash', () {
      // Menafsirkan ulang pengeluaran lama sebagai potongan rekening
      // membuat saldo bank berbunyi minus untuk uang yang tidak pernah
      // keluar dari sana.
      expect(Expense(
        id: 'x',
        restoId: 'r1',
        amount: 1000,
        description: 'apa saja',
        createdBy: 'a@b.c',
        createdAt: DateTime(2026, 9, 12),
      ).fundSource, 'petty');
      expect(sql, contains("default 'petty'"));
      expect(sql, contains("check (fund_source in ('petty', 'cash', 'bank'))"));
    });

    test('kantong yang dipilih yang dipotong', () {
      expect(sql, contains("when 'cash' then 'company_cash'"));
      expect(sql, contains("when 'bank' then 'company_bank'"));
    });

    // Sebelumnya petty cash DIKREDIT saat uangnya dipakai — dan kredit
    // menaikkan saldo, jadi tiap pengeluaran justru menambah saldo petty
    // cash di jurnal.
    test('sumbernya didebit, bukan dikredit', () {
      final blok = sql.substring(sql.indexOf('function log_expense_journal'));
      expect(blok, contains("new.amount, 'debit', v_sebut"));
    });

    test('batas nominalnya ikut kantong yang dipilih', () {
      final balance =
          File('lib/screens/finance_balance_screen.dart').readAsStringSync();
      expect(balance, contains("'cash' => widget.saldoCash"));
      expect(balance, contains("'bank' => widget.saldoBank"));
      expect(balance, contains('Melebihi \$namaSumber'));
    });
  });

  test('kedua akunnya bisa dipetakan di Mapping GL', () {
    final mapping =
        File('lib/screens/finance_gl_mapping_screen.dart').readAsStringSync();
    expect(mapping, contains("_companyBankMethod = 'company_bank'"));
    expect(mapping, contains('GL Saldo Bank Perusahaan'));
    expect(mapping, contains('  _companyBankMethod,\n'));
  });
}
