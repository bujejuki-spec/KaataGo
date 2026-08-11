import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../db/order_repository.dart';
import '../models/customer_order.dart';
import '../providers/auth_provider.dart';
import '../utils/logout_confirm.dart';
import '../widgets/grouped_order_list.dart';

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
    final auth = context.watch<AuthProvider>();
    final restoId = auth.restoId!;
    final employeeName = auth.employeeName?.isNotEmpty == true ? auth.employeeName! : 'Chef';

    return DefaultTabController(
      length: _tabs.length,
      child: Scaffold(
        appBar: AppBar(
          toolbarHeight: 60,
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(employeeName, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              Text(
                '${auth.roleLabel ?? 'Chef'} • ${auth.user?.email ?? ''}',
                style: const TextStyle(fontSize: 11, color: Colors.white70),
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
          bottom: TabBar(tabs: _tabs.map((t) => Tab(text: t.$2)).toList()),
          actions: [
            IconButton(
              icon: const Icon(Icons.logout),
              tooltip: 'Keluar',
              onPressed: () async {
                if (!await confirmLogout(context)) return;
                if (!context.mounted) return;
                await context.read<AuthProvider>().signOut();
              },
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
                return GroupedOrderList(orders: orders, actionsFor: _buildActions);
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
