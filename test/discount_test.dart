import 'package:flutter_test/flutter_test.dart';
import 'package:pos_app/models/discount.dart';
import 'package:pos_app/utils/promo_period.dart';

final _hariIni = DateTime(2026, 8, 16);

Discount _d({
  String id = 'd1',
  DiscountBasis basis = DiscountBasis.products,
  DiscountKind kind = DiscountKind.percent,
  int value = 10,
  List<String> productIds = const ['p1'],
  int minPurchase = 0,
  MinCompare compare = MinCompare.atLeast,
  DateTime? startsOn,
  DateTime? endsOn,
  bool active = true,
}) =>
    Discount(
      id: id,
      restoId: 'r1',
      name: 'Promo $id',
      basis: basis,
      kind: kind,
      value: value,
      productIds: productIds,
      minPurchase: minPurchase,
      compare: compare,
      startsOn: startsOn,
      endsOn: endsOn,
      active: active,
      createdAt: _hariIni,
    );

void main() {
  group('potongan', () {
    test('persen dibulatkan ke bawah', () {
      expect(_d(value: 10).amountFor(40793), 4079);
    });

    test('tidak pernah melebihi tagihannya sendiri', () {
      // Diskon rupiah tetap yang lebih besar daripada tagihannya
      // menghasilkan total negatif — uang yang harus dikembalikan resto
      // kepada orang yang belum membayar apa pun.
      final potong50rb = _d(kind: DiscountKind.amount, value: 50000);
      expect(potong50rb.amountFor(20000), 20000);
    });
  });

  group('minimum belanja', () {
    test('≥ memberi diskon pada nilai yang pas', () {
      final d = _d(
        basis: DiscountBasis.minPurchase,
        minPurchase: 200000,
        compare: MinCompare.atLeast,
      );
      expect(d.meetsMinimum(200000), isTrue);
      expect(d.meetsMinimum(199999), isFalse);
    });

    test('> menolak nilai yang pas', () {
      // Yang membedakan keduanya cuma satu transaksi — yang nilainya
      // persis di batas — dan justru itu yang paling sering jadi
      // perselisihan di meja kasir.
      final d = _d(
        basis: DiscountBasis.minPurchase,
        minPurchase: 200000,
        compare: MinCompare.moreThan,
      );
      expect(d.meetsMinimum(200000), isFalse);
      expect(d.meetsMinimum(200001), isTrue);
    });
  });

  group('masa berlaku', () {
    test('hari terakhirnya masih berlaku penuh', () {
      // "Promo sampai 31 Agustus" berarti sampai tutup toko tanggal 31,
      // bukan sampai pukul 00:00 tanggal 31.
      final d = _d(endsOn: DateTime(2026, 8, 16));
      expect(d.isLive(DateTime(2026, 8, 16, 23, 59)), isTrue);
      expect(d.isLive(DateTime(2026, 8, 17)), isFalse);
    });

    test('yang belum mulai tidak ikut dihitung', () {
      final d = _d(startsOn: DateTime(2026, 8, 20));
      expect(d.isLive(_hariIni), isFalse);
      expect(d.period.isScheduled(_hariIni), isTrue);
    });

    test('yang dimatikan tidak berlaku walau tanggalnya pas', () {
      expect(_d(active: false).isLive(_hariIni), isFalse);
    });
  });

  group('pemilihan diskon', () {
    int subtotal(String id) => {'p1': 50000, 'p2': 30000}[id] ?? 0;

    test('bundling menjumlahkan menunya dulu, baru dipotong', () {
      // Kalau tiap baris dipotong sendiri-sendiri, diskon rupiah tetap
      // akan terkalikan sebanyak menu yang ikut promo.
      final bundling = _d(
        kind: DiscountKind.amount,
        value: 10000,
        productIds: ['p1', 'p2'],
      );

      final hasil = bestDiscountFor(
        discounts: [bundling],
        total: 80000,
        subtotalOf: subtotal,
        productIds: {'p1', 'p2'},
        now: _hariIni,
      );

      expect(hasil!.amount, 10000);
    });

    test('diskon menu hanya mengenai menu yang ikut promo', () {
      final d = _d(value: 50, productIds: ['p2']);

      final hasil = bestDiscountFor(
        discounts: [d],
        total: 80000,
        subtotalOf: subtotal,
        productIds: {'p1', 'p2'},
        now: _hariIni,
      );

      // 50% dari 30.000 (harga p2), bukan dari 80.000.
      expect(hasil!.amount, 15000);
    });

    test('hanya satu diskon yang dipakai — yang paling menguntungkan', () {
      // Menumpuk terdengar murah hati sampai dua promo yang kebetulan
      // berlaku bersamaan melebihi harga barangnya.
      final kecil = _d(id: 'a', value: 10, productIds: ['p1']);
      final besar = _d(
        id: 'b',
        basis: DiscountBasis.minPurchase,
        minPurchase: 50000,
        value: 20,
      );

      final hasil = bestDiscountFor(
        discounts: [kecil, besar],
        total: 80000,
        subtotalOf: subtotal,
        productIds: {'p1'},
        now: _hariIni,
      );

      expect(hasil!.discount.id, 'b');
      expect(hasil.amount, 16000);
    });

    test('tidak ada yang cocok berarti tidak ada potongan', () {
      final hasil = bestDiscountFor(
        discounts: [_d(productIds: ['p9'])],
        total: 80000,
        subtotalOf: subtotal,
        productIds: {'p1'},
        now: _hariIni,
      );
      expect(hasil, isNull);
    });
  });

  group('batas tanggal', () {
    test('mulai tidak boleh mundur ke belakang', () {
      final error = validatePeriod(
        startsOn: DateTime(2026, 8, 15),
        now: _hariIni,
      );
      expect(error, isNotNull);
    });

    test('berakhir harus setelah hari ini', () {
      expect(validatePeriod(endsOn: _hariIni, now: _hariIni), isNotNull);
      expect(
        validatePeriod(endsOn: DateTime(2026, 8, 17), now: _hariIni),
        isNull,
      );
    });

    test('berakhir harus setelah mulai', () {
      final error = validatePeriod(
        startsOn: DateTime(2026, 8, 20),
        endsOn: DateTime(2026, 8, 18),
        now: _hariIni,
      );
      expect(error, isNotNull);
    });
  });
}
