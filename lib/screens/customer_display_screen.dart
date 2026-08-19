import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../db/customer_display_repository.dart';
import '../providers/auth_provider.dart';
import '../providers/settings_provider.dart';
import '../theme.dart';
import '../widgets/promo_banner_carousel.dart';

final _rupiah =
    NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0);

/// Layar yang menghadap pelanggan di meja kasir.
///
/// Dibuka di perangkat kedua — HP atau tablet bekas yang diputar
/// menghadap keluar. Isinya mengikuti apa yang sedang ditagih kasir,
/// berubah seketika lewat realtime.
///
/// Yang ditampilkan datang dari satu baris `customer_displays` milik
/// restonya, bukan ditebak dari tagihan terakhir. Tebakan semacam itu
/// meleset persis saat paling ramai: dua kasir melayani berbarengan,
/// dan layar depan menampilkan tagihan orang yang mengantre di
/// belakang.
class CustomerDisplayScreen extends StatefulWidget {
  const CustomerDisplayScreen({super.key});

  @override
  State<CustomerDisplayScreen> createState() => _CustomerDisplayScreenState();
}

class _CustomerDisplayScreenState extends State<CustomerDisplayScreen> {
  final _repo = CustomerDisplayRepository();
  Stream<TampilanLayar>? _aliran;
  String? _restoId;

  @override
  void initState() {
    super.initState();
    // Layar penuh: perangkat ini tidak dipakai menavigasi apa pun, dan
    // bilah status yang menampilkan jam serta notifikasi pemiliknya
    // bukan sesuatu yang perlu dilihat pelanggan.
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  }

  @override
  void dispose() {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final restoId = context.watch<AuthProvider>().restoId;
    if (restoId == null) {
      return const Scaffold(
        body: Center(child: Text('Pilih merchant dulu sebelum membuka layar ini.')),
      );
    }
    if (_restoId != restoId) {
      _restoId = restoId;
      _aliran = _repo.watch(restoId);
    }

    return Scaffold(
      backgroundColor: KaataTheme.backgroundOf(context),
      body: SafeArea(
        child: StreamBuilder<TampilanLayar>(
          stream: _aliran,
          builder: (context, snapshot) {
            final t = snapshot.data ?? const TampilanLayar();
            return switch (t.status) {
              StatusLayar.menunggu => _Menunggu(tampilan: t),
              StatusLayar.lunas => _Lunas(tampilan: t),
              StatusLayar.menganggur => _Menganggur(restoId: restoId),
            };
          },
        ),
      ),
    );
  }
}

/// Saat tidak ada yang ditagih.
///
/// Diisi banner promo restonya, bukan dibiarkan kosong: layar yang
/// menghadap pelanggan dan menampilkan ruang kosong selama berjam-jam
/// adalah ruang iklan yang dibuang.
class _Menganggur extends StatelessWidget {
  final String restoId;

  const _Menganggur({required this.restoId});

  @override
  Widget build(BuildContext context) {
    final nama = context.watch<SettingsProvider>().merchantName;
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(nama,
            style: const TextStyle(fontSize: 30, fontWeight: FontWeight.bold)),
        const SizedBox(height: 6),
        Text('Selamat datang',
            style:
                TextStyle(fontSize: 16, color: KaataTheme.mutedOf(context))),
        const SizedBox(height: 24),
        PromoBannerCarousel(restoId: restoId),
      ],
    );
  }
}

class _Menunggu extends StatelessWidget {
  final TampilanLayar tampilan;

  const _Menunggu({required this.tampilan});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (tampilan.label != null && tampilan.label!.isNotEmpty) ...[
            Text(tampilan.label!,
                style: TextStyle(
                    fontSize: 17, color: KaataTheme.mutedOf(context))),
            const SizedBox(height: 8),
          ],
          Text('Total yang dibayar',
              style:
                  TextStyle(fontSize: 15, color: KaataTheme.mutedOf(context))),
          const SizedBox(height: 4),
          // Nominalnya yang paling besar di layar. Inilah satu-satunya
          // angka yang benar-benar perlu dibaca pelanggan dari jarak
          // sejangkauan tangan.
          Text(
            _rupiah.format(tampilan.amount ?? 0),
            style: TextStyle(
              fontSize: 44,
              fontWeight: FontWeight.bold,
              color: KaataTheme.brandOf(context),
            ),
          ),
          const SizedBox(height: 22),
          if (tampilan.adaQr) ...[
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(18),
              ),
              child: QrImageView(
                data: tampilan.qrString!,
                size: 260,
                backgroundColor: Colors.white,
              ),
            ),
            const SizedBox(height: 14),
            Text('Pindai untuk membayar',
                style: TextStyle(
                    fontSize: 14, color: KaataTheme.mutedOf(context))),
          ] else
            Text('Silakan bayar di kasir',
                style: TextStyle(
                    fontSize: 16, color: KaataTheme.mutedOf(context))),
        ],
      ),
    );
  }
}

class _Lunas extends StatelessWidget {
  final TampilanLayar tampilan;

  const _Lunas({required this.tampilan});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Icon(Icons.check_circle, size: 96, color: Colors.green),
        const SizedBox(height: 16),
        const Text('Pembayaran Diterima',
            style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold)),
        if (tampilan.amount != null) ...[
          const SizedBox(height: 6),
          Text(_rupiah.format(tampilan.amount),
              style: TextStyle(
                  fontSize: 20, color: KaataTheme.mutedOf(context))),
        ],
        const SizedBox(height: 10),
        Text('Terima kasih',
            style:
                TextStyle(fontSize: 16, color: KaataTheme.mutedOf(context))),
      ],
    );
  }
}
