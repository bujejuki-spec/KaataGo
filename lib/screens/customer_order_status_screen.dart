import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../db/order_repository.dart';
import '../models/customer_order.dart';
import '../providers/table_session_provider.dart';
import 'customer_receipt_screen.dart';

/// Lets the customer track their own orders live — grouped under the
/// session id assigned when they scanned their table's QR code, so no
/// account is needed. Also where they end their session once done.
class CustomerOrderStatusScreen extends StatelessWidget {
  const CustomerOrderStatusScreen({super.key});

  static const _kitchenLabels = {
    KitchenStatus.waiting: 'Menunggu Diproses',
    KitchenStatus.onProgress: 'Sedang Dimasak',
    KitchenStatus.done: 'Selesai',
  };
  static const _kitchenColors = {
    KitchenStatus.waiting: Colors.grey,
    KitchenStatus.onProgress: Colors.orange,
    KitchenStatus.done: Colors.green,
  };

  Future<void> _confirmEndSession(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Selesaikan Sesi?'),
        content: const Text(
          'Sesi meja ini akan diakhiri. Kalau kamu mau pesan lagi nanti, '
          'scan ulang QR meja yang sama untuk melanjutkan riwayat pesanan ini.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Ya, Selesai'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    await context.read<TableSessionProvider>().endSession();
    if (!context.mounted) return;
    Navigator.of(context).popUntil((r) => r.isFirst);
  }

  @override
  Widget build(BuildContext context) {
    final session = context.watch<TableSessionProvider>();
    final currency = NumberFormat.currency(
      locale: 'id_ID',
      symbol: 'Rp ',
      decimalDigits: 0,
    );
    final dateFmt = DateFormat('HH:mm', 'id_ID');

    if (!session.hasActiveTable) {
      return Scaffold(
        appBar: AppBar(title: const Text('Pesanan Saya')),
        body: const Center(child: Text('Belum ada sesi meja aktif.')),
      );
    }

    final repo = OrderRepository();

    return Scaffold(
      appBar: AppBar(title: Text('Pesanan Saya • Meja ${session.tableNumber}')),
      body: StreamBuilder<List<CustomerOrder>>(
        stream: repo.watchBySession(session.sessionId!),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(
              child: Text('Gagal memuat pesanan.\n${snapshot.error}',
                  textAlign: TextAlign.center),
            );
          }
          final orders = snapshot.data ?? [];
          if (orders.isEmpty) {
            return const Center(child: Text('Belum ada pesanan di sesi ini.'));
          }
          return ListView.builder(
            padding: const EdgeInsets.all(12),
            itemCount: orders.length,
            itemBuilder: (context, index) {
              final order = orders[index];
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
                          Text('Pesanan #${order.id.substring(0, 6).toUpperCase()}',
                              style: const TextStyle(fontWeight: FontWeight.bold)),
                          Row(
                            children: [
                              Text(dateFmt.format(order.createdAt),
                                  style: const TextStyle(color: Colors.grey, fontSize: 12)),
                              IconButton(
                                icon: const Icon(Icons.receipt_long_outlined, size: 20),
                                tooltip: 'Struk Pembayaran',
                                visualDensity: VisualDensity.compact,
                                onPressed: () => Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (_) => CustomerReceiptScreen(order: order),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Icon(Icons.circle,
                              size: 10, color: _kitchenColors[order.kitchenStatus]),
                          const SizedBox(width: 6),
                          Text(
                            _kitchenLabels[order.kitchenStatus]!,
                            style: TextStyle(
                              color: _kitchenColors[order.kitchenStatus],
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Text(
                            paid ? 'Sudah Dibayar' : 'Menunggu Pembayaran',
                            style: TextStyle(
                              color: paid ? Colors.green : Colors.orange,
                              fontSize: 12,
                            ),
                          ),
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
                                Text(
                                  item.notes!,
                                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
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
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: OutlinedButton.icon(
            icon: const Icon(Icons.check_circle_outline),
            label: const Text('Pesanan Sudah Semua • Selesai'),
            onPressed: () => _confirmEndSession(context),
          ),
        ),
      ),
    );
  }
}
