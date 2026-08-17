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
      expect(sql, contains("new.amount, 'credit'"));
      expect(sql, contains("new.discount_amount, 'debit'"));
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

}
