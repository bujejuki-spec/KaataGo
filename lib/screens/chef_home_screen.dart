import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../db/order_repository.dart';
import '../models/customer_order.dart';
import '../providers/auth_provider.dart';
import '../widgets/order_card.dart';

/// Chef's entire app: a live, tabbed feed of incoming orders — from both
/// Employee Kasir sales and customer self-orders — with full item detail.
/// Chef can advance an order from "Baru" → "Diproses" → "Selesai"; the
/// status updates live for the customer to see too. No product
/// management, no cashier access, no settings.
class ChefHomeScreen extends StatefulWidget {
  const ChefHomeScreen({super.key});

  @override
  State<ChefHomeScreen> createState() => _ChefHomeScreenState();
}

class _ChefHomeScreenState extends State<ChefHomeScreen> {
  final _repo = OrderRepository();

  static const _tabs = [
    (KitchenStatus.waiting, 'Baru'),
    (KitchenStatus.onProgress, 'Diproses'),
    (KitchenStatus.done, 'Selesai'),
  ];

  @override
  Widget build(BuildContext context) {
    final restoId = context.watch<AuthProvider>().restoId!;
    return DefaultTabController(
      length: _tabs.length,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Pesanan Masuk (Dapur)'),
          bottom: TabBar(tabs: _tabs.map((t) => Tab(text: t.$2)).toList()),
          actions: [
            IconButton(
              icon: const Icon(Icons.logout),
              tooltip: 'Keluar',
              onPressed: () => context.read<AuthProvider>().signOut(),
            ),
          ],
        ),
        body: StreamBuilder<List<CustomerOrder>>(
          stream: _repo.watchAll(restoId),
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
            final allOrders = snapshot.data ?? [];

            return TabBarView(
              children: _tabs.map((tab) {
                final orders =
                    allOrders.where((o) => o.kitchenStatus == tab.$1).toList();
                if (orders.isEmpty) {
                  return Center(child: Text('Tidak ada pesanan "${tab.$2}".'));
                }
                return ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: orders.length,
                  itemBuilder: (context, index) {
                    final order = orders[index];
                    return OrderCard(
                      order: order,
                      actions: _buildActions(order),
                    );
                  },
                );
              }).toList(),
            );
          },
        ),
      ),
    );
  }

  Widget? _buildActions(CustomerOrder order) {
    switch (order.kitchenStatus) {
      case KitchenStatus.waiting:
        return SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            icon: const Icon(Icons.soup_kitchen_outlined, size: 18),
            label: const Text('Mulai Masak'),
            onPressed: () =>
                _repo.updateKitchenStatus(order.id, KitchenStatus.onProgress),
          ),
        );
      case KitchenStatus.onProgress:
        return SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            icon: const Icon(Icons.check_circle_outline, size: 18),
            label: const Text('Selesai'),
            onPressed: () => _repo.updateKitchenStatus(order.id, KitchenStatus.done),
          ),
        );
      case KitchenStatus.done:
        return null;
    }
  }
}
