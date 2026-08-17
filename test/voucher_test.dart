import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pos_app/models/voucher.dart';

Voucher _v({
  VoucherKind kind = VoucherKind.percent,
  int value = 10,
  int maxDiscount = 0,
  int minPurchase = 0,
  List<String> restoIds = const [],
  int quotaTotal = 0,
  int used = 0,
  DateTime? startsOn,
  DateTime? endsOn,
  bool active = true,
}) =>
    Voucher(
      id: 'v1',
      code: 'HEMAT10',
      name: 'Promo Pengguna Baru',
      kind: kind,
      value: value,
      maxDiscount: maxDiscount,
      minPurchase: minPurchase,
      restoIds: restoIds,
      quotaTotal: quotaTotal,
      used: used,
      startsOn: startsOn,
      endsOn: endsOn,
      active: active,
      createdAt: DateTime(2026, 8, 1),
    );

void main() {
  group('potongan voucher', () {
    test('persen dibulatkan ke bawah', () {
      expect(_v(value: 10).amountFor(40793), 4079);
    });

    test('batas atas menahan potongan persen', () {
      // Tanpa batas ini, "diskon 20%" pada tagihan sejuta rupiah adalah
      // dua ratus ribu yang keluar dari saldo KaataGo untuk satu
      // transaksi.
      expect(_v(value: 20, maxDiscount: 20000).amountFor(1000000), 20000);
      expect(_v(value: 20).amountFor(1000000), 200000);
    });

    test('potongan rupiah tetap', () {
      expect(_v(kind: VoucherKind.amount, value: 5000).amountFor(50000), 5000);
    });

    test('tidak pernah melebihi tagihannya sendiri', () {
      expect(
        _v(kind: VoucherKind.amount, value: 90000).amountFor(50000),
        50000,
      );
    });

    test('minimal belanja belum terpenuhi berarti nol', () {
      expect(_v(minPurchase: 50000).amountFor(30000), 0);
      expect(_v(minPurchase: 50000).amountFor(50000), 5000);
    });
  });

  group('masa berlaku dan kuota', () {
    test('yang dimatikan tidak berlaku walau tanggalnya pas', () {
      expect(_v(active: false).isLive(DateTime(2026, 8, 17)), isFalse);
    });

    test('belum mulai belum berlaku', () {
      final v = _v(startsOn: DateTime(2026, 9, 1));
      expect(v.isLive(DateTime(2026, 8, 17)), isFalse);
      expect(v.isLive(DateTime(2026, 9, 1)), isTrue);
    });

    test('hari terakhir masih berlaku penuh', () {
      final v = _v(endsOn: DateTime(2026, 8, 31));
      expect(v.isLive(DateTime(2026, 8, 31)), isTrue);
      expect(v.isLive(DateTime(2026, 9, 1)), isFalse);
    });

    test('kuota habis dikenali', () {
      expect(_v(quotaTotal: 100, used: 100).kuotaHabis, isTrue);
      expect(_v(quotaTotal: 100, used: 99).kuotaHabis, isFalse);
      expect(_v(used: 9999).kuotaHabis, isFalse); // tanpa kuota
    });

    test('sisa kuota null kalau tanpa batas', () {
      expect(_v().sisaKuota, isNull);
      expect(_v(quotaTotal: 10, used: 4).sisaKuota, 6);
    });

    test('kosongnya daftar resto berarti semua resto', () {
      expect(_v().berlakuDiSemuaResto, isTrue);
      expect(_v(restoIds: const ['r1']).berlakuDiSemuaResto, isFalse);
    });
  });

  group('bentuk data', () {
    test('kode selalu tersimpan huruf besar', () {
      // "hemat10" dan "HEMAT10" harus voucher yang sama — yang
      // mengetiknya sedang lapar dan berdiri di depan kasir.
      final v = Voucher(
        id: 'v1',
        code: ' hemat10 ',
        name: 'A',
        value: 10,
        createdAt: DateTime(2026, 8, 1),
      );
      expect(v.toMap()['code'], 'HEMAT10');
    });

    test('bolak-balik lewat peta', () {
      final map = _v(quotaTotal: 50, minPurchase: 25000).toMap();
      final lagi = Voucher.fromMap(
          {...map, 'created_at': DateTime(2026, 8, 1).toIso8601String()},
          used: 3);
      expect(lagi.quotaTotal, 50);
      expect(lagi.minPurchase, 25000);
      expect(lagi.used, 3);
    });

    test('jawaban server yang ditolak selalu menyebut alasannya', () {
      // "Voucher tidak berlaku" tanpa sebab membuat orang mencoba lagi
      // dengan kode yang sama, lalu menyalahkan aplikasinya.
      const q = VoucherQuote(reason: 'Kuota voucher ini sudah habis');
      expect(q.diterima, isFalse);
      expect(q.reason, isNotEmpty);
    });

    test('jawaban diterima harus punya id dan nominal', () {
      expect(const VoucherQuote(voucherId: 'v1', amount: 5000).diterima, isTrue);
      expect(const VoucherQuote(voucherId: 'v1', amount: 0).diterima, isFalse);
      expect(const VoucherQuote(amount: 5000).diterima, isFalse);
    });
  });

  group('aturan di server', () {
    final sql = File('supabase/vouchers.sql').readAsStringSync();

    test('nominalnya dihitung server, bukan dikirim aplikasi', () {
      // Ini uang KaataGo sendiri yang keluar.
      expect(sql, contains('function voucher_quote'));
      final repo = File('lib/db/voucher_repository.dart').readAsStringSync();
      expect(repo, contains("rpc('voucher_quote'"));
    });

    test('kode dicocokkan tanpa peduli huruf besar-kecil', () {
      expect(sql, contains('upper(trim(p_code))'));
    });

    test('tiap penolakan membawa alasannya', () {
      for (final alasan in [
        'Kode voucher tidak ditemukan',
        'Voucher ini sudah tidak berlaku',
        'Voucher ini belum berlaku',
        'Voucher ini tidak berlaku di resto ini',
        'Kuota voucher ini sudah habis',
        'Voucher ini sudah kamu pakai',
      ]) {
        expect(sql, contains(alasan), reason: alasan);
      }
    });

    test('pemakaian dicatat lewat pemicu, bukan panggilan terpisah', () {
      // Panggilan terpisah bisa gagal atau tidak pernah dikirim, dan
      // yang tertinggal adalah voucher yang memotong tagihan tanpa
      // pernah terhitung kuotanya.
      expect(sql, contains('after insert on orders'));
      expect(sql, contains('function log_voucher_redemption'));
    });

    test('tidak mencatat dua kali untuk pesanan yang sama', () {
      expect(sql, contains('select 1 from voucher_redemptions where order_id = new.id'));
    });

    test('biayanya masuk pembukuan KaataGo, bukan resto', () {
      expect(sql, contains("_gl_account_for('kaatago', 'voucher')"));
      expect(sql, contains("'kaatago',"));
    });

    test('dua kaki jurnal: biaya didebit, kantongnya dikredit', () {
      // Satu kaki saja membuat saldo KaataGo terlihat utuh padahal
      // uangnya sudah dijanjikan keluar.
      expect(sql, contains("new.voucher_amount, 'debit'"));
      expect(sql, contains("new.voucher_amount, 'credit'"));
    });

    test('hanya Super Admin yang membuat voucher', () {
      expect(sql, contains('"vouchers: super admin write"'));
    });

    test('vouchernya bisa dibaca pelanggan', () {
      // Harus terlihat sebelum orangnya memutuskan memesan.
      expect(sql, contains('"vouchers: public read"'));
    });
  });
}
