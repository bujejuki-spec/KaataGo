import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../db/order_repository.dart';
import '../models/customer_order.dart';
import '../models/order_type.dart';
import '../providers/auth_provider.dart';
import '../theme.dart';
import '../utils/id_time.dart';
import '../widgets/app_toast.dart';
import '../widgets/cash_payment_dialog.dart';
import '../widgets/responsive.dart';

/// Antrean pesanan yang dipesan sendiri dari HP pelanggan, dipilih bayar
/// tunai, dan menunggu dilunasi di meja kasir.
///
/// Pesanannya sudah utuh sejak awal — dapur boleh langsung memasaknya,
/// dan pelanggan sudah diberi tahu untuk membayar ke kasir. Yang belum
/// terjadi cuma satu: uangnya belum berpindah. Layar ini tempat kejadian
/// itu dicatat.
class PendingPaymentScreen extends StatefulWidget {
  const PendingPaymentScreen({super.key});

  @override
  State<PendingPaymentScreen> createState() => _PendingPaymentScreenState();
}

class _PendingPaymentScreenState extends State<PendingPaymentScreen> {
  final _repo = OrderRepository();
  final _currency = NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0);

  /// Pesanan yang sedang dilunasi. Tombolnya dimatikan selama itu supaya
  /// satu pesanan tidak dilunasi dua kali oleh dua ketukan beruntun.
  String? _settling;

  Future<void> _settle(CustomerOrder order) async {
    final received = await showDialog<int>(
      context: context,
      builder: (_) => CashPaymentDialog(total: order.total),
    );
    if (received == null || !mounted) return;

    setState(() => _settling = order.id);
    try {
      await _repo.settleCashPayment(order.id, cashReceived: received);
      if (!mounted) return;
      final change = received - order.total;
      showAppToast(
        context,
        change > 0
            ? 'Pesanan #${refOf(order.id)} lunas. Kembalian ${_currency.format(change)}.'
            : 'Pesanan #${refOf(order.id)} lunas — uang pas.',
      );
    } catch (e) {
      if (!mounted) return;
      showAppToast(context, 'Gagal menyimpan pembayaran: $e', isError: true);
    } finally {
      if (mounted) setState(() => _settling = null);
    }
  }

  Future<void> _showDetail(CustomerOrder order) async {
    await showDialog<void>(
      context: context,
      builder: (_) => _OrderDetailDialog(order: order, currency: _currency),
    );
  }

  @override
  Widget build(BuildContext context) {
    final restoId = context.watch<AuthProvider>().restoId;

    if (restoId == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Pending Payment')),
        body: const Center(child: Text('Akun ini belum punya Resto ID.')),
      );
    }

    return Scaffold(
      backgroundColor: KaataTheme.backgroundTint,
      appBar: AppBar(title: const Text('Pending Payment')),
      body: StreamBuilder<List<CustomerOrder>>(
        stream: _repo.watchPendingCashPayments(restoId),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text('Gagal memuat: ${snapshot.error}', textAlign: TextAlign.center),
              ),
            );
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final orders = snapshot.data!;
          if (orders.isEmpty) return const _EmptyState();

          return ResponsiveCenter(
            child: ListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
              itemCount: orders.length + 1,
              itemBuilder: (context, index) {
                if (index == 0) {
                  return _TotalHeader(
                    count: orders.length,
                    total: orders.fold<int>(0, (sum, o) => sum + o.total),
                    currency: _currency,
                  );
                }
                final order = orders[index - 1];
                return _PendingCard(
                  order: order,
                  currency: _currency,
                  busy: _settling == order.id,
                  onDetail: () => _showDetail(order),
                  onSettle: _settling == null ? () => _settle(order) : null,
                );
              },
            ),
          );
        },
      ),
    );
  }
}

class _TotalHeader extends StatelessWidget {
  final int count;
  final int total;
  final NumberFormat currency;

