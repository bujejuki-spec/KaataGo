import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../db/firestore_product_repository.dart';
import '../db/order_repository.dart';
import '../db/product_repository.dart';
import '../db/transaction_repository.dart';
import '../models/cart_item.dart';
import '../models/customer_order.dart';
import '../models/order_type.dart';
import '../models/product.dart';
import '../models/transaction.dart';

class CartProvider extends ChangeNotifier {
  final _productRepo = ProductRepository();
  final _firestoreProductRepo = FirestoreProductRepository();
  final _txRepo = TransactionRepository();
  final _orderRepo = OrderRepository();
  final _uuid = const Uuid();

  final List<CartItem> _items = [];
  List<CartItem> get items => List.unmodifiable(_items);

  int get total => _items.fold(0, (sum, item) => sum + item.subtotal);
  int get itemCount => _items.fold(0, (sum, item) => sum + item.quantity);

  /// How many of [productId] are currently in the cart. Used by the POS
  /// grid to highlight selected product cards and show a quantity badge.
  int quantityOf(String productId) {
    final match = _items.where((i) => i.product.id == productId);
    return match.isEmpty ? 0 : match.first.quantity;
  }

  void addProduct(Product product) {
    final existing = _items.where((i) => i.product.id == product.id);
    if (existing.isNotEmpty) {
      existing.first.quantity++;
    } else {
      _items.add(CartItem(product: product));
    }
    notifyListeners();
  }

  /// Sets the exact quantity (and, if provided, level selections/notes)
  /// for [product] in the cart (used by the quantity-entry popup on the
  /// POS grid). A quantity of 0 or less removes the item from the cart
  /// entirely.
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

  void decrement(String productId) {
    final index = _items.indexWhere((i) => i.product.id == productId);
    if (index == -1) return;
    if (_items[index].quantity > 1) {
      _items[index].quantity--;
    } else {
      _items.removeAt(index);
    }
    notifyListeners();
  }

  void remove(String productId) {
    _items.removeWhere((i) => i.product.id == productId);
    notifyListeners();
  }

  void clear() {
    _items.clear();
    notifyListeners();
  }

  static const _paymentLabels = {
    PaymentMethod.cash: 'Tunai',
    PaymentMethod.qris: 'QRIS',
    PaymentMethod.transfer: 'Transfer',
  };

  /// Finalizes the sale: saves the transaction, deducts stock, clears cart.
  /// This is the single "checkout" entry point — every payment method
  /// (cash, QRIS, transfer) flows through here so the reconciliation
  /// ledger stays consistent regardless of how the customer paid.
  ///
  /// [cashierLabel] (the logged-in Kasir/Admin's email), [tableNumber]
  /// and [restoId] (required at checkout) are used to mirror this sale
  /// into the shared Firestore "orders" feed so the Chef sees it
  /// alongside customer self-orders, with a table to deliver it to and
  /// scoped to the right restaurant. [tableNumber] is null for a
  /// [OrderType.takeAway] sale — no table involved.
  /// [customerName] is mandatory (validated by the checkout screen, not
  /// here) for [OrderType.takeAway] — the Kasir types in who to call out
  /// when it's ready, since there's no table to deliver it to.
  Future<PosTransaction> checkout(
    PaymentMethod method, {
    String? cashierLabel,
    int? tableNumber,
    required String restoId,
    OrderType orderType = OrderType.dineIn,
    String? customerName,
  }) async {
    final tx = PosTransaction(
      id: _uuid.v4(),
      createdAt: DateTime.now(),
      paymentMethod: method,
      total: total,
      orderType: orderType,
      customerName: customerName,
      items: _items
          .map((i) => TransactionItem(
                productId: i.product.id,
                productName: i.product.name,
                price: i.effectiveUnitPrice,
                quantity: i.quantity,
                notes: i.noteSummary,
              ))
          .toList(),
    );

    await _txRepo.insert(tx);
    final stockDeltas = <String, int>{};
    for (final item in _items) {
      await _productRepo.adjustStock(item.product.id, -item.quantity);
      stockDeltas[item.product.id] = item.quantity;
    }
    // Best-effort mirror so the customer-facing catalog reflects the same
    // stock. Skipped silently if offline.
    _firestoreProductRepo.decrementStockForOrder(stockDeltas).catchError((_) {});

    // Mirror into the shared order feed so the Chef sees walk-in sales too.
    _orderRepo.create(CustomerOrder(
      id: '',
      createdAt: tx.createdAt,
      items: tx.items
          .map((i) => CustomerOrderItem(
                productId: i.productId,
                productName: i.productName,
                price: i.price,
                quantity: i.quantity,
                notes: i.notes,
              ))
          .toList(),
      total: tx.total,
      paymentStatus: OrderPaymentStatus.paid,
      customerLabel: cashierLabel ?? 'Kasir',
      source: OrderSource.kasir,
      paymentMethod: _paymentLabels[method],
      tableNumber: tableNumber,
      restoId: restoId,
      orderType: orderType,
      customerName: customerName,
    )).catchError((_) {
      return '';
    });

    clear();
    return tx;
  }
}
