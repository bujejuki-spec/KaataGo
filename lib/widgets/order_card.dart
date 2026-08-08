import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/customer_order.dart';
import '../models/order_type.dart';

/// Shared order-detail card used by both the Admin's and Chef's
/// "Pesanan Masuk" views: customer/kasir label, table number, payment
/// status, source (Kasir sale vs self-order), itemized list, and total.
///
/// [actions], if provided, renders below the total — the Chef view uses
/// this slot for its "Mulai Masak" / "Selesai" buttons.
class OrderCard extends StatelessWidget {
  final CustomerOrder order;
  final Widget? actions;

  const OrderCard({super.key, required this.order, this.actions});

  @override
  Widget build(BuildContext context) {
    final currency = NumberFormat.currency(
      locale: 'id_ID',
      symbol: 'Rp ',
      decimalDigits: 0,
    );
    final dateFmt = DateFormat('dd MMM, HH:mm', 'id_ID');
    final paid = order.paymentStatus == OrderPaymentStatus.paid;

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
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
                      ],
                      Flexible(
                        child: Text(
                          order.customerLabel,
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
                        ? 'Kasir${order.paymentMethod != null ? ' • ${order.paymentMethod}' : ''}'
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
                Text(dateFmt.format(order.createdAt),
                    style: const TextStyle(color: Colors.grey, fontSize: 12)),
              ],
            ),
            const Divider(height: 16),
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
              actions!,
            ],
          ],
        ),
      ),
    );
  }
}