  const _TotalHeader({required this.count, required this.total, required this.currency});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFF59E0B), Color(0xFFB45309)],
        ),
      ),
      child: Row(
        children: [
          const Icon(Icons.pending_actions_outlined, color: Colors.white, size: 30),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('$count pesanan menunggu dibayar',
                    style: const TextStyle(
                        color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15)),
                const SizedBox(height: 2),
                Text('Total ${currency.format(total)}',
                    style: TextStyle(color: Colors.white.withOpacity(0.9), fontSize: 13)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PendingCard extends StatelessWidget {
  final CustomerOrder order;
  final NumberFormat currency;
  final bool busy;
  final VoidCallback onDetail;
  final VoidCallback? onSettle;

  const _PendingCard({
    required this.order,
    required this.currency,
    required this.busy,
    required this.onDetail,
    required this.onSettle,
  });

  @override
  Widget build(BuildContext context) {
    final itemCount = order.items.fold<int>(0, (sum, i) => sum + i.quantity);
    final where = order.orderType == OrderType.takeAway
        ? 'Take Away'
        : 'Meja ${order.tableNumber ?? '-'}';

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onDetail,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: KaataTheme.brand.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text('#${refOf(order.id)}',
                        style: const TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.bold,
                            color: KaataTheme.brandDark)),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '$where · $itemCount item',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14.5),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Text(currency.format(order.total),
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                '${DateFormat('dd MMM · HH:mm').format(order.createdAt.toWib())}'
                '${order.customerName?.trim().isNotEmpty == true ? ' · ${order.customerName!.trim()}' : ''}'
                ' · ${order.customerLabel}',
                style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: onDetail,
                      icon: const Icon(Icons.receipt_long_outlined, size: 16),
                      label: const Text('Detail'),
                      style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(38)),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    flex: 2,
                    child: FilledButton.icon(
                      onPressed: busy ? null : onSettle,
                      icon: busy
                          ? const SizedBox(
                              width: 14,
                              height: 14,
                              child:
                                  CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : const Icon(Icons.payments_outlined, size: 16),
                      label: const Text('Terima Pembayaran'),
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFF10B981),
                        minimumSize: const Size.fromHeight(38),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Rincian pesanan sebelum uangnya diterima.
///
/// Kasir menagih sejumlah uang tanpa pernah melihat barangnya diserahkan
/// — daftar ini satu-satunya cara memastikan yang ditagih memang yang
/// dipesan saat pelanggan bertanya "kok segini?".
class _OrderDetailDialog extends StatelessWidget {
  final CustomerOrder order;
  final NumberFormat currency;

  const _OrderDetailDialog({required this.order, required this.currency});

  @override
  Widget build(BuildContext context) {
    final where = order.orderType == OrderType.takeAway
        ? 'Take Away'
        : 'Meja ${order.tableNumber ?? '-'}';

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Pesanan #${refOf(order.id)}',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 17)),
            const SizedBox(height: 2),
            Text(
              '$where · ${DateFormat('dd MMM yyyy · HH:mm').format(order.createdAt.toWib())}',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
            ),
            if (order.customerName?.trim().isNotEmpty == true)
              Text('a.n. ${order.customerName!.trim()}',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
            const Divider(height: 20),
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final item in order.items) ...[
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(item.productName,
                                    style: const TextStyle(fontWeight: FontWeight.w600)),
                                Text(
                                  '${item.quantity} x ${currency.format(item.price)}'
                                  '${item.notes?.isNotEmpty == true ? ' · ${item.notes}' : ''}',
                                  style:
                                      TextStyle(fontSize: 12, color: Colors.grey.shade600),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 10),
                          Text(currency.format(item.subtotal),
                              style: const TextStyle(fontWeight: FontWeight.w600)),
                        ],
                      ),
                      const SizedBox(height: 10),
                    ],
                  ],
                ),
              ),
            ),
            const Divider(height: 20),
            if ((order.serviceAmount ?? 0) > 0)
              _row('Biaya Service', currency.format(order.serviceAmount!), soft: true),
            if ((order.ppnAmount ?? 0) > 0)
              _row('PPN', currency.format(order.ppnAmount!), soft: true),
            const SizedBox(height: 4),
            _row('TOTAL', currency.format(order.total), bold: true),
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Tutup'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _row(String label, String value, {bool bold = false, bool soft = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style: TextStyle(
                fontWeight: bold ? FontWeight.bold : FontWeight.normal,
                fontSize: bold ? 15 : 13,
                color: soft ? Colors.grey.shade700 : null,
              )),
          Text(value,
              style: TextStyle(
                fontWeight: bold ? FontWeight.bold : FontWeight.w600,
                fontSize: bold ? 17 : 13,
                color: soft ? Colors.grey.shade700 : null,
              )),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.check_circle_outline, size: 64, color: Colors.grey.shade300),
            const SizedBox(height: 14),
            Text('Tidak ada pesanan yang menunggu dibayar',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey.shade600, fontSize: 14)),
            const SizedBox(height: 6),
            Text(
              'Pesanan dari HP pelanggan yang memilih bayar tunai akan muncul di sini.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey.shade500, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}
