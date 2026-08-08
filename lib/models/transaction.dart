import 'order_type.dart';

class TransactionItem {
  final String productId;
  final String productName;
  final int price;
  final int quantity;

  /// Selected level(s) (e.g. "Level Pedas: Pedas") plus any free-text
  /// note, combined into one display string — see [CartItem.noteSummary].
  final String? notes;

  TransactionItem({
    required this.productId,
    required this.productName,
    required this.price,
    required this.quantity,
    this.notes,
  });

  int get subtotal => price * quantity;

  Map<String, dynamic> toMap(String transactionId) {
    return {
      'transactionId': transactionId,
      'productId': productId,
      'productName': productName,
      'price': price,
      'quantity': quantity,
      'notes': notes,
    };
  }

  factory TransactionItem.fromMap(Map<String, dynamic> map) {
    return TransactionItem(
      productId: map['productId'] as String,
      productName: map['productName'] as String,
      price: map['price'] as int,
      quantity: map['quantity'] as int,
      notes: map['notes'] as String?,
    );
  }
}

enum PaymentMethod { cash, qris, transfer }

class PosTransaction {
  final String id;
  final DateTime createdAt;
  final List<TransactionItem> items;
  final PaymentMethod paymentMethod;
  final int total;
  final OrderType orderType;

  /// Who to call out when the order's ready — mandatory for
  /// [OrderType.takeAway] (there's no table to deliver it to), unused
  /// for dine-in.
  final String? customerName;

  PosTransaction({
    required this.id,
    required this.createdAt,
    required this.items,
    required this.paymentMethod,
    required this.total,
    this.orderType = OrderType.dineIn,
    this.customerName,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'createdAt': createdAt.toIso8601String(),
      'paymentMethod': paymentMethod.name,
      'total': total,
      'orderType': orderType.dbValue,
      'customerName': customerName,
    };
  }

  factory PosTransaction.fromMap(
    Map<String, dynamic> map,
    List<TransactionItem> items,
  ) {
    return PosTransaction(
      id: map['id'] as String,
      createdAt: DateTime.parse(map['createdAt'] as String),
      items: items,
      paymentMethod: PaymentMethod.values.firstWhere(
        (e) => e.name == map['paymentMethod'],
      ),
      total: map['total'] as int,
      orderType: OrderTypeDb.fromDb(map['orderType'] as String?),
      customerName: map['customerName'] as String?,
    );
  }
}
