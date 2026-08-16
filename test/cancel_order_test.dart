import 'package:flutter_test/flutter_test.dart';
import 'package:pos_app/models/customer_order.dart';

CustomerOrder _order({
  OrderSource source = OrderSource.customer,
  OrderPaymentStatus status = OrderPaymentStatus.pending,
  KitchenStatus kitchen = KitchenStatus.waiting,
  String? method = 'cash',
}) =>
    CustomerOrder(
      id: 'o1',
      createdAt: DateTime(2026, 8, 16),
      items: const [],
      total: 25000,
      paymentStatus: status,
      customerLabel: 'orang@contoh.com',
      restoId: 'r1',
      source: source,
      paymentMethod: method,
      kitchenStatus: kitchen,
    );

void main() {
  group('pembatalan oleh pelanggan', () {
    test('boleh selama belum dibayar dan dapur belum mulai', () {
      expect(_order().canBeCancelledByCustomer, isTrue);
    });

    test('tidak boleh setelah dapur mulai memasak', () {
      // Bahan yang sudah terpakai adalah kerugian yang nyata, dan yang
      // menanggungnya bukan pihak yang menekan tombolnya.
      expect(
        _order(kitchen: KitchenStatus.onProgress).canBeCancelledByCustomer,
        isFalse,
      );
    });

    test('tidak boleh setelah dibayar', () {
      expect(
        _order(status: OrderPaymentStatus.paid).canBeCancelledByCustomer,
        isFalse,
      );
    });

    test('pesanan yang diinput kasir bukan urusan tombol ini', () {
      expect(
        _order(source: OrderSource.kasir).canBeCancelledByCustomer,
        isFalse,
      );
    });

    test('yang sudah dibatalkan tidak bisa dibatalkan lagi', () {
      final batal = _order(status: OrderPaymentStatus.cancelled);
      expect(batal.canBeCancelledByCustomer, isFalse);
      expect(batal.isCancelled, isTrue);
      expect(batal.isVoid, isTrue);
    });
  });

  group('menunggu pembayaran di layar dapur', () {
    test('pesanan QRIS yang belum dibayar ikut terhitung', () {
      // Inilah yang bocor ke tab "Baru": penanda lama hanya mengenali
      // yang memilih bayar tunai, jadi pesanan QRIS yang ditinggal tanpa
      // dibayar terlihat seolah sudah beres.
      expect(_order(method: 'qris').isAwaitingPayment, isTrue);
      expect(_order(method: 'qris').isPendingCashPayment, isFalse);
    });

    test('pesanan tunai yang belum dibayar tetap terhitung', () {
      expect(_order().isAwaitingPayment, isTrue);
    });

    test('yang sudah dibayar tidak ikut', () {
      expect(_order(status: OrderPaymentStatus.paid).isAwaitingPayment, isFalse);
    });

    test('pesanan kasir tidak pernah menunggu pembayaran', () {
      // Diinput saat uangnya sudah diterima.
      expect(_order(source: OrderSource.kasir).isAwaitingPayment, isFalse);
    });

    test('yang batal atau hangus tidak muncul di dapur', () {
      expect(_order(status: OrderPaymentStatus.cancelled).isVoid, isTrue);
      expect(_order(status: OrderPaymentStatus.expired).isVoid, isTrue);
      expect(_order().isVoid, isFalse);
    });
  });
}
