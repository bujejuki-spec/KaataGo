import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../db/mail_request_repository.dart';
import '../models/customer_order.dart';
import '../models/order_type.dart';

/// Itemized receipt for one customer order, with an option to have it
/// emailed. Reachable from "Pesanan Saya" (order status screen).
class CustomerReceiptScreen extends StatefulWidget {
  final CustomerOrder order;

  const CustomerReceiptScreen({super.key, required this.order});

  @override
  State<CustomerReceiptScreen> createState() => _CustomerReceiptScreenState();
}

class _CustomerReceiptScreenState extends State<CustomerReceiptScreen> {
  final _mailRepo = MailRequestRepository();
  bool _sending = false;

  Future<void> _sendToEmail() async {
    final controller = TextEditingController();
    final email = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Kirim Struk ke Email'),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.emailAddress,
          decoration: const InputDecoration(labelText: 'Alamat Email'),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () {
              final value = controller.text.trim();
              final valid = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(value);
              Navigator.pop(context, valid ? value : null);
            },
            child: const Text('Kirim'),
          ),
        ],
      ),
    );
    if (email == null || !mounted) return;

    setState(() => _sending = true);
    await _mailRepo.requestReceiptEmail(
      toEmail: email,
      orderId: widget.order.id,
      restoId: widget.order.restoId,
    );
    if (!mounted) return;
    setState(() => _sending = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Struk akan dikirim ke $email')),
    );
  }

  String _paymentLabel(CustomerOrder order) {
    if (order.source == OrderSource.kasir) return order.paymentMethod ?? '-';
    return 'QRIS';
  }

  @override
  Widget build(BuildContext context) {
    final order = widget.order;
    final currency = NumberFormat.currency(
      locale: 'id_ID',
      symbol: 'Rp ',
      decimalDigits: 0,
    );
    final dateFmt = DateFormat('dd MMM yyyy, HH:mm', 'id_ID');

    return Scaffold(
      appBar: AppBar(title: const Text('Struk Pembayaran')),
      body: Column(
        children: [
          const SizedBox(height: 8),
          Text('Pesanan #${order.id.substring(0, 6).toUpperCase()}',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          Text(dateFmt.format(order.createdAt),
              style: const TextStyle(color: Colors.grey)),
          const SizedBox(height: 4),
          Text(kOrderTypeLabels[order.orderType]!,
              style: TextStyle(color: Colors.grey.shade700, fontWeight: FontWeight.w600, fontSize: 13)),
          if (order.customerName != null && order.customerName!.isNotEmpty)
            Text('a.n. ${order.customerName}',
                style: TextStyle(color: Colors.grey.shade600, fontSize: 12)),
          const SizedBox(height: 16),
          const Divider(),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              itemCount: order.items.length,
              itemBuilder: (context, index) {
                final item = order.items[index];
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
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
                );
              },
            ),
          ),
          const Divider(),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Metode Bayar'),
                    Text(_paymentLabel(order)),
                  ],
                ),
                const SizedBox(height: 4),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Total',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                    Text(
                      currency.format(order.total),
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                icon: _sending
                    ? const SizedBox(
                        width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.email_outlined),
                label: const Text('Kirim ke Email'),
                onPressed: _sending ? null : _sendToEmail,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
