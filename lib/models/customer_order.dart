import 'order_type.dart';

class CustomerOrderItem {
  final String productId;
  final String productName;
  final int price;
  final int quantity;

  /// Selected level(s) (e.g. "Level Pedas: Pedas") plus any free-text
  /// note, combined into one display string — see [CartItem.noteSummary].
  /// Shown to the Chef/Admin so they know how to prep this line.
  final String? notes;

  CustomerOrderItem({
    required this.productId,
    required this.productName,
    required this.price,
    required this.quantity,
    this.notes,
  });

  int get subtotal => price * quantity;

  Map<String, dynamic> toMap() => {
        'productId': productId,
        'productName': productName,
        'price': price,
        'quantity': quantity,
        if (notes != null) 'notes': notes,
      };

  factory CustomerOrderItem.fromMap(Map<String, dynamic> map) {
    return CustomerOrderItem(
      productId: map['productId'] as String,
      productName: map['productName'] as String,
      price: (map['price'] as num).toInt(),
      quantity: (map['quantity'] as num).toInt(),
      notes: map['notes'] as String?,
    );
  }
}

enum OrderPaymentStatus { pending, paid }

/// Who placed the order — shown to the Chef so they know whether it came
/// from a walk-in rung up by a cashier, or a customer's own phone.
enum OrderSource { customer, kasir }

/// Kitchen prep status, tracked by the Chef and mirrored live to the
/// customer's order-status screen.
enum KitchenStatus { waiting, onProgress, done }

/// An order visible in the shared "Pesanan Masuk" feed: either a
/// self-service order placed by a customer (always paid via QRIS), or a
/// mirror of a sale rung up by an Employee Kasir (any payment method).
class CustomerOrder {
  final String id;
  final DateTime createdAt;
  final List<CustomerOrderItem> items;
  final int total;
  final OrderPaymentStatus paymentStatus;
  final String customerLabel; // email, or "Tamu" if not logged in
  final OrderSource source;
  final String? paymentMethod; // e.g. "Tunai", "QRIS", "Transfer" — kasir only

  /// This resto's Mapping GL Account code for [paymentMethod] (or QRIS,
  /// for customer self-orders) — kept in sync by a database trigger, not
  /// set from the app. Null if that GL isn't configured yet. See
  /// supabase/orders_gl_code.sql.
  final String? glCode;
  final String? tableNumber;
  final String? sessionId; // groups a customer's orders after scanning a table QR
  final KitchenStatus kitchenStatus;
  final String restoId; // which restaurant this order belongs to
  final OrderType orderType; // dine-in or take-away, chosen at checkout

  /// Who to call out when the order's ready for pickup — mandatory for
  /// take-away (there's no table to deliver it to), unused for dine-in.
  final String? customerName;

  /// Name of the Kasir/Admin who entered this order. Null for a customer
  /// self-order — nobody entered it on their behalf.
  final String? cashierName;

  /// How [total] splits into revenue, service charge and PPN — stored on
  /// the order so the journal can credit three separate GL accounts and
  /// a reprint shows the original figures.
  final int? baseAmount;
  final int? serviceAmount;
  final int? ppnAmount;

  CustomerOrder({
    required this.id,
    required this.createdAt,
    required this.items,
    required this.total,
    required this.paymentStatus,
    required this.customerLabel,
    required this.restoId,
    this.source = OrderSource.customer,
    this.paymentMethod,
    this.glCode,
    this.tableNumber,
    this.sessionId,
    this.kitchenStatus = KitchenStatus.waiting,
    this.orderType = OrderType.dineIn,
    this.customerName,
    this.cashierName,
    this.baseAmount,
    this.serviceAmount,
    this.ppnAmount,
  });

  /// Maps to Postgres `orders` table columns (snake_case). `id` and
  /// `created_at` are left out — assigned by the database on insert.
  Map<String, dynamic> toMap() => {
        'items': items.map((i) => i.toMap()).toList(),
        'total': total,
        'payment_status': paymentStatus.name,
        'customer_label': customerLabel,
        'source': source.name,
        'resto_id': restoId,
        if (paymentMethod != null) 'payment_method': paymentMethod,
        if (tableNumber != null) 'table_number': tableNumber,
        if (sessionId != null) 'session_id': sessionId,
        'kitchen_status': kitchenStatus.name,
        'order_type': orderType.dbValue,
        if (customerName != null) 'customer_name': customerName,
        if (cashierName != null) 'cashier_name': cashierName,
        if (baseAmount != null) 'base_amount': baseAmount,
        if (serviceAmount != null) 'service_amount': serviceAmount,
        if (ppnAmount != null) 'ppn_amount': ppnAmount,
      };

  factory CustomerOrder.fromMap(Map<String, dynamic> data) {
    return CustomerOrder(
      id: data['id'] as String,
      createdAt: DateTime.parse(data['created_at'] as String),
      items: (data['items'] as List<dynamic>)
          .map((i) => CustomerOrderItem.fromMap(i as Map<String, dynamic>))
          .toList(),
      total: (data['total'] as num).toInt(),
      paymentStatus: OrderPaymentStatus.values.firstWhere(
        (e) => e.name == data['payment_status'],
        orElse: () => OrderPaymentStatus.pending,
      ),
      customerLabel: data['customer_label'] as String? ?? 'Tamu',
      source: OrderSource.values.firstWhere(
        (e) => e.name == data['source'],
        orElse: () => OrderSource.customer,
      ),
      paymentMethod: data['payment_method'] as String?,
      glCode: data['gl_code'] as String?,
      tableNumber: data['table_number']?.toString(),
      sessionId: data['session_id'] as String?,
      kitchenStatus: KitchenStatus.values.firstWhere(
        (e) => e.name == data['kitchen_status'],
        orElse: () => KitchenStatus.waiting,
      ),
      restoId: data['resto_id'] as String? ?? '',
      orderType: OrderTypeDb.fromDb(data['order_type'] as String?),
      customerName: data['customer_name'] as String?,
      cashierName: data['cashier_name'] as String?,
      baseAmount: (data['base_amount'] as num?)?.toInt(),
      serviceAmount: (data['service_amount'] as num?)?.toInt(),
      ppnAmount: (data['ppn_amount'] as num?)?.toInt(),
    );
  }
}
