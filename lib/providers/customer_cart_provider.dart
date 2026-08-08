import 'package:flutter/foundation.dart';

import '../db/firestore_product_repository.dart';
import '../db/order_repository.dart';
import '../db/session_repository.dart';
import '../models/cart_item.dart';
import '../models/customer_order.dart';
import '../models/order_type.dart';
import '../models/product.dart';

/// Cart for the customer self-order flow. Separate from [CartProvider]
/// (used by the cashier) because checkout here creates a Firestore order
/// instead of a local SQLite transaction, and only ever pays via QRIS.
class CustomerCartProvider extends ChangeNotifier {
  final _orderRepo = OrderRepository();
  final _firestoreProductRepo = FirestoreProductRepository();
  final _sessionRepo = SessionRepository();

  final List<CartItem> _items = [];
  List<CartItem> get items => List.unmodifiable(_items);

  int get total => _items.fold(0, (sum, item) => sum + item.subtotal);
  int get itemCount => _items.fold(0, (sum, item) => sum + item.quantity);

  int quantityOf(String productId) {
    final match = _items.where((i) => i.product.id == productId);
    return match.isEmpty ? 0 : match.first.quantity;
  }

  void setQuantity(
    Product product,
    int quantity, {
    Map<String, String>? selectedLevels,
    String? notes,
  }) {
    final index = _items.indexWhere((i) => i.product.id == product.id);
    if (quantity <= 0) {
      if (index != -1) _items.removeAt(index);
    } else if (index != -1) {
      _items[index].quantity = quantity;
      if (selectedLevels != null) _items[index].selectedLevels = selectedLevels;
      _items[index].notes = notes;
    } else {
      _items.add(CartItem(
        product: product,
        quantity: quantity,
        selectedLevels: selectedLevels,
        notes: notes,
      ));
    }
    notifyListeners();
  }

  /// Currently selected level(s) for [productId] in the cart, if any —
  /// used to pre-fill the quantity dialog when re-opening it.
  Map<String, String> selectedLevelsOf(String productId) {
    final match = _items.where((i) => i.product.id == productId);
    return match.isEmpty ? {} : match.first.selectedLevels;
  }

  /// Currently saved note for [productId] in the cart, if any.
  String? notesOf(String productId) {
    final match = _items.where((i) => i.product.id == productId);
    return match.isEmpty ? null : match.first.notes;
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
    int? tableNumber,
    required String sessionId,
    required String restoId,
    OrderType orderType = OrderType.dineIn,
    String? customerName,
  }) async {
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
      total: total,
      paymentStatus: OrderPaymentStatus.pending,
      customerLabel: customerLabel,
      tableNumber: tableNumber,
      sessionId: sessionId,
      restoId: restoId,
      orderType: orderType,
      customerName: customerName,
    );
    final id = await _orderRepo.create(order);

    // Reserve stock immediately (same behavior as the cashier checkout) so
    // two customers can't both order the last unit of something.
    final stockDeltas = <String, int>{};
    for (final item in _items) {
      stockDeltas[item.product.id] = item.quantity;
    }
    await _firestoreProductRepo.decrementStockForOrder(stockDeltas);

    // Reset the backend's "5 minutes idle" clock for this session so the
    // Cloud Function doesn't end it while a fresh order is still cooking.
    _sessionRepo.touchLastOrder(sessionId).catchError((_) {});

    clear();
    return id;
  }
}
