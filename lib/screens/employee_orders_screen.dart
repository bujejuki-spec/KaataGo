import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../db/order_repository.dart';
import '../utils/akses_menu.dart';
import '../models/customer_order.dart';
import '../providers/auth_provider.dart';
import '../widgets/grouped_order_list.dart';

/// Live list of incoming orders for this Admin's restaurant — from both
/// Employee Kasir sales and customer self-orders — with their payment
/// status. Grouped by date (newest first), then by Dine In / Take Away
/// within each date, so a busy day doesn't turn into one long
/// undifferentiated list. Reachable by Admin via the app bar icon on the
/// main POS screen.
class EmployeeOrdersScreen extends StatelessWidget {
  const EmployeeOrdersScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final repo = OrderRepository();
    final restoId = context.watch<AuthProvider>().restoId!;

    return berdasarkanAkses(context, 'Pesanan Masuk', Scaffold(
      appBar: AppBar(title: const Text('Pesanan Masuk')),
      body: StreamBuilder<List<CustomerOrder>>(
        stream: repo.watchAktif(restoId),
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
          // Pesanan yang dibatalkan atau hangus tidak ikut ditampilkan.
          //
          // Layar dapur sudah membuangnya sejak awal, layar ini belum —
          // dan karena kartunya membaca status bayar sebagai "lunas atau
          // bukan", pesanan yang ditarik pelanggannya muncul di sini
          // dengan label Menunggu Pembayaran. Yang membacanya wajar
          // menyiapkan makanannya.
          final orders =
              (snapshot.data ?? []).where((o) => !o.isVoid).toList();
          if (orders.isEmpty) {
            return const Center(child: Text('Belum ada pesanan masuk.'));
          }
          return GroupedOrderList(
            key: ValueKey(Theme.of(context).brightness),
            orders: orders,
            expandItems: false,
            collapsibleDays: true,
            // Kasir yang menyatakan sebuah pesanan mulai disiapkan.
            //
            // Dulu tombol itu ada di layar dapur, ditekan juru masak
            // sendiri. Sekarang yang memakai layar itu mengantar
            // makanan, bukan memutuskan mana yang mulai dikerjakan —
            // jadi keputusannya pindah ke tempat pesanannya diterima.
            //
            // Hanya untuk yang sudah lunas. Pesanan yang uangnya belum
            // diterima memang tidak boleh diteruskan: kalau memang mau
            // dimasak duluan, pembayarannya yang diselesaikan lebih
            // dulu.
            actionsFor: (order) {
              if (order.isAwaitingPayment) return null;
              if (order.kitchenStatus != KitchenStatus.waiting) return null;
              return SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  icon: const Icon(Icons.soup_kitchen_outlined, size: 18),
                  label: const Text('Mulai Disiapkan'),
                  onPressed: () => repo.updateKitchenStatus(
                      order.id, KitchenStatus.onProgress),
                ),
              );
            },
          );
        },
      ),
    ));
  }
}
