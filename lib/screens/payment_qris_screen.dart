import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../providers/settings_provider.dart';

/// Dummy QRIS payment screen. Generates a placeholder QR code locally
/// (no network call) encoding the merchant info + amount, just so the
/// cashier flow feels realistic. Nothing here talks to a real payment
/// gateway — merchant name / QRIS ID come from Settings.
class PaymentQrisScreen extends StatelessWidget {
  final int amount;

  const PaymentQrisScreen({super.key, required this.amount});

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider>();
    final currency = NumberFormat.currency(
      locale: 'id_ID',
      symbol: 'Rp ',
      decimalDigits: 0,
    );
    final qrData =
        'DUMMY-QRIS|MERCHANT:${settings.merchantName}|ID:${settings.qrisId}|AMOUNT:$amount';

    return Scaffold(
      appBar: AppBar(title: const Text('Bayar dengan QRIS')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              settings.merchantName,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 4),
            Text(
              currency.format(amount),
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
              child: QrImageView(
                data: qrData,
                version: QrVersions.auto,
                size: 220,
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              '(QR dummy — belum terhubung ke payment gateway sungguhan)',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey, fontSize: 12),
            ),
            const SizedBox(height: 32),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Simulasikan: Sudah Dibayar'),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Batal'),
            ),
          ],
        ),
      ),
    );
  }
}
