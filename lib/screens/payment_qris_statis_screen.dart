import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../theme.dart';
import '../widgets/dialog_actions.dart';
import '../widgets/gambar_tersimpan.dart';
import '../widgets/responsive.dart';

/// QR statis merchant, ditunjukkan ke pelanggan di meja kasir.
///
/// Berbeda dari layar QRIS Dinamis, dan bedanya bukan tampilan: yang di
/// sana dibuat penyedia pembayaran per transaksi, membawa nominalnya di
/// dalam kode, dan berpindah sendiri begitu webhook menyatakan lunas.
/// Yang di sini gambar cetak yang sama untuk semua transaksi — tidak
/// membawa nominal, dan tidak ada satu pun kabar yang datang dari luar.
///
/// Karena itu yang menyatakan lunas adalah kasir, setelah melihat bukti
/// transfer di HP pelanggan. Nominalnya ditulis besar-besar di atas
/// QR-nya justru untuk itu: yang paling mungkin keliru bukan QR-nya,
/// melainkan jumlah yang diketik pelanggan.
class PaymentQrisStatisScreen extends StatelessWidget {
  final int amount;

  /// QR-nya: base64 kalau sudah dipasang ulang, jalur Storage kalau
  /// merchant ini memasangnya sebelum gambar pindah ke basis data.
  final RefGambar qr;

  const PaymentQrisStatisScreen({
    super.key,
    required this.amount,
    required this.qr,
  });

  @override
  Widget build(BuildContext context) {
    final rp = NumberFormat.currency(
        locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0);

    return Scaffold(
      appBar: AppBar(title: const Text('QRIS Statis')),
      body: ResponsiveCenter(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 14),
              decoration: BoxDecoration(
                color: KaataTheme.tintOf(context, Colors.amber),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Column(
                children: [
                  Text('Minta pelanggan mengirim tepat',
                      style: TextStyle(
                          fontSize: 12.5,
                          color: KaataTheme.onTintOf(context, Colors.brown))),
                  const SizedBox(height: 2),
                  Text(
                    rp.format(amount),
                    style: const TextStyle(
                      fontSize: 27,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF92400E),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: KaataTheme.borderOf(context)),
              ),
              child: SizedBox(
                height: 280,
                child: GambarTersimpan.dariRef(
                  qr,
                  ember: 'qris-statis',
                  fit: BoxFit.contain,
                  kosong: 'QR-nya belum dipasang. Pakai metode bayar '
                      'lain dulu.',
                ),
              ),
            ),
            const SizedBox(height: 14),
            Text(
              'QR ini tidak membawa nominal, jadi pelanggan mengetik '
              'jumlahnya sendiri. Pastikan bukti transfernya menyebut '
              'angka di atas sebelum menekan tombol di bawah.',
              textAlign: TextAlign.center,
              style:
                  TextStyle(fontSize: 12.5, color: KaataTheme.mutedOf(context)),
            ),
            const SizedBox(height: 20),
            // Tombolnya menyebut apa yang dinyatakan kasir, bukan
            // "Lanjut". Yang menekan ini sedang bersaksi bahwa uangnya
            // sudah terlihat masuk — dan kalimatnya harus mengatakan itu.
            FilledButton.icon(
              onPressed: () => Navigator.pop(context, true),
              icon: const Icon(Icons.verified_outlined),
              label: const Text('Sudah Terima Pembayarannya'),
              style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(50)),
            ),
            const SizedBox(height: 8),
            OutlinedButton(
              onPressed: () async {
                final batal = await showDialog<bool>(
                  context: context,
                  builder: (d) => AlertDialog(
                    title: const Text('Batalkan Pembayaran?'),
                    content: const Text(
                        'Pesanannya kembali ke keranjang dan belum tercatat.'),
                    actions: [
                      DialogActions(
                        confirmLabel: 'Ya, Batalkan',
                        destructive: true,
                        onCancel: () => Navigator.pop(d, false),
                        onConfirm: () => Navigator.pop(d, true),
                      ),
                    ],
                    actionsAlignment: MainAxisAlignment.center,
                  ),
                );
                if (batal == true && context.mounted) {
                  Navigator.pop(context, false);
                }
              },
              style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(48)),
              child: const Text('Batal'),
            ),
          ],
        ),
      ),
    );
  }
}
