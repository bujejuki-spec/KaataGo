import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../db/firestore_product_repository.dart';
import '../db/order_repository.dart';
import '../db/session_repository.dart';
import '../models/cart_item.dart';
import '../models/customer_order.dart';
import '../models/order_type.dart';
import '../models/product.dart';
import '../utils/tax_calculator.dart';

/// Cart for the customer self-order flow. Separate from [CartProvider]
/// (used by the cashier) because checkout here creates a Firestore order
/// instead of a local SQLite transaction, and only ever pays via QRIS.
class CustomerCartProvider extends ChangeNotifier {
  final _orderRepo = OrderRepository();
  final _firestoreProductRepo = FirestoreProductRepository();
  final _sessionRepo = SessionRepository();

  final _uuid = const Uuid();

  final List<CartItem> _items = [];
  List<CartItem> get items => List.unmodifiable(_items);

  /// Sum of the menu prices shown to the customer (original + PPN).
  /// Service isn't in here — it lands at checkout, and only for Dine In.
  int get total => _items.fold(0, (sum, item) => sum + menuSubtotalOf(item));

  /// Sum of the original, pre-charge prices.
  int get baseTotal => _items.fold(0, (sum, item) => sum + item.subtotal);

  /// Resto-wide charge rates, pushed in by whichever ordering screen is
  /// open. Menu prices carry PPN only; service is a per-bill Dine In
  /// charge worked out at checkout, so it never changes a line's price.
  double ppnPercent = 0;
  double servicePercent = 0;

  void setRates({required double ppn, required double service}) {
    if (ppnPercent == ppn && servicePercent == service) return;
    ppnPercent = ppn;
    servicePercent = service;
    notifyListeners();
  }

  /// What a line costs on the menu — original price plus PPN.
  int menuSubtotalOf(CartItem item) =>
      menuPrice(item.effectiveUnitPrice,
          ppnPercent: ppnPercent, ppnExempt: item.product.ppnExempt) *
      item.quantity;

  /// Splits the bill for [orderType], building up from original prices.
  TaxBreakdown chargesFor(OrderType orderType) => calculateCharges(
        lines: _items
            .map((i) => TaxableLine(
                  baseTotal: i.subtotal,
                  ppnExempt: i.product.ppnExempt,
                  serviceExempt: i.product.serviceExempt,
                ))
            .toList(),
        ppnPercent: ppnPercent,
        servicePercent: servicePercent,
        serviceApplies: orderType == OrderType.dineIn,
      );

  int get itemCount => _items.fold(0, (sum, item) => sum + item.quantity);

  /// How many of [productId] are in the cart across every variant —
  /// used by the grid badge, where "2" should mean two plates of nasi
  /// goreng regardless of how many lines they're split over.
  int quantityOf(String productId) => _items
      .where((i) => i.product.id == productId)
      .fold(0, (sum, i) => sum + i.quantity);

  /// Adds a configured line. Merges into an existing line only when the
  /// options and note match exactly — otherwise the same dish ordered
  /// two different ways stays as two separate lines.
  void addLine(
    Product product, {
    int quantity = 1,
    Map<String, String>? selectedLevels,
    String? notes,
  }) {
    if (quantity <= 0) return;
    final candidate = CartItem(
      lineId: _uuid.v4(),
      product: product,
      quantity: quantity,
      selectedLevels: selectedLevels,
      notes: notes,
    );
    final existing = _items.where((i) => i.variantKey == candidate.variantKey);
    if (existing.isNotEmpty) {
      existing.first.quantity += quantity;
    } else {
      _items.add(candidate);
    }
    notifyListeners();
  }

