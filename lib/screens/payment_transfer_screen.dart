import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../db/bank_account_repository.dart';
import '../models/bank_account.dart';
import '../providers/auth_provider.dart';
import '../widgets/app_toast.dart';

/// Layar transfer di meja kasir.
///
/// Rekeningnya dibaca dari `bank_accounts`, bukan dari salinan lama di
/// `settings`. Kolom lama itu ditinggalkan apa adanya saat rekening
/// dipindah jadi entitasnya sendiri, dan layar yang masih membacanya
/// menunjukkan nomor yang bisa berbeda dari yang sebenarnya dipakai —
/// nomor yang salah di layar ini berarti uang pelanggan mendarat di
/// rekening yang tidak lagi dipantau siapa pun.
class PaymentTransferScreen extends StatefulWidget {
  final int amount;

  const PaymentTransferScreen({super.key, required this.amount});

  @override
  State<PaymentTransferScreen> createState() => _PaymentTransferScreenState();
}

class _PaymentTransferScreenState extends State<PaymentTransferScreen> {
  /// Rekening utama saja, meski merchantnya punya beberapa.
  ///
  /// Sempat menawarkan pilihan, dan itu keliru tempatnya: yang berdiri
  /// di depan kasir adalah pelanggan yang sedang menunggu nomor untuk
  /// ditransfer, bukan orang yang sedang memutuskan rekening mana yang
  /// dipakai merchant. Pilihan di sana cuma memperlambat, dan membuka
  /// jalan bagi uang mendarat di rekening yang tidak dipantau siapa pun.
  ///
  /// Rekening mana yang utama diatur di Rekening Perusahaan.
  BankAccount? _utama;
  bool _memuat = true;

  @override
  void initState() {
    super.initState();
    _muat();
  }

  Future<void> _muat() async {
    final restoId = context.read<AuthProvider>().restoId;
    if (restoId == null) {
      setState(() => _memuat = false);
      return;
    }
    try {
      final r = await BankAccountRepository().utama(restoId);
      if (!mounted) return;
      setState(() {
        _utama = r;
        _memuat = false;
      });
    } catch (_) {
      if (mounted) setState(() => _memuat = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final currency = NumberFormat.currency(
      locale: 'id_ID',
      symbol: 'Rp ',
      decimalDigits: 0,
    );
    final r = _utama;

    return Scaffold(
      appBar: AppBar(title: const Text('Bayar dengan Transfer')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              currency.format(widget.amount),
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 24),
            if (_memuat)
              const CircularProgressIndicator()
            else if (r == null)
              const Text(
                'Belum ada rekening perusahaan. Minta Owner atau Finance '
                'menambahkannya di Rekening Perusahaan.',
                textAlign: TextAlign.center,
              )
            else ...[
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    children: [
                      Text(r.bankName,
                          style: const TextStyle(
                              fontSize: 14, color: Colors.grey)),
                      const SizedBox(height: 8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Flexible(
                            child: Text(
                              r.accountNumber,
                              style: const TextStyle(
                                  fontSize: 22,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 1),
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.copy, size: 18),
                            tooltip: 'Salin nomor rekening',
                            onPressed: () {
                              Clipboard.setData(ClipboardData(
                                  text: r.accountNumber.replaceAll(' ', '')));
                              showAppToast(context, 'Nomor rekening disalin');
                            },
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text('a.n. ${r.accountHolder}',
                          style: const TextStyle(color: Colors.grey)),
                    ],
                  ),
                ),
              ),
            ],
            const SizedBox(height: 32),
            FilledButton(
              onPressed: r == null ? null : () => Navigator.of(context).pop(true),
              child: const Text('Sudah Transfer'),
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
