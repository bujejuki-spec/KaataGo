import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pos_app/models/balance_topup.dart';

void main() {
  final sql = File('supabase/balance_topup.sql').readAsStringSync();
  // Top up modal pindah ke layar Saldo Perusahaan: modal masuk ke
  // perusahaan, bukan ke penjualan hari ini.
  final layar =
      File('lib/screens/saldo_perusahaan_screen.dart').readAsStringSync();
  final harian =
      File('lib/screens/finance_balance_screen.dart').readAsStringSync();
  final pemetaan =
      File('lib/screens/finance_gl_mapping_screen.dart').readAsStringSync();

  group('akun modal', () {
    test('punya akunnya sendiri, bukan menumpang pendapatan', () {
      // Resto yang menyetor modal besar tidak boleh terlihat seperti
      // resto yang laris.
      expect(sql, contains("'capital'"));
      expect(sql, contains("'1100003', 'GL Setoran Modal'"));
      expect(sql, contains("'1940001', 'GL Setoran Modal'"));
    });

    test('merchant platform tidak kebagian nomor merchant', () {
      expect(sql, contains('coalesce(r.is_platform, false) = false'));
    });

    test('masuk daftar metode yang diizinkan', () {
      expect(sql, contains("'voucher_redeem',\n     'capital'"));
    });

    // Tinggal milik KaataGo sendiri.
    //
    // Di merchant, setoran modal sekarang mendarat di Saldo Cash atau
    // Saldo Bank — yang mana disebut penyetornya. Akun ketiga yang
    // berdiri sendiri menjawab pertanyaan yang tidak pernah ditanyakan:
    // yang ditanyakan adalah berapa uang di tangan dan berapa di
    // rekening.
    test('GL Modal tinggal milik platform', () {
      expect(pemetaan, contains("const _capitalMethod = 'capital';"));
      expect(pemetaan, contains("title: 'GL Modal'"));
      final blok = pemetaan.substring(
          pemetaan.indexOf('const _platformOnlyMethods'),
          pemetaan.indexOf('};', pemetaan.indexOf('const _platformOnlyMethods')));
      expect(blok, contains('_capitalMethod'));
    });
  });

  group('tempatnya', () {
    test('formulirnya ada di Saldo Perusahaan', () {
      expect(layar, contains('class _FormModal'));
      expect(layar, contains("label: 'Top Up',"));
    });

    // Menghitungnya juga di layar harian membuat satu setoran muncul di
    // dua tempat, dan yang menjumlahkan keduanya mendapat angka yang
    // tidak pernah ada.
    test('tidak lagi menyentuh saldo harian merchant', () {
      expect(harian, isNot(contains('_topupTotal')));
      expect(harian, isNot(contains('class _FormModal')));
      final rumus = harian.substring(
          harian.indexOf('int get _nonCashBalance'),
          harian.indexOf('int get _pettyCashToppedUp'));
      expect(rumus, isNot(contains('_topup')));
    });
  });

  group('jurnalnya', () {
    test('satu baris kredit ke akun modalnya sendiri', () {
      // Sempat ditulis berpasangan dengan debit GL Total Saldo — dan
      // pasangan yang saling menghapus membuat setoran modal tidak
      // menaikkan saldo sama sekali, karena saldo adalah selisih
      // seluruh kredit dan debit.
      final blok = sql.substring(sql.indexOf('function log_balance_topup'));
      expect(blok, contains("'capital', new.id::text, new.amount, 'credit'"));
      expect(blok, isNot(contains("'debit'")));
      expect(blok, isNot(contains("'total_balance'")));
    });

    test('jenis rujukannya masuk daftar batasan', () {
      expect(sql, contains("'voucher', 'capital'"));
    });

    test('ditulis pemicu, bukan aplikasi', () {
      // Dua baris jurnal yang dikirim aplikasi bisa sampai satu dan
      // gagal satu, dan pembukuan timpang sebelah lebih sulit ditemukan
      // daripada pembukuan yang kosong.
      expect(sql, contains('after insert on balance_topups'));
      final repo =
          File('lib/db/balance_topup_repository.dart').readAsStringSync();
      expect(repo, isNot(contains('gl_journal_entries')));
    });
  });

  group('siapa boleh mencatat', () {
    test('kasir melihat tapi tidak menambah', () {
      // Baris yang menaikkan saldo tanpa uang sungguhan adalah cara
      // paling rapi menutupi selisih laci.
      final baca = sql.substring(sql.indexOf('"balance_topups: read"'),
          sql.indexOf('"balance_topups: write"'));
      expect(baca, contains("'kasir'"));
      final tulis = sql.substring(sql.indexOf('"balance_topups: write"'));
      expect(tulis.substring(0, 300), isNot(contains("'kasir'")));
    });

    test('tidak ada yang boleh mengubah atau menghapus', () {
      expect(sql, contains('for insert with check'));
      expect(sql, isNot(contains('for all using')));
    });
  });

  group('di layar', () {
    // Modal mendarat di kantong perusahaan, dan daftarnya berdiri di
    // layar yang sama dengan saldonya — bukan di layar harian merchant,
    // yang menjawab pertanyaan lain sama sekali.
    test('daftarnya berdiri di Saldo Perusahaan', () {
      expect(layar, contains("title: 'Setoran Modal',"));
      expect(layar, contains('masuk \${m.labelTujuan}'));
    });

    test('penyetornya wajib disebut', () {
      expect(layar, contains("'Sebutkan penyetornya'"));
    });

    // Layarnya sendiri cuma untuk Owner dan Finance, dan tombolnya ikut
    // hilang kalau menunya dibuka dalam mode Lihat.
    test('tombolnya mengikuti hak mengubah', () {
      expect(layar, contains('action: bolehUbahDiSini(context)'));
    });

    // Uang yang ditransfer dan uang yang diserahkan tunai mendarat di
    // tempat yang berbeda, dan menebaknya berarti salah satu dari dua
    // saldo perusahaan selalu meleset.
    test('penyetornya menyebut masuk ke kantong mana', () {
      final form = layar.substring(layar.indexOf('class _FormModal'));
      expect(form, contains('DropdownButtonFormField'));
      expect(form, contains("labelText: 'Masuk ke'"));
      expect(form, contains("value: 'bank'"));
      expect(form, contains("value: 'cash'"));
    });
  });

  group('modelnya', () {
    test('terbaca dari baris database', () {
      final t = BalanceTopup.fromMap({
        'id': 'abc',
        'resto_id': 'r1',
        'amount': 5000000,
        'source': 'Pak Budi',
        'note': 'Modal awal',
        'created_at': '2026-08-18T10:00:00Z',
      });
      expect(t.amount, 5000000);
      expect(t.source, 'Pak Budi');
      expect(t.punyaBukti, isFalse);
    });
  });

  group('wording masuk', () {
    test('Karyawan Merchant sudah jadi KaataGo Merchant', () {
      final pilih =
          File('lib/screens/role_choice_screen.dart').readAsStringSync();
      expect(pilih, contains("context.tr('KaataGo Merchant')"));
      expect(pilih, isNot(contains('Karyawan Merchant')));
    });
  });
}
