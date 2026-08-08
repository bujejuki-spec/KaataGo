import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../providers/auth_provider.dart';
import '../providers/customer_cart_provider.dart';
import '../providers/table_session_provider.dart';
import 'customer_qris_screen.dart';

class CustomerCartScreen extends StatelessWidget {
  const CustomerCartScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final currency = NumberFormat.currency(
      locale: 'id_ID',
      symbol: 'Rp ',
      decimalDigits: 0,
    );

    return Scaffold(
      appBar: AppBar(title: const Text('Keranjang')),
      body: Consumer<CustomerCartProvider>(
        builder: (context, cart, _) {
          if (cart.items.isEmpty) {
            return const Center(child: Text('Keranjang kosong.'));
          }
          return Column(
            children: [
              Expanded(
                child: ListView.builder(
                  itemCount: cart.items.length,
                  itemBuilder: (context, index) {
                    final item = cart.items[index];
                    final note = item.noteSummary;
                    return ListTile(
                      title: Text(item.product.name),
                      subtitle: Text(
                        note == null
                            ? '${item.quantity} x ${currency.format(item.product.price)}'
                            : '${item.quantity} x ${currency.format(item.product.price)}\n$note',
                      ),
                      isThreeLine: note != null,
                      trailing: Text(currency.format(item.subtotal)),
                    );
                  },
                ),
              ),
              const Divider(height: 1),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Total', style: TextStyle(fontSize: 18)),
                        Text(
                          currency.format(cart.total),
                          style: const TextStyle(
                              fontSize: 18, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Pembayaran hanya lewat QRIS untuk pesanan mandiri.',
                      style: TextStyle(color: Colors.grey, fontSize: 12),
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: () async {
                          final auth = context.read<AuthProvider>();
                          final session = context.read<TableSessionProvider>();
                          final label = auth.user?.email ?? 'Tamu';
                          final amount = cart.total;
                          final orderId = await cart.placeOrder(
                            label,
                            tableNumber: session.tableNumber!,
                            sessionId: session.sessionId!,
                            restoId: session.restoId!,
                          );
                          if (!context.mounted) return;
                          Navigator.of(context).pushReplacement(
                            MaterialPageRoute(
                              builder: (_) => CustomerQrisScreen(
                                orderId: orderId,
                                amount: amount,
                                restoId: session.restoId!,
                              ),
                            ),
                          );
                        },
                        child: const Text('Pesan & Bayar dengan QRIS'),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
