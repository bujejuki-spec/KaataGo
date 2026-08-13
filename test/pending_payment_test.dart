import 'package:flutter_test/flutter_test.dart';
import 'package:pos_app/models/customer_order.dart';

CustomerOrder _order({
  required OrderSource source,
  required OrderPaymentStatus status,
  String? method,
  int total = 50000,
  int? cashReceived,
}) {
  return CustomerOrder(
    id: 'abcdef12-3456-7890-abcd-ef1234567890',
    createdAt: DateTime.utc(2026, 8, 14, 3),
    items: const [],
    total: total,
    paymentStatus: status,
    customerLabel: 'tamu@example.com',
    restoId: 'resto-1',
    source: source,
    paymentMethod: method,
    cashReceived: cashReceived,
  );
}

void main() {
  group('isPendingCashPayment', () {
    test('pesanan mandiri tunai yang belum dibayar masuk antrean', () {
      expect(
        _order(
          source: OrderSource.customer,
          status: OrderPaymentStatus.pending,
          method: 'cash',
        ).isPendingCashPayment,
        isTrue,
      );
    });

    test('yang sudah dibayar keluar dari antrean', () {
      expect(
        _order(
          source: OrderSource.customer,
          status: OrderPaymentStatus.paid,
          method: 'cash',
        ).isPendingCashPayment,
        isFalse,
      );
    });

    test('pesanan QRIS yang belum dibayar bukan urusan kasir', () {
      // Yang ini diselesaikan pelanggan sendiri di layar QRIS-nya.
      // Memunculkannya di Pending Payment akan membuat kasir menagih
      // uang tunai untuk tagihan yang sedang dibayar lewat QR.
      expect(
        _order(
          source: OrderSource.customer,
          status: OrderPaymentStatus.pending,
          method: 'qris',
        ).isPendingCashPayment,
        isFalse,
      );
    });

    test('pesanan lama tanpa cara bayar tidak ikut tertagih', () {
      expect(
        _order(
          source: OrderSource.customer,
          status: OrderPaymentStatus.pending,
        ).isPendingCashPayment,
        isFalse,
      );
    });

    test('pesanan yang diinput kasir tidak masuk antrean', () {
      // Kasir menerima uangnya di tempat saat mencatatnya. Yang pending
      // di sana adalah data setengah jadi, bukan tagihan yang menunggu.
      expect(
        _order(
          source: OrderSource.kasir,
          status: OrderPaymentStatus.pending,
          method: 'cash',
        ).isPendingCashPayment,
        isFalse,
      );
    });
  });

  group('changeDue', () {
    test('belum ada uang diterima berarti belum ada kembalian', () {
      expect(
        _order(source: OrderSource.customer, status: OrderPaymentStatus.pending)
            .changeDue,
        isNull,
      );
    });

    test('kembalian dihitung dari uang diterima dikurangi total', () {
      final order = _order(
        source: OrderSource.customer,
        status: OrderPaymentStatus.paid,
        method: 'cash',
        total: 47000,
        cashReceived: 50000,
      );
      expect(order.changeDue, 3000);
    });

    test('uang pas berarti kembalian nol, bukan null', () {
      final order = _order(
        source: OrderSource.customer,
        status: OrderPaymentStatus.paid,
        method: 'cash',
        total: 50000,
        cashReceived: 50000,
      );
      expect(order.changeDue, 0);
    });
  });

  group('serialisasi', () {
    test('cash_received ikut terbaca dan tertulis', () {
      final order = _order(
        source: OrderSource.customer,
        status: OrderPaymentStatus.paid,
        method: 'cash',
        cashReceived: 100000,
      );
      expect(order.toMap()['cash_received'], 100000);

      final parsed = CustomerOrder.fromMap({
        'id': 'x',
        'created_at': DateTime.utc(2026, 8, 14).toIso8601String(),
        'items': const [],
        'total': 50000,
        'payment_status': 'paid',
        'customer_label': 'a@b.com',
        'resto_id': 'resto-1',
        'source': 'customer',
        'payment_method': 'cash',
        'cash_received': 100000,
      });
      expect(parsed.cashReceived, 100000);
      expect(parsed.changeDue, 50000);
    });

    test('pesanan tanpa uang diterima tidak mengirim kolomnya', () {
      final map = _order(
        source: OrderSource.customer,
        status: OrderPaymentStatus.pending,
        method: 'cash',
      ).toMap();
      // Bukan sekadar rapi: mengirim null akan menimpa nominal yang
      // sudah tercatat kalau baris yang sama pernah dilunasi.
      expect(map.containsKey('cash_received'), isFalse);
    });
  });
}
