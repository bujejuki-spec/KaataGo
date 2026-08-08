import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../providers/auth_provider.dart';
import '../providers/customer_cart_provider.dart';
import '../providers/table_session_provider.dart';
import 'customer_qris_screen.dart';

/// Checkout screen. If the session came from scanning a table QR code,
/// the table number is already known — shown here read-only/greyed out.
/// If it came from picking a restaurant off the list instead (no QR),
/// there's no table number yet, so this screen makes it a mandatory
/// field before "Pesan & Bayar" can be pressed.
class CustomerCartScreen extends StatefulWidget {
  const CustomerCartScreen({super.key});

  @override
  State<CustomerCartScreen> createState() => _CustomerCartScreenState();
}

class _CustomerCartScreenState extends State<CustomerCartScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _tableCtrl;
  bool _placing = false;

  @override
  void initState() {
    super.initState();
    final known = context.read<TableSessionProvider>().tableNumber;
    _tableCtrl = TextEditingController(text: known?.toString() ?? '');
  }

  @override
  void dispose() {
    _tableCtrl.dispose();
    super.dispose();
  }

  Future<void> _checkout() async {
    if (!_formKey.currentState!.validate()) return;

    final session = context.read<TableSessionProvider>();
    final cart = context.read<CustomerCartProvider>();
    final auth = context.read<AuthProvider>();

    // Table came in via QR scan already — nothing new to save. Otherwise
    // this is the first time it's known, so persist it to the session.
    final tableNumber = session.tableNumber ?? int.parse(_tableCtrl.text.trim());
    if (session.tableNumber == null) {
      await session.setTableNumber(tableNumber);
    }

    setState(() => _placing = true);
    final label = auth.user?.email ?? 'Tamu';
    final amount = cart.total;
    final orderId = await cart.placeOrder(
      label,
      tableNumber: tableNumber,
      sessionId: session.sessionId!,
      restoId: session.restoId!,
    );
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => CustomerQrisScreen(
          orderId: orderId,
          amount: amount,
          restoId: session.restoId!,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final currency = NumberFormat.currency(
      locale: 'id_ID',
      symbol: 'Rp ',
      decimalDigits: 0,
    );
    final tableKnown = context.watch<TableSessionProvider>().tableNumber != null;

    return Scaffold(
      appBar: AppBar(title: const Text('Keranjang')),
      body: Consumer<CustomerCartProvider>(
        builder: (context, cart, _) {
          if (cart.items.isEmpty) {
            return const Center(child: Text('Keranjang kosong.'));
          }
          return Form(
            key: _formKey,
            child: Column(
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
                      TextFormField(
                        controller: _tableCtrl,
                        enabled: !tableKnown,
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(
                          labelText: 'Nomor Meja',
                          helperText: tableKnown
                              ? 'Terisi otomatis dari QR yang kamu scan'
                              : 'Wajib diisi — nomor meja tempat kamu duduk',
                          filled: tableKnown,
                          fillColor: tableKnown ? Colors.grey.shade200 : null,
                        ),
                        validator: (v) {
                          if (tableKnown) return null;
                          if (v == null || v.trim().isEmpty) return 'Wajib diisi';
                          if (int.tryParse(v.trim()) == null) return 'Harus angka';
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),
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
                          onPressed: _placing ? null : _checkout,
                          child: _placing
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(strokeWidth: 2))
                              : const Text('Pesan & Bayar dengan QRIS'),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
