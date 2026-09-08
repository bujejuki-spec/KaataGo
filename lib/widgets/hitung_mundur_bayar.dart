import 'dart:async';

import 'package:flutter/material.dart';

import '../theme.dart';

/// Sisa waktu membayar sebelum pesanannya hangus sendiri.
///
/// Satu kartu untuk dua layar — bayar di kasir dan bayar QRIS — karena
/// yang dijanjikannya sama persis: tiga puluh menit sejak pesanan
/// dibuat, lalu dibatalkan server. Dua salinan kalimat yang menjanjikan
/// hal yang sama akan berpisah pada perubahan berikutnya, dan yang
/// membacanya tidak punya cara tahu mana yang benar.
///
/// Batas waktu yang baru terbaca setelah lewat sama saja dengan tidak
/// pernah diberitahukan — jadi kartunya ditaruh di badan layar, bukan
/// sebagai catatan kaki.
class HitungMundurBayar extends StatefulWidget {
  final DateTime deadline;

  /// Ditulis saat waktunya sudah habis. Berbeda antar layar hanya pada
  /// apa yang bisa dilakukan orangnya sesudah itu.
  final String pesanHabis;

  const HitungMundurBayar({
    super.key,
    required this.deadline,
    this.pesanHabis = 'Batas waktu pembayaran sudah lewat.\n'
        'Pesanan ini dibatalkan — silakan pesan ulang.',
  });

  @override
  State<HitungMundurBayar> createState() => _HitungMundurBayarState();
}

class _HitungMundurBayarState extends State<HitungMundurBayar> {
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  String _jam(Duration d) {
    final m = d.inMinutes.toString().padLeft(2, '0');
    final s = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final sisa = widget.deadline.difference(DateTime.now());
    final habis = sisa.isNegative;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: habis
            ? KaataTheme.tintOf(context, Colors.red)
            : KaataTheme.softFillOf(context),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        children: [
          Icon(
            habis ? Icons.cancel_outlined : Icons.timer_outlined,
            size: 20,
            color: habis
                ? KaataTheme.onTintOf(context, Colors.red)
                : KaataTheme.mutedOf(context),
          ),
          const SizedBox(height: 6),
          if (habis)
            Text(
              widget.pesanHabis,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Color(0xFFB91C1C),
              ),
            )
          else ...[
            Text(
              'Bayar dalam ${_jam(sisa)}',
              style: const TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.bold,
                letterSpacing: 1,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              'Kalau belum dibayar sampai waktunya habis, pesanan ini '
              'otomatis dibatalkan.',
              textAlign: TextAlign.center,
              style:
                  TextStyle(fontSize: 12, color: KaataTheme.mutedOf(context)),
            ),
          ],
        ],
      ),
    );
  }
}
