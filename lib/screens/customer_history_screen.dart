import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../db/order_repository.dart';
import '../db/restaurant_repository.dart';
import '../models/customer_order.dart';
import '../providers/auth_provider.dart';
import 'customer_receipt_screen.dart';

/// Cross-restaurant order history for a customer who logged in with
/// email — unlike "Pesanan Saya" (which only tracks the *current* table
/// session on *this* device), this follows the account everywhere, since
/// every order they place while logged in is tagged with their email.
class CustomerHistoryScreen extends StatefulWidget {
  const CustomerHistoryScreen({super.key});

  @override
  State<CustomerHistoryScreen> createState() => _CustomerHistoryScreenState();
}

class _CustomerHistoryScreenState extends State<CustomerHistoryScreen> {
  final _restoRepo = RestaurantRepository();
  final Map<String, String> _restoNameCache = {};

  Future<String> _restoName(String restoId) async {
    if (_restoNameCache.containsKey(restoId)) return _restoNameCache[restoId]!;
    final resto = await _restoRepo.getOnce(restoId);
    final name = resto?.name ?? restoId;
    _restoNameCache[restoId] = name;
    return name;
  }

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

  @override
  Widget build(BuildContext context) {
    final email = context.watch<AuthProvider>().user?.email;
    final currency = NumberFormat.currency(
      locale: 'id_ID',
      symbol: 'Rp ',
      decimalDigits: 0,
    );
    final dateFmt = DateFormat('dd MMM yyyy, HH:mm', 'id_ID');

    if (email == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Riwayat Saya')),
        body: const Center(child: Text('Login dulu untuk lihat riwayat.')),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Riwayat Saya')),
      body: StreamBuilder<List<CustomerOrder>>(
        stream: OrderRepository().watchByCustomerEmail(email),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(
              child: Text('Gagal memuat riwayat.\n${snapshot.error}',
                  textAlign: TextAlign.center),
            );
          }
          final orders = snapshot.data ?? [];
          if (orders.isEmpty) {
            return const Center(child: Text('Belum ada riwayat pesanan.'));
          }
          return ListView.builder(
            padding: const EdgeInsets.all(12),
            itemCount: orders.length,
            itemBuilder: (context, index) {
              final order = orders[index];
              final paid = order.paymentStatus == OrderPaymentStatus.paid;
              return Card(
                margin: const EdgeInsets.only(bottom: 10),
                child: ListTile(
                  title: FutureBuilder<String>(
                    future: _restoName(order.restoId),
                    builder: (context, snap) => Text(
                      snap.data ?? order.restoId,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${order.tableNumber != null ? 'Meja ${order.tableNumber} • ' : ''}${dateFmt.format(order.createdAt)}',
                        style: const TextStyle(fontSize: 12),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Icon(Icons.circle,
                              size: 8, color: _kitchenColors[order.kitchenStatus]),
                          const SizedBox(width: 4),
                          Text(
                            _kitchenLabels[order.kitchenStatus]!,
                            style: TextStyle(
                              fontSize: 11,
                              color: _kitchenColors[order.kitchenStatus],
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            paid ? 'Sudah Dibayar' : 'Menunggu Pembayaran',
                            style: TextStyle(
                              fontSize: 11,
                              color: paid ? Colors.green : Colors.orange,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  trailing: Text(
                    currency.format(order.total),
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => CustomerReceiptScreen(order: order)),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
