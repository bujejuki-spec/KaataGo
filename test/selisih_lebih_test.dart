import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:pos_app/models/cash_variance.dart';
import 'package:pos_app/utils/cash_balance.dart';

CashVariance _selisih({
  required int amount,
  bool lebih = false,
  bool lunas = false,
  String? resolution,
  String? settleMethod,
}) =>
    CashVariance(
      id: 'v-$amount-$lebih',
      restoId: 'r1',
      shiftId: 's1',
      employeeEmail: 'kasir@contoh.com',
      amount: amount,
      lebih: lebih,
      lunas: lunas,
      resolution: resolution,
      settleMethod: settleMethod,
      createdAt: DateTime(2026, 1, 1),
    );

void main() {
  final sql = File('supabase/cash_variance_lebih.sql').readAsStringSync();
  final layar =
      File('lib/screens/cashier_shift_screen.dart').readAsStringSync();

  group('Saldo Cash', () {
    // Uangnya ADA di laci — itulah artinya berlebih. Mengabaikannya
    // membuat Saldo Cash lebih kecil daripada yang bisa dihitung
    // tangan, dan setoran seluruh isi laci jadi melebihi saldonya.
    test('bertambah oleh selisih lebih yang belum selesai', () {
      expect(
        cashOnHand(
          cashIncome: 1000000,
          deposits: const [],
          pettyCash: const [],
          selisih: [_selisih(amount: 50000, lebih: true)],
        ),
        1050000,
      );
    });

    // Kasir menutup shift dengan menghitung uang fisik. Kelebihan yang
    // diakui sebagai pendapatan tetap berupa lembaran di laci — yang
    // berubah cuma pengakuannya di pembukuan.
    test('yang diakui pendapatan TETAP di laci', () {
      expect(
        cashOnHand(
          cashIncome: 1000000,
          deposits: const [],
          pettyCash: const [],
          selisih: [
            _selisih(
                amount: 50000,
                lebih: true,
                lunas: true,
                resolution: 'pendapatan'),
          ],
        ),
        1050000,
      );
    });

    // Pesanan yang barusan dimasukkan sudah membawa uangnya lewat
    // pemasukan tunai; menghitungnya lagi berarti dua kali.
    test('yang penjualannya sudah diinput berhenti dihitung', () {
      expect(
        cashOnHand(
          cashIncome: 1050000, // pesanannya sudah masuk ke pemasukan tunai
          deposits: const [],
          pettyCash: const [],
          selisih: [
            _selisih(
                amount: 50000,
                lebih: true,
                lunas: true,
                resolution: 'input_penjualan'),
          ],
        ),
        1050000,
      );
    });

    // Keduanya hidup di tabel yang sama sekarang; kalau penyaringnya
    // salah, yang lebih ikut mengurangi laci — persis kebalikan dari
    // yang benar.
    test('yang kurang tetap mengurangi, dan tidak tertukar', () {
      expect(
        cashOnHand(
          cashIncome: 1000000,
          deposits: const [],
          pettyCash: const [],
          selisih: [
            _selisih(amount: 30000),
            _selisih(amount: 50000, lebih: true),
          ],
        ),
        1020000,
      );
    });
  });

  group('jurnalnya', () {
    // Titipan, bukan pendapatan: selisih lebih paling sering berarti
    // penjualan yang belum diinput, dan mengakuinya sebagai pendapatan
    // saat itu juga membuatnya terhitung dua kali.
    test('selisih lebih dikreditkan ke GL Selisih Kasir, bukan pendapatan',
        () {
      expect(sql, contains("'lebih'"));
      final trigger = sql.substring(sql.indexOf('function journal_cash_variance'));
      expect(trigger.substring(0, trigger.indexOf(r'$$;')),
          contains("when v_selisih < 0 then 'debit' else 'credit' end"));
    });

    test('keduanya melahirkan barisnya sendiri', () {
      final trigger = sql.substring(sql.indexOf('function journal_cash_variance'));
      final badan = trigger.substring(0, trigger.indexOf(r'$$;'));
      expect(badan, contains('insert into cash_variances'));
      expect(badan, isNot(contains('if v_selisih < 0 then\n    insert')));
    });

    // Kalau penjualannya sudah diinput, pesanan itu membawa jurnal
    // pendapatannya sendiri — kredit tandingan di sini akan menghitung
    // uang yang sama dua kali.
    test('input_penjualan hanya melepas titipannya', () {
      final fn = sql.substring(sql.indexOf('function resolve_cash_overage'));
      final badan = fn.substring(0, fn.indexOf(r'$$;'));
      expect(badan, contains("if p_cara = 'pendapatan' then"));
      expect(badan, contains("'other_income'"));
    });

    test('bayar selisih menolak yang lebih', () {
      final fn = sql.substring(sql.indexOf('function settle_cash_variance'));
      expect(fn.substring(0, fn.indexOf(r'$$;')),
          contains("if v_row.kind <> 'kurang' then"));
    });

    // Memutuskan uang tak dikenal jadi pendapatan adalah keputusan
    // pembukuan, bukan operasional.
    test('yang lebih hanya boleh diselesaikan Owner dan Finance', () {
      final fn = sql.substring(sql.indexOf('function resolve_cash_overage'));
      expect(fn.substring(0, fn.indexOf(r'$$;')),
          contains("array['owner', 'finance']"));
    });
  });

  group('layarnya', () {
    // Satu daftar berjudul "Selisih Belum Dibayar" membuat separuhnya
    // salah dibaca, dan tombol Bayar Selisih di sana pasti ditolak
    // server.
    test('dua daftar terpisah, bukan satu', () {
      expect(layar, contains("'Selisih Kurang — Belum Dibayar'"));
      expect(layar, contains("'Selisih Lebih — Belum Ditelusuri'"));
      expect(layar, contains('_lebihBelumSelesai'));
      expect(layar, contains('!v.lunas && !v.lebih'));
    });

    test('dua jalan keluar untuk yang lebih', () {
      expect(layar, contains("'input_penjualan'"));
      expect(layar, contains("'pendapatan'"));
      expect(layar, contains('selesaikanSelisihLebih('));
    });

    test('tombolnya lebih sempit daripada Bayar Selisih', () {
      expect(layar, contains('bool get _bolehTelusuri'));
      final blok = layar.substring(layar.indexOf('bool get _bolehTelusuri'));
      expect(blok.substring(0, blok.indexOf('}')), isNot(contains('isAdmin')));
    });

    test('rincian yang sudah ditutup menyebut caranya', () {
      expect(layar, contains('tagihan.caraSelesai'));
    });
  });

  // Uang yang hilang dari laci tidak pernah kembali ke laci kalau
  // dibayar lewat transfer; yang bertambah rekening merchant.
  group('selisih kurang dibayar transfer', () {
    test('Saldo Cash tetap dikurangi, selamanya', () {
      expect(
        cashOnHand(
          cashIncome: 1000000,
          deposits: const [],
          pettyCash: const [],
          selisih: [
            _selisih(
                amount: 30000,
                lunas: true,
                resolution: 'dibayar',
                settleMethod: 'transfer'),
          ],
        ),
        970000,
      );
    });

    test('yang dibayar tunai pulih seperti biasa', () {
      expect(
        cashOnHand(
          cashIncome: 1000000,
          deposits: const [],
          pettyCash: const [],
          selisih: [
            _selisih(
                amount: 30000,
                lunas: true,
                resolution: 'dibayar',
                settleMethod: 'cash'),
          ],
        ),
        1000000,
      );
    });

    test('yang transfer masuk hitungan Saldo Non Cash', () {
      final daftar = [
        _selisih(
            amount: 30000,
            lunas: true,
            resolution: 'dibayar',
            settleMethod: 'transfer'),
        _selisih(
            amount: 20000,
            lunas: true,
            resolution: 'dibayar',
            settleMethod: 'cash'),
      ];
      expect(selisihDibayarTransfer(daftar), 30000);
    });

    test('layarnya menawarkan keduanya, dan Non Cash memakainya', () {
      expect(layar, contains("'Tunai — Masuk Laci'"));
      expect(layar, contains("'Transfer — Masuk Rekening'"));
      final saldo =
          File('lib/screens/finance_balance_screen.dart').readAsStringSync();
      expect(saldo, contains('selisihDibayarTransfer(_selisih)'));
    });
  });
}
