import 'package:flutter/material.dart';

import '../theme.dart';
import 'package:intl/intl.dart';

import '../models/customer_order.dart';
import '../models/order_type.dart';
import '../utils/id_time.dart';

const _paymentMethodDisplayLabels = {'cash': 'Tunai', 'qris': 'QRIS', 'transfer': 'Transfer'};

/// Kasir sales store `payment_method` as the lowercase gl_accounts key
/// ('cash'/'qris'/'transfer') going forward, but orders recorded before
/// that change still have the old display label ('Tunai'/'QRIS'/
/// 'Transfer') — shown as-is since it already reads fine.
String _paymentMethodLabel(String raw) => _paymentMethodDisplayLabels[raw] ?? raw;

/// Shared order-detail card used by both the Admin's and Chef's
/// "Pesanan Masuk" views: customer/kasir label, table number, payment
/// status, source (Kasir sale vs self-order), itemized list, and total.
///
/// [actions], if provided, renders below the total — the Chef view uses
/// this slot for its "Mulai Masak" / "Selesai" buttons.
class OrderCard extends StatefulWidget {
  final CustomerOrder order;
  final Widget? actions;

  /// Terbuka saat pertama digambar. Layar dapur membiarkannya terbuka —
  /// isinya justru yang harus dibaca; layar Pesanan Masuk memulainya
  /// tertutup karena di sana orang mencari satu pesanan di antara
  /// puluhan.
  final bool initiallyExpanded;

  const OrderCard({
    super.key,
    required this.order,
    this.actions,
    this.initiallyExpanded = true,
  });

  @override
  State<OrderCard> createState() => _OrderCardState();
}

class _OrderCardState extends State<OrderCard> {
  late bool _expanded = widget.initiallyExpanded;

  @override
  Widget build(BuildContext context) {
    final order = widget.order;
    final actions = widget.actions;
    final currency = NumberFormat.currency(
      locale: 'id_ID',
      symbol: 'Rp ',
      decimalDigits: 0,
    );
    final dateFmt = DateFormat('dd MMM, HH:mm', 'id_ID');
    final paid = order.paymentStatus == OrderPaymentStatus.paid;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: KaataTheme.surfaceOf(context),
        borderRadius: BorderRadius.circular(14),
        // Garis tepi, bukan sekadar bayangan: dengan banyak pesanan
        // beruntun, bayangan tipis membuat batas antar kartu nyaris tak
        // terlihat dan dua pesanan mudah terbaca sebagai satu.
        border: Border.all(color: Colors.grey.shade300),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Row(
                    children: [
                      if (order.tableNumber != null) ...[
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: Colors.blueGrey.shade50,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            'Meja ${order.tableNumber}',
                            style: const TextStyle(
                                fontSize: 12, fontWeight: FontWeight.bold, color: Colors.blueGrey),
                          ),
                        ),
                        const SizedBox(width: 8),
                      ] else if (order.orderType == OrderType.takeAway &&
                          order.customerName != null &&
                          order.customerName!.isNotEmpty) ...[
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: Colors.amber.shade50,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            'a.n. ${order.customerName}',
                            style: TextStyle(
                                fontSize: 12, fontWeight: FontWeight.bold, color: Colors.amber.shade800),
                          ),
                        ),
                        const SizedBox(width: 8),
                      ],
                      Flexible(
                        child: Text(
                          '#${order.id.substring(0, 8).toUpperCase()}',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: paid ? Colors.green.shade100 : Colors.orange.shade100,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    paid ? 'Sudah Dibayar' : 'Menunggu Pembayaran',
                    style: TextStyle(
                      color: paid ? Colors.green.shade800 : Colors.orange.shade800,
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: order.source == OrderSource.kasir
                        ? Colors.indigo.shade50
                        : Colors.purple.shade50,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    order.source == OrderSource.kasir
                        ? 'Kasir${order.paymentMethod != null ? ' • ${_paymentMethodLabel(order.paymentMethod!)}' : ''}'
                        : 'Pesanan Mandiri',
                    style: TextStyle(
                      fontSize: 11,
                      color: order.source == OrderSource.kasir ? Colors.indigo : Colors.purple,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: order.orderType == OrderType.takeAway
                        ? Colors.amber.shade50
                        : Colors.teal.shade50,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        order.orderType == OrderType.takeAway
                            ? Icons.shopping_bag_outlined
                            : Icons.restaurant_outlined,
                        size: 12,
                        color: order.orderType == OrderType.takeAway
                            ? Colors.amber.shade800
                            : Colors.teal.shade800,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        kOrderTypeLabels[order.orderType]!,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: order.orderType == OrderType.takeAway
                              ? Colors.amber.shade800
                              : Colors.teal.shade800,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Text(dateFmt.format(order.createdAt.toWib()),
                    style: const TextStyle(color: Colors.grey, fontSize: 12)),
              ],
            ),
            const Divider(height: 16),
            InkWell(
              onTap: () => setState(() => _expanded = !_expanded),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  children: [
                    Icon(_expanded ? Icons.expand_less : Icons.expand_more,
                        size: 18, color: Colors.grey.shade600),
                    const SizedBox(width: 6),
                    Text(
                      '${order.items.fold<int>(0, (sum, i) => sum + i.quantity)} item',
                      style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                          color: Colors.grey.shade700),
                    ),
                    const Spacer(),
                    if (!_expanded)
                      Text(
                        'Lihat rincian',
                        style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
                      ),
                  ],
                ),
              ),
            ),
            if (_expanded) ...[
            const SizedBox(height: 6),
            ...order.items.map(
              (item) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(child: Text('${item.productName} x${item.quantity}')),
                        Text(currency.format(item.subtotal)),
                      ],
                    ),
                    if (item.notes != null && item.notes!.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 1),
                        child: Text(
                          item.notes!,
                          style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            ],
            const Divider(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Total', style: TextStyle(fontWeight: FontWeight.bold)),
                Text(currency.format(order.total),
                    style: const TextStyle(fontWeight: FontWeight.bold)),
              ],
            ),
            if (actions != null) ...[
              const SizedBox(height: 12),
              actions,
            ],
          ],
        ),
      ),
    );
  }
}
