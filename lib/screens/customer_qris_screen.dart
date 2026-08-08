import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../db/order_repository.dart';

/// QR payment screen shown right after a customer places a self-order.
/// The order already exists in Supabase with status "pending" (visible
/// to the employee app immediately); confirming payment here flips it
/// to "paid".
class CustomerQrisScreen extends StatefulWidget {
  final String orderId;
  final int amount;
  final String restoId;

  const CustomerQrisScreen({
    super.key,
    required this.orderId,
    required this.amount,
    required this.restoId,
  });

  @override
  State<CustomerQrisScreen> createState() => _CustomerQrisScreenState();
}

class _CustomerQrisScreenState extends State<CustomerQrisScreen> {
  final _orderRepo = OrderRepository();
  bool _confirming = false;

  Future<void> _confirmPaid() async {
    setState(() => _confirming = true);
    try {
      await _orderRepo.markPaid(widget.orderId);
      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(
          builder: (_) => _OrderPlacedScreen(orderId: widget.orderId),
        ),
        (route) => route.isFirst,
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Gagal konfirmasi pembayaran: $e')),
      );
      setState(() => _confirming = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final currency = NumberFormat.currency(
      locale: 'id_ID',
      symbol: 'Rp ',
      decimalDigits: 0,
    );

    return Scaffold(
      appBar: AppBar(
        title: const Text('Bayar dengan QRIS'),
        automaticallyImplyLeading: false,
      ),
      body: StreamBuilder<List<Map<String, dynamic>>>(
        stream: Supabase.instance.client
            .from('settings')
            .stream(primaryKey: ['resto_id']).eq('resto_id', widget.restoId),
        builder: (context, snapshot) {
          final data = snapshot.data?.isNotEmpty == true ? snapshot.data!.first : null;
          final merchantName = data?['merchant_name'] as String? ?? 'Toko';
          final qrisId = data?['qris_id'] as String? ?? '-';
          final qrData =
              'DUMMY-QRIS|MERCHANT:$merchantName|ID:$qrisId|AMOUNT:${widget.amount}|ORDER:${widget.orderId}';

          return Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(merchantName,
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                const SizedBox(height: 4),
                Text(
                  currency.format(widget.amount),
                  style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 24),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.08),
                        blurRadius: 12,
                      ),
                    ],
                  ),
                  child: QrImageView(data: qrData, version: QrVersions.auto, size: 220),
                ),
                const SizedBox(height: 16),
                const Text(
                  '(QR dummy — belum terhubung ke payment gateway sungguhan)',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey, fontSize: 12),
                ),
                const SizedBox(height: 32),
                FilledButton(
                  onPressed: _confirming ? null : _confirmPaid,
                  child: _confirming
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Text('Simulasikan: Sudah Dibayar'),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _OrderPlacedScreen extends StatelessWidget {
  final String orderId;

  const _OrderPlacedScreen({required this.orderId});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Pesanan Diterima'),
        automaticallyImplyLeading: false,
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 84,
                height: 84,
                decoration: const BoxDecoration(color: Colors.green, shape: BoxShape.circle),
                child: const Icon(Icons.check, color: Colors.white, size: 48),
              ),
              const SizedBox(height: 16),
              const Text('Pembayaran Berhasil',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Text('Nomor pesanan: ${orderId.substring(0, 8).toUpperCase()}',
                  style: const TextStyle(color: Colors.grey)),
              const SizedBox(height: 4),
              const Text(
                'Pesanan kamu sudah masuk ke kasir dan sedang diproses.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: () => Navigator.of(context).popUntil((r) => r.isFirst),
                child: const Text('Selesai'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
