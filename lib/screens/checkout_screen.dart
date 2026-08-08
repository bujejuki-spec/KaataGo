import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/order_type.dart';
import '../models/transaction.dart';
import '../providers/auth_provider.dart';
import '../providers/cart_provider.dart';
import '../providers/product_provider.dart';
import 'payment_qris_screen.dart';
import 'payment_transfer_screen.dart';
import 'receipt_screen.dart';

class CheckoutScreen extends StatefulWidget {
  const CheckoutScreen({super.key});

  @override
  State<CheckoutScreen> createState() => _CheckoutScreenState();
}

class _CheckoutScreenState extends State<CheckoutScreen> {
  final _tableCtrl = TextEditingController();
  OrderType _orderType = OrderType.dineIn;

  @override
  void dispose() {
    _tableCtrl.dispose();
    super.dispose();
  }

  bool get _isDineIn => _orderType == OrderType.dineIn;
  int? get _tableNumber => int.tryParse(_tableCtrl.text.trim());

  /// Take Away needs no table; Dine In does.
  bool get _canPay => _isDineIn ? _tableNumber != null : true;

  @override
  Widget build(BuildContext context) {
    final currency = NumberFormat.currency(
      locale: 'id_ID',
      symbol: 'Rp ',
      decimalDigits: 0,
    );

    return Scaffold(
      appBar: AppBar(title: const Text('Kasir')),
      body: Consumer<CartProvider>(
        builder: (context, cart, _) {
          if (cart.items.isEmpty) {
            return const Center(child: Text('Keranjang kosong. Pilih produk dulu.'));
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
                            ? currency.format(item.product.price)
                            : '${currency.format(item.product.price)}\n$note',
                      ),
                      isThreeLine: note != null,
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.remove_circle_outline),
                            onPressed: () => cart.decrement(item.product.id),
                          ),
                          Text('${item.quantity}'),
                          IconButton(
                            icon: const Icon(Icons.add_circle_outline),
                            onPressed: () => cart.addProduct(item.product),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    SegmentedButton<OrderType>(
                      segments: const [
                        ButtonSegment(
                          value: OrderType.dineIn,
                          label: Text('Dine In'),
                          icon: Icon(Icons.restaurant_outlined),
                        ),
                        ButtonSegment(
                          value: OrderType.takeAway,
                          label: Text('Take Away'),
                          icon: Icon(Icons.shopping_bag_outlined),
                        ),
                      ],
                      selected: {_orderType},
                      onSelectionChanged: (v) => setState(() => _orderType = v.first),
                    ),
                    const SizedBox(height: 12),
                    if (_isDineIn)
                      TextField(
                        controller: _tableCtrl,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'Nomor Meja',
                          prefixIcon: Icon(Icons.table_bar_outlined),
                          border: OutlineInputBorder(),
                        ),
                        onChanged: (_) => setState(() {}),
                      ),
                    if (_isDineIn) const SizedBox(height: 16),
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
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: !_canPay
                                ? null
                                : () => _handlePayment(context, cart, PaymentMethod.cash),
                            child: const Text('Tunai'),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: OutlinedButton(
                            onPressed: !_canPay
                                ? null
                                : () => _handlePayment(context, cart, PaymentMethod.qris),
                            child: const Text('QRIS'),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: OutlinedButton(
                            onPressed: !_canPay
                                ? null
                                : () => _handlePayment(context, cart, PaymentMethod.transfer),
                            child: const Text('Transfer'),
                          ),
                        ),
                      ],
                    ),
                    if (!_canPay) ...[
                      const SizedBox(height: 8),
                      const Text(
                        'Isi nomor meja dulu sebelum bisa checkout.',
                        style: TextStyle(color: Colors.red, fontSize: 12),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _handlePayment(
      BuildContext context, CartProvider cart, PaymentMethod method) async {
    if (!_canPay) return;
    final tableNumber = _isDineIn ? _tableNumber : null;

    // Cash needs no extra confirmation screen. QRIS/Transfer show a dummy
    // "simulate payment" screen first, and only proceed if the cashier
    // confirms the (simulated) payment went through.
    if (method != PaymentMethod.cash) {
      final confirmed = await Navigator.of(context).push<bool>(
        MaterialPageRoute(
          builder: (_) => method == PaymentMethod.qris
              ? PaymentQrisScreen(amount: cart.total)
              : PaymentTransferScreen(amount: cart.total),
        ),
      );
      if (confirmed != true) return;
    }

    if (!context.mounted) return;

    final auth = context.read<AuthProvider>();
    final tx = await cart.checkout(
      method,
      cashierLabel: auth.user?.email,
      tableNumber: tableNumber,
      restoId: auth.restoId!,
      orderType: _orderType,
    );

    // Refresh product list so updated stock is reflected everywhere
    // (grid on the home screen, product management list, etc.)
    if (context.mounted) {
      await context.read<ProductProvider>().load();
    }

    if (!context.mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => ReceiptScreen(transaction: tx)),
    );
  }
}
