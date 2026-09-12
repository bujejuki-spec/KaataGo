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
    final terjadwal =
        File('supabase/jurnal_bank_terjadwal.sql').readAsStringSync();

    // Uang QRIS tidak mendarat di rekening pada detik pelanggan
    // membayar; ia ditahan penyedia dan cair belakangan. Mencatatnya
    // seketika membuat Saldo Bank menyebut uang yang belum bisa dipakai.
    test('penjualan non-tunai masuk rekening lewat tugas jam 5 pagi', () {
      expect(terjadwal,
          contains("in ('qris', 'qris_static', 'transfer')"));
      expect(terjadwal, contains('function jurnal_pendapatan_bank'));
      // 22:00 UTC = 05:00 WIB. pg_cron berjalan dalam UTC.
      expect(terjadwal, contains("'0 22 * * *'"));
    });

    test('pesanan lunas tidak lagi langsung menyentuh Saldo Bank', () {
      final blok = terjadwal.substring(
          terjadwal.indexOf('create or replace function log_order_paid_journal'),
          terjadwal.indexOf('create or replace function jurnal_pendapatan_bank'));
      expect(blok, isNot(contains('company_bank')));
    });

    // Kalau tugasnya pernah gagal jalan, yang terlewat ikut tersapu esok
    // harinya — bukan hilang selamanya.
    test('yang terlewat ikut tersapu, bukan cuma kemarin', () {
      expect(terjadwal, contains('not exists ('));
      expect(terjadwal, isNot(contains("interval '1 day'")));
    });

    // Penjualan 30 September yang tercatat 1 Oktober membuat kedua bulan
    // salah di tutup buku dan laporan per periode.
    test('tanggal jurnalnya ikut tanggal pesanannya', () {
      expect(terjadwal,
          contains("(o.created_at at time zone 'Asia/Jakarta')::date"));
    });

    test('setoran kasir yang disetujui mendarat di Saldo Bank', () {
      // laci → GL Suspense Setor Tunai → (disetujui) → Saldo Bank.
      // Sebelumnya tujuannya GL Total Saldo, akun payung yang menampung
      // segalanya — benar selama Saldo Perusahaan belum ada.
      final setoran =
          File('supabase/setoran_ke_saldo_bank.sql').readAsStringSync();
      expect(setoran,
          contains("case when v_pickup then 'company_cash' else 'company_bank' end"));
      expect(setoran, isNot(contains("'total_balance'")));
      // Titipannya tetap lewat GL Suspense lebih dulu.
      expect(setoran,
          contains("case when v_pickup then 'cash_pickup' else 'suspense' end"));
    });

    test('setoran lama yang sudah disetujui ikut dilengkapi', () {
      final setoran =
          File('supabase/setoran_ke_saldo_bank.sql').readAsStringSync();
      expect(setoran, contains("where d.status = 'approved'"));
      expect(setoran, contains('not exists ('));
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

  group('pengeluaran perusahaan dicatat di layarnya sendiri', () {
    final harian =
        File('lib/screens/finance_balance_screen.dart').readAsStringSync();

    // Dua pintu ke kantong yang sama membuat yang satu pasti
    // ketinggalan saat aturannya berubah.
    test('layar harian kembali murni petty cash', () {
      expect(harian, contains("const namaSumber = 'Petty Cash';"));
      expect(harian, isNot(contains('bolehPilihSumber')));
      expect(harian, isNot(contains("'cash' => widget.saldoCash")));
    });

    test('layar perusahaan memilih cash atau bank saja', () {
      expect(layar, contains('class _DialogPengeluaran'));
      expect(layar, contains("_sumber == 'cash' ? widget.saldoCash"));
      // Tidak ada petty cash di sini: kas kecil kasir punya layarnya.
      final blok = layar.substring(layar.indexOf('class _DialogPengeluaran'));
      expect(blok, isNot(contains("value: 'petty'")));
      expect(blok, isNot(contains("fundSource: 'petty'")));
    });

    // Daftar yang sama dengan pengeluaran petty cash, supaya laporan per
    // akun tidak terbelah menurut dari kantong mana uangnya diambil.
    test('akun biayanya diambil dari daftar GL Pengeluaran', () {
      expect(layar, contains('ExpenseGlAccountRepository().getForResto'));
      expect(layar, contains("label: requiredLabel('Akun Pengeluaran')"));
    });

    test('tidak bisa membelanjakan lebih dari yang dipegang', () {
      expect(layar, contains('if (n > _tersedia)'));
    });

    // Menampilkan pengeluaran petty cash di sini membuat satu
    // pengeluaran terbaca dua kali.
    test('daftarnya cuma yang bersumber uang perusahaan', () {
      expect(layar,
          contains("if (e.fundSource == 'cash' || e.fundSource == 'bank') e,"));
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
      expect(layar, contains('Melebihi \$_namaSumber'));
    });
  });

  group('selisih kasir yang dilunasi transfer', () {
    final sqlSelisih =
        File('supabase/jurnal_selisih_ke_bank.sql').readAsStringSync();

    // Uangnya mendarat di rekening merchant, persis seperti penjualan
    // QRIS dan transfer pelanggan. Sebelumnya jurnalnya berhenti di GL
    // Selisih Kasir, jadi Saldo Bank tidak pernah tahu uang itu ada.
    test('ikut dikreditkan ke Saldo Bank', () {
      expect(sqlSelisih, contains("if v_cara = 'transfer' then"));
      expect(sqlSelisih,
          contains("_gl_account_for(v_row.resto_id, 'company_bank')"));
    });

    // Lembarannya kembali ke laci, dan laci sudah menghitungnya lewat
    // jalurnya sendiri.
    test('yang dibayar tunai tidak ikut', () {
      final blok = sqlSelisih.substring(
          sqlSelisih.indexOf("if v_cara = 'transfer' then"),
          sqlSelisih.indexOf('return v_hasil;'));
      expect(blok, contains('company_bank'));
      expect(blok.split("if v_cara = 'transfer' then").length, 2);
    });

    test('yang sudah terlanjur tercatat ikut dilengkapi', () {
      expect(sqlSelisih, contains("v.settle_method = 'transfer'"));
      expect(sqlSelisih, contains('not exists ('));
    });
  });

  group('setoran modal memilih kantongnya', () {
    final terjadwal =
        File('supabase/jurnal_bank_terjadwal.sql').readAsStringSync();

    test('merchant memilih cash atau bank', () {
      expect(terjadwal,
          contains("check (destination in ('cash', 'bank'))"));
      expect(terjadwal, contains("then 'company_cash'"));
    });

    // Pembukuan KaataGo tidak punya laci kasir maupun rekening merchant,
    // jadi tidak ada kantong lain untuk menampungnya.
    test('KaataGo sendiri tetap memakai GL Setoran Modal', () {
      expect(terjadwal, contains("when new.resto_id = 'kaatago' then 'capital'"));
    });

    // Barisnya di jurnal tidak disentuh: setoran modal yang sudah
    // tercatat tetap berdiri di akun itu.
    test('yang dilepas cuma pemetaannya, bukan jurnalnya', () {
      expect(terjadwal, contains('delete from gl_accounts'));
      expect(terjadwal, contains("where payment_method = 'capital'"));
      expect(terjadwal, isNot(contains('delete from gl_journal_entries')));
    });

    test('GL Setoran Modal tinggal milik platform di Mapping GL', () {
      final mapping =
          File('lib/screens/finance_gl_mapping_screen.dart').readAsStringSync();
      final blok = mapping.substring(
          mapping.indexOf('const _platformOnlyMethods'),
          mapping.indexOf('String _pctText'));
      expect(blok, contains('_capitalMethod'));
    });
  });

  test('kedua akunnya bisa dipetakan di Mapping GL', () {
    final mapping =
        File('lib/screens/finance_gl_mapping_screen.dart').readAsStringSync();
    expect(mapping, contains("_companyBankMethod = 'company_bank'"));
    expect(mapping, contains('GL Saldo Bank Perusahaan'));
    expect(mapping, contains('  _companyBankMethod,\n'));
  });

  // Bentuknya mengikuti Saldo & Pengeluaran: judul yang bisa dilipat
  // dengan satu tombol di ujung kanannya. Dua layar yang menyusun
  // daftar dengan cara yang sama tapi memakai widget berbeda akan
  // berpisah bentuknya pada perubahan berikutnya.
  group('bagiannya bisa dilipat', () {
    test('ketiganya memakai judul bagian bersama', () {
      expect(layar, contains("title: 'Setoran ke Bank',"));
      expect(layar, contains("title: 'Pengeluaran Perusahaan',"));
      expect(layar, contains("title: 'Setoran Modal',"));
      expect(layar, contains('JudulBagian('));
      expect(layar, contains('TombolPil('));
    });

    test('tombol mengambangnya dilepas', () {
      expect(layar, isNot(contains('FloatingActionButton')));
    });

    test('tiap bagian punya keadaan terbuka sendiri', () {
      for (final k in ['_setoranTerbuka', '_biayaTerbuka', '_modalTerbuka']) {
        expect(layar, contains(k));
      }
    });

    test('widget judulnya dipakai kedua layar', () {
      final harian =
          File('lib/screens/finance_balance_screen.dart').readAsStringSync();
      expect(harian, contains("import '../widgets/judul_bagian.dart';"));
      expect(harian, contains('JudulBagian('));
    });
  });
}
