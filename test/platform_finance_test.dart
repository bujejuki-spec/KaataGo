import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pos_app/models/billing.dart';

BillingDiscount _d({
  DiscountKindBilling kind = DiscountKindBilling.percent,
  int value = 20,
  List<String> restoIds = const ['r1'],
  DateTime? startsOn,
  DateTime? endsOn,
  bool active = true,
}) =>
    BillingDiscount(
      id: 'bd1',
      name: 'Promo Pembukaan',
      kind: kind,
      value: value,
      restoIds: restoIds,
      startsOn: startsOn,
      endsOn: endsOn,
      active: active,
      createdAt: DateTime(2026, 8, 1),
    );

void main() {
  group('diskon langganan', () {
    test('persen dibulatkan ke bawah', () {
      expect(_d(value: 20).amountFor(150000), 30000);
      expect(_d(value: 33).amountFor(150000), 49500);
    });

    test('potongan rupiah tetap', () {
      expect(
        _d(kind: DiscountKindBilling.amount, value: 50000).amountFor(150000),
        50000,
      );
    });

    test('potongan tidak pernah melebihi harganya sendiri', () {
      // Kalau melebihi, tagihannya negatif — yaitu kami yang berutang
      // kepada resto yang belum membayar apa pun.
      expect(
        _d(kind: DiscountKindBilling.amount, value: 500000).amountFor(150000),
        150000,
      );
    });

    test('harga nol tidak menghasilkan potongan', () {
      expect(_d().amountFor(0), 0);
    });

    test('yang dimatikan tidak berlaku walau tanggalnya pas', () {
      expect(_d(active: false).isLive(DateTime(2026, 8, 17)), isFalse);
    });

    test('belum mulai belum berlaku', () {
      final d = _d(startsOn: DateTime(2026, 9, 1));
      expect(d.isLive(DateTime(2026, 8, 17)), isFalse);
      expect(d.isLive(DateTime(2026, 9, 1)), isTrue);
    });

    test('hari terakhir masih berlaku penuh', () {
      final d = _d(endsOn: DateTime(2026, 8, 31));
      expect(d.isLive(DateTime(2026, 8, 31)), isTrue);
      expect(d.isLive(DateTime(2026, 9, 1)), isFalse);
    });

    test('tersimpan dan terbaca kembali', () {
      final map = _d(restoIds: ['r1', 'r2']).toMap();
      expect(map['resto_ids'], ['r1', 'r2']);
      final lagi = BillingDiscount.fromMap(
          {...map, 'created_at': DateTime(2026, 8, 1).toIso8601String()});
      expect(lagi.restoIds, ['r1', 'r2']);
      expect(lagi.kind, DiscountKindBilling.percent);
    });
  });

  group('penyewa platform', () {
    final sql = File('supabase/platform_finance.sql').readAsStringSync();

    test('KaataGo punya barisnya sendiri di tabel resto', () {
      expect(sql, contains("values ('kaatago', 'KaataGo'"));
      expect(kPlatformRestoId, 'kaatago');
    });

    test('barisnya tidak aktif, supaya lolos dari saringan yang sudah ada', () {
      // Daftar resto pelanggan, pemilih resto, dan pencarian semuanya
      // sudah menyaring yang tidak aktif.
      expect(sql, contains("false, true)"));
    });

    test('ia bukan pelanggan dirinya sendiri', () {
      expect(sql, contains("update resto_billing set active = false"));
    });

    test('daftar resto menyaring penyewa platform', () {
      final repo =
          File('lib/db/restaurant_repository.dart').readAsStringSync();
      expect(repo, contains(".eq('is_platform', false)"));
    });

    test('punya bagan akun sendiri, bernomor beda dari resto', () {
      // 11xxxxx supaya satu baris jurnal bisa dikenali pemiliknya hanya
      // dari nomornya.
      expect(sql, contains("'subscription',          '1100001'"));
      expect(sql, contains("'subscription_discount', '1100002'"));
    });
  });

  group('jurnal pendapatan langganan', () {
    final sql = File('supabase/platform_finance.sql').readAsStringSync();

    test('dicatat di buku KaataGo, bukan di buku restonya', () {
      // Bagi resto, biaya langganan adalah pengeluaran mereka.
      // Menuliskannya ke jurnal mereka dari sini berarti kami menulis di
      // pembukuan orang lain.
      expect(sql, contains("_gl_account_for('kaatago', 'subscription')"));
      expect(sql, contains("'kaatago',\n      (v_now"));
    });

    test('pendapatan dikredit, diskon didebit', () {
      final gross =
          File('supabase/billing_journal_gross.sql').readAsStringSync();
      expect(gross, contains("v_gross, 'credit'"));
      expect(gross, contains("new.discount_amount, 'debit'"));
    });

    test('tidak mencatat dua kali walau statusnya berpindah lagi', () {
      expect(sql, contains("where reference_type = 'billing'"));
    });

    test('hanya mencatat yang benar-benar lunas', () {
      expect(sql, contains("if new.status <> 'paid' then"));
    });
  });

  group('akses Super Admin', () {
    final sql = File('supabase/platform_finance.sql').readAsStringSync();

    test('jurnal lintas resto hanya bisa DIBACA', () {
      // Tangan yang bisa menulis langsung ke jurnal adalah tangan yang
      // bisa membuat pembukuan berbeda dari yang benar-benar terjadi —
      // dan itu berlaku untuk Super Admin persis seperti untuk yang lain.
      final blok = sql.substring(sql.indexOf('gl_journal_entries: super admin read'));
      expect(blok, contains('for select using (is_super_admin())'));
      expect(blok, isNot(contains('gl_journal_entries" for all')));
    });

    test('akses ditambahkan sebagai kebijakan baru, bukan menulis ulang', () {
      // Kebijakan permissive digabung dengan OR, jadi menambah satu
      // cukup. Menulis ulang yang lama berarti menyalin ulang syaratnya,
      // yang suatu hari akan tersalin tidak lengkap.
      for (final t in [
        'gl_accounts: super admin',
        'expenses: super admin',
        'petty_cash_entries: super admin',
        'expense_gl_accounts: super admin',
      ]) {
        expect(sql, contains(t), reason: t);
      }
    });

    test('tidak ada setor tunai di sisi platform', () {
      // KaataGo tidak punya laci kasir; menyetor tunai ke rekening
      // sendiri adalah pekerjaan resto yang uangnya menumpuk di sana.
      final layar =
          File('lib/screens/super_admin_finance_screen.dart').readAsStringSync();
      expect(layar, isNot(contains('CashDepositScreen')));
      expect(layar, contains('KaataGo tidak punya laci'));
    });
  });

  group('diskon ikut memotong tagihan yang sudah terbit', () {
    final sql = File('supabase/billing_discount_apply.sql').readAsStringSync();

    test('tagihan yang belum dibayar disegarkan, bukan dibiarkan', () {
      // `on conflict do nothing` menjaga satu tagihan per periode, tapi
      // juga membekukan nominalnya sejak detik pertama — diskon yang
      // dibuat sesudahnya tidak pernah sampai.
      expect(sql, contains("and i.status = 'unpaid'"));
      expect(sql, contains('and i.amount <> v_amount'));
    });

    test('yang sudah mengirim bukti tidak diubah nominalnya', () {
      // Mengubah nominal di bawah kaki orang yang sudah membayar adalah
      // cara tercepat membuat pembayaran yang benar terlihat kurang.
      expect(sql, isNot(contains("i.status in ('unpaid', 'review')")));
    });

    test('nomor VA dibuang begitu nominalnya berubah', () {
      // VA tertutup di nominal lama akan MENOLAK transfer sebesar
      // nominal baru: resto membayar jumlah yang benar dan tetap
      // dianggap belum bayar.
      final blokUpdate = sql.substring(sql.indexOf('update billing_invoices i'));
      expect(blokUpdate, contains('va_number = null'));
      expect(blokUpdate, contains('va_expires_at = null'));
    });

    test('bisa disegarkan satu per satu tanpa menunggu penjadwal', () {
      expect(sql, contains('function refresh_billing_invoice'));
      expect(sql, contains('Hanya Super Admin yang dapat menyegarkan'));
    });

    test('yang sudah lunas tidak ikut dihitung ulang', () {
      expect(sql, contains("if v_inv.status <> 'unpaid' then"));
    });

    test('tagihan lama tanpa gross_amount diisi dari nominalnya sendiri', () {
      // Supaya rinciannya tidak menampilkan "harga langganan Rp 0".
      expect(sql, contains('where gross_amount is null'));
    });

    test('layar tagihan menampilkan rinciannya', () {
      final layar =
          File('lib/screens/billing_screen.dart').readAsStringSync();
      expect(layar, contains('Harga langganan'));
      expect(layar, contains('invoice.discountAmount > 0'));
    });
  });


  group('pendapatan dicatat sebesar harga penuh', () {
    final sql = File('supabase/billing_journal_gross.sql').readAsStringSync();

    test('yang dikredit harga daftar, bukan yang sudah dipotong', () {
      // Mengkredit nominal yang sudah dipotong LALU mendebit diskonnya
      // menghitung potongan itu dua kali: tagihan 230.000 berdiskon 50%
      // menghasilkan pendapatan bersih nol, padahal 115.000 benar-benar
      // masuk.
      expect(sql, contains('v_gross := coalesce(new.gross_amount, new.amount)'));
      expect(sql, contains("v_gross, 'credit'"));
    });

    test('tagihan lama tanpa gross memakai nominalnya sendiri', () {
      // Untuk mereka, nominalnya memang harga penuhnya.
      expect(sql, contains('coalesce(new.gross_amount, new.amount)'));
    });

    test('jurnal yang salah diperbaiki dengan menambah, bukan menyunting', () {
      // Pembukuan yang barisnya bisa disunting belakangan tidak bisa
      // dipakai membuktikan apa pun.
      expect(sql, isNot(contains('update gl_journal_entries')));
      expect(sql, isNot(contains('delete from gl_journal_entries')));
      expect(sql, contains('insert into gl_journal_entries'));
      expect(sql, contains('Koreksi pencatatan diskon'));
    });

    test('koreksinya hanya sekali walau berkasnya dijalankan berulang', () {
      expect(sql, contains("k.description like 'Koreksi pencatatan diskon%'"));
    });

    test('yang dikoreksi hanya yang memang tercatat bersih', () {
      expect(sql, contains('j.amount = i.amount'));
      expect(sql, contains('i.gross_amount > i.amount'));
    });
  });


  group('GL diskon di layar pemetaan', () {
    final layar =
        File('lib/screens/finance_gl_mapping_screen.dart').readAsStringSync();

    test('GL Diskon punya bagiannya sendiri', () {
      // Tanpa ini, akunnya ada di database tapi tidak pernah bisa
      // dilihat atau diubah Finance — dan yang GL-nya belum dipetakan
      // dilewati pemicu jurnal tanpa galat apa pun.
      expect(layar, contains("const _discountMethod = 'discount'"));
      expect(layar, contains("title: 'GL Diskon'"));
    });

    test('akun langganan hanya tampil untuk pembukuan KaataGo', () {
      // Resto tidak menagih siapa pun.
      expect(layar, contains('if (_untukPlatform)'));
      expect(layar, contains("title: 'GL Langganan'"));
    });

    test('penghitung akun mengikuti layar yang sedang dibuka', () {
      // Menghitung akun langganan untuk resto biasa membuat penandanya
      // selamanya berbunyi "2 akun belum dipetakan" — peringatan yang
      // tidak bisa dihilangkan mengajari orang mengabaikan seluruh
      // penandanya.
      expect(layar, contains('_metodeLayarIni.where'));
      expect(layar, contains('total: _metodeLayarIni.length'));
    });

    test('menyimpan tidak membuat baris kosong', () {
      expect(layar, contains('if (code.isEmpty && name.isEmpty) continue'));
    });
  });

  group('label cara pelunasan', () {
    test('ditulis utuh, bukan sekadar "manual"', () {
      // Yang dibedakan adalah bagaimana tagihannya dinyatakan lunas,
      // bukan cara transfernya. "manual" sendirian membuat yang
      // membacanya menebak — dan menebak soal uang selalu mahal.
      final layar =
          File('lib/screens/super_admin_finance_screen.dart').readAsStringSync();
      expect(layar, contains("'Lunas via VA'"));
      expect(layar, contains("'Dikonfirmasi manual'"));
    });
  });


  group('GL Diskon punya nilai bawaan di tiap resto', () {
    final sql = File('supabase/gl_discount_backfill.sql').readAsStringSync();

    test('resto biasa dapat 2200002', () {
      expect(sql, contains("'discount', '2200002', 'GL Diskon Penjualan'"));
    });

    test('KaataGo dapat 1100002 untuk diskon langganan', () {
      expect(sql, contains("'subscription_discount', '1100002'"));
    });

    test('baris kosong ikut diisi, bukan hanya yang belum ada', () {
      // `on conflict do nothing` tidak menyentuh baris yang sudah ada —
      // dan baris bernomor kosong persis sama akibatnya dengan baris
      // yang tidak ada: pemicu jurnal melewatkannya diam-diam.
      expect(sql, contains("coalesce(gl_code, '') = ''"));
    });

    test('nomornya tetap bisa diubah Finance', () {
      // Yang dijamin cuma tidak ada resto yang berjalan tanpa akun
      // diskon sama sekali.
      expect(sql, contains('tetap bisa diubah Finance'));
    });

    test('penyewa platform tidak ikut kebagian nomor resto', () {
      expect(sql, contains('where r.is_platform = false'));
    });
  });

  group('nama diskon di jurnal', () {
    test('jurnal diskon pesanan menyebut nama promonya', () {
      final sql = File('supabase/discounts.sql').readAsStringSync();
      expect(sql,
          contains("coalesce(nullif(new.discount_name, ''), 'Diskon')"));
    });

    test('nama promonya benar-benar tersimpan di pesanannya', () {
      // Deskripsi jurnal membacanya dari orders.discount_name; kalau
      // aplikasi tidak pernah mengisinya, jurnalnya jatuh ke kata
      // "Diskon" polos dan nama promonya hilang.
      for (final p in [
        'lib/providers/cart_provider.dart',
        'lib/providers/customer_cart_provider.dart',
      ]) {
        final isi = File(p).readAsStringSync();
        expect(isi, contains('discountName: applied?.discount.name'),
            reason: p);
        expect(isi, contains('discountAmount:'), reason: p);
      }
    });

    test('jurnal diskon langganan menyebut nama diskonnya', () {
      final sql = File('supabase/billing_journal_gross.sql').readAsStringSync();
      expect(sql,
          contains("coalesce(nullif(new.discount_name, ''), 'Diskon langganan')"));
    });
  });

}
