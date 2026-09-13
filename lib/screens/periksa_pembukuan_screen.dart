import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../db/periksa_pembukuan_repository.dart';
import '../providers/auth_provider.dart';
import '../theme.dart';
import '../utils/akses_menu.dart';
import '../utils/pesan_galat.dart';
import '../widgets/responsive.dart';

/// Pemeriksa konsistensi pembukuan.
///
/// Kekeliruan pembukuan di aplikasi ini selalu berbentuk sama: satu uang
/// terhitung di dua tempat, atau satu angka berbeda tergantung siapa
/// yang melihatnya. Selama ini yang menemukannya adalah orang yang
/// kebetulan memperhatikan angka yang ganjil — cara menemukan yang tidak
/// bisa diandalkan. Selisih seratus ribu memang terlihat; dua ribu
/// tidak, dan merchant yang jarang dibuka tidak akan pernah dilihat.
///
/// Layar ini memeriksa aturan yang tidak boleh dilanggar, dan hanya
/// melaporkan yang dilanggar. Ia tidak memperbaiki apa pun: pemeriksa
/// yang sekaligus membetulkan akan menyembunyikan sebabnya, dan yang
/// perlu diperbaiki hampir selalu kodenya, bukan barisnya.
class PeriksaPembukuanScreen extends StatefulWidget {
  const PeriksaPembukuanScreen({super.key});

  @override
  State<PeriksaPembukuanScreen> createState() =>
      _PeriksaPembukuanScreenState();
}

class _PeriksaPembukuanScreenState extends State<PeriksaPembukuanScreen> {
  final _repo = PeriksaPembukuanRepository();
  final _rp =
      NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0);

  List<TemuanPembukuan>? _temuan;
  bool _memuat = true;
  String? _galat;

  @override
  void initState() {
    super.initState();
    _periksa();
  }

  Future<void> _periksa() async {
    final restoId = context.read<AuthProvider>().restoId;
    if (restoId == null) {
      setState(() => _memuat = false);
      return;
    }
    setState(() {
      _memuat = true;
      _galat = null;
    });
    try {
      final hasil = await _repo.periksa(restoId);
      if (!mounted) return;
      setState(() {
        _temuan = hasil;
        _memuat = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _galat = pesanGalat(e);
        _memuat = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return berdasarkanAkses(
      context,
      'Periksa Pembukuan',
      Scaffold(
        backgroundColor: KaataTheme.backgroundOf(context),
        appBar: AppBar(
          title: const Text('Periksa Pembukuan'),
          actions: [
            IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: 'Periksa ulang',
              onPressed: _memuat ? null : _periksa,
            ),
          ],
        ),
        body: _memuat
            ? const Center(child: CircularProgressIndicator())
            : _galat != null
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.error_outline,
                              size: 44, color: Colors.red),
                          const SizedBox(height: 12),
                          Text('Gagal memeriksa: $_galat',
                              textAlign: TextAlign.center),
                          const SizedBox(height: 14),
                          FilledButton(
                              onPressed: _periksa,
                              child: const Text('Coba Lagi')),
                        ],
                      ),
                    ),
                  )
                : RefreshIndicator(
                    onRefresh: _periksa,
                    child: ResponsiveCenter(
                      child: ListView(
                        padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
                        children: [
                          _Ringkasan(jumlah: _temuan?.length ?? 0),
                          const SizedBox(height: 16),
                          if ((_temuan ?? const []).isEmpty)
                            _YangDiperiksa()
                          else
                            for (final t in _temuan!)
                              _KartuTemuan(temuan: t, rp: _rp),
                        ],
                      ),
                    ),
                  ),
      ),
    );
  }
}

class _Ringkasan extends StatelessWidget {
  final int jumlah;

  const _Ringkasan({required this.jumlah});

  @override
  Widget build(BuildContext context) {
    final bersih = jumlah == 0;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: bersih
              ? [const Color(0xFF10B981), const Color(0xFF0F766E)]
              : [const Color(0xFFDC2626), const Color(0xFF991B1B)],
        ),
      ),
      child: Row(
        children: [
          Icon(bersih ? Icons.verified_outlined : Icons.warning_amber_outlined,
              color: Colors.white, size: 30),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  bersih ? 'Pembukuan cocok' : '$jumlah hal perlu diperiksa',
                  style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: Colors.white),
                ),
                const SizedBox(height: 4),
                Text(
                  bersih
                      ? 'Semua aturan yang diperiksa terpenuhi saat ini.'
                      : 'Angkanya belum tentu salah — tapi ada yang tidak '
                          'bisa dijelaskan, dan itu perlu dilihat.',
                  style: TextStyle(
                      fontSize: 12.5, color: Colors.white.withOpacity(0.85)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Daftar yang diperiksa, ditampilkan justru saat semuanya cocok.
///
/// Layar yang cuma berbunyi "aman" tanpa menyebutkan apa yang
/// diperiksanya menuntut orang percaya begitu saja — dan kepercayaan
/// semacam itu adalah yang pertama runtuh saat suatu hari ada angka yang
/// ternyata salah.
class _YangDiperiksa extends StatelessWidget {
  static const _daftar = [
    'Titipan setoran tunai habis setelah diputuskan',
    'Titipan cash pickup habis setelah diserahterimakan',
    'Saldo Cash dan Saldo Bank Perusahaan tidak minus',
    'Isi laci kasir tidak minus',
    'Penjualan non-tunai kemarin sudah masuk Saldo Bank',
    'Tiap pengeluaran punya lawan akunnya di jurnal',
  ];

  @override
  Widget build(BuildContext context) {
    final muted = KaataTheme.mutedOf(context);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: KaataTheme.softFillOf(context),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Yang diperiksa',
              style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.bold,
                  color: muted)),
          const SizedBox(height: 10),
          for (final d in _daftar)
            Padding(
              padding: const EdgeInsets.only(bottom: 7),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.check, size: 15, color: Color(0xFF10B981)),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Text(d,
                        style: TextStyle(fontSize: 12.5, color: muted)),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _KartuTemuan extends StatelessWidget {
  final TemuanPembukuan temuan;
  final NumberFormat rp;

  const _KartuTemuan({required this.temuan, required this.rp});

  @override
  Widget build(BuildContext context) {
    final muted = KaataTheme.mutedOf(context);
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.report_gmailerrorred_outlined,
                    size: 20, color: Color(0xFFDC2626)),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(temuan.aturan,
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 14)),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(temuan.keterangan,
                style: TextStyle(fontSize: 12.5, color: muted, height: 1.4)),
            const SizedBox(height: 8),
            Row(
              children: [
                Text('Selisih ',
                    style: TextStyle(fontSize: 12.5, color: muted)),
                Text(rp.format(temuan.selisih),
                    style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFFDC2626))),
              ],
            ),
            const SizedBox(height: 8),
            // Ke mana harus melihat. Temuan tanpa arah cuma memindahkan
            // kebingungan dari angka ke kalimat.
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.arrow_forward, size: 14, color: muted),
                const SizedBox(width: 7),
                Expanded(
                  child: Text(temuan.petunjuk,
                      style: TextStyle(fontSize: 12, color: muted)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