  /// Edits one line in place. A quantity of 0 or less deletes it.
  void updateLine(
    String lineId, {
    required int quantity,
    Map<String, String>? selectedLevels,
    String? notes,
  }) {
    final index = _items.indexWhere((i) => i.lineId == lineId);
    if (index == -1) return;
    if (quantity <= 0) {
      _items.removeAt(index);
      notifyListeners();
      return;
    }
    final item = _items[index];
    item.quantity = quantity;
    if (selectedLevels != null) item.selectedLevels = selectedLevels;
    item.notes = notes;

    // Editing a line's options can turn it into a duplicate of another
    // line — fold them together rather than leaving two identical rows.
    final twin = _items.where((i) => i.lineId != lineId && i.variantKey == item.variantKey);
    if (twin.isNotEmpty) {
      twin.first.quantity += item.quantity;
      _items.removeAt(index);
    }
    notifyListeners();
  }

  void incrementLine(String lineId) {
    final item = _items.where((i) => i.lineId == lineId);
    if (item.isEmpty) return;
    item.first.quantity++;
    notifyListeners();
  }

  /// Steps a line down, deleting it when it would hit zero.
  void decrementLine(String lineId) {
    final index = _items.indexWhere((i) => i.lineId == lineId);
    if (index == -1) return;
    if (_items[index].quantity > 1) {
      _items[index].quantity--;
    } else {
      _items.removeAt(index);
    }
    notifyListeners();
  }

  void removeLine(String lineId) {
    _items.removeWhere((i) => i.lineId == lineId);
    notifyListeners();
  }

  void clear() {
    _items.clear();
    notifyListeners();
  }

  /// Places the order in Firestore with status "pending" — it shows up
  /// immediately in the employee app's "Pesanan Masuk" list — and returns
  /// the order id so the QR screen can mark it paid once confirmed.
  ///
  /// [sessionId] and [restoId] come from [TableSessionProvider] —
  /// required so the order can be tied to the right restaurant and so
  /// the customer can track its status afterward without an account.
  /// [tableNumber] is null for a [OrderType.takeAway] order (no table
  /// involved); required for [OrderType.dineIn]. [customerName] is
  /// mandatory (validated by the checkout screen, not here) for
  /// take-away — who to call out when it's ready.
  Future<String> placeOrder(
    String customerLabel, {
    String? tableNumber,
    required String sessionId,
    required String restoId,
    OrderType orderType = OrderType.dineIn,
    String? customerName,
  }) async {
    final tax = chargesFor(orderType);

    final order = CustomerOrder(
      id: '', // assigned by Firestore
      createdAt: DateTime.now(),
      items: _items
          .map((i) => CustomerOrderItem(
                productId: i.product.id,
                productName: i.product.name,
                price: i.effectiveUnitPrice,
                quantity: i.quantity,
                notes: i.noteSummary,
              ))
          .toList(),
      total: tax.total,
      paymentStatus: OrderPaymentStatus.pending,
      customerLabel: customerLabel,
      // Customer self-orders are always paid via QRIS — set explicitly
      // (rather than left null) so it relates directly to gl_accounts
      // the same way a Kasir sale's payment_method does.
      paymentMethod: 'qris',
      tableNumber: tableNumber,
      sessionId: sessionId,
      restoId: restoId,
      orderType: orderType,
      customerName: customerName,
      baseAmount: tax.base,
      serviceAmount: tax.service,
      ppnAmount: tax.ppn,
    );
    final id = await _orderRepo.create(order);

    // Reserve stock immediately (same behavior as the cashier checkout) so
    // two customers can't both order the last unit of something.
    final stockDeltas = <String, int>{};
    for (final item in _items) {
      // Accumulated, not assigned: the same product can now occupy
      // several lines (pedas and tidak pedas), and overwriting would
      // deduct only the last line's quantity from stock.
      stockDeltas.update(item.product.id, (q) => q + item.quantity,
          ifAbsent: () => item.quantity);
    }
    await _firestoreProductRepo.decrementStockForOrder(stockDeltas);

    // Reset the backend's "5 minutes idle" clock for this session so the
    // Cloud Function doesn't end it while a fresh order is still cooking.
    _sessionRepo.touchLastOrder(sessionId).catchError((_) {});

    clear();
    return id;
  }
}
