
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../db/merchant_review_repository.dart';
import '../models/merchant_review.dart';
import '../models/opening_hours.dart';
import '../models/restaurant.dart';
import '../providers/auth_provider.dart';
import '../theme.dart';
import '../utils/gambar_base64.dart';
import '../utils/resto_location.dart';
import '../widgets/responsive.dart';
import 'merchant_review_form.dart';

final _tanggal = DateFormat('d MMM yyyy', 'id_ID');

/// Info merchant untuk pelanggan: alamat, fasilitas, jam buka, dan apa
/// kata orang yang sudah ke sana.
///
/// Dipakai juga oleh pegawai merchant untuk membaca penilaian yang masuk
/// — [bolehMenilai] yang membedakan. Menyalinnya jadi dua layar berarti
/// dua tempat yang harus diingat berbarengan tiap kali bentuk ulasannya
/// berubah.
class MerchantInfoScreen extends StatefulWidget {
  final Restaurant merchant;

  /// Tombol "Beri Penilaian" muncul. Mati untuk tamu dan untuk pegawai
  /// merchant — yang menilai tempatnya sendiri bukan penilaian.
  final bool bolehMenilai;

  const MerchantInfoScreen({
    super.key,
    required this.merchant,
    this.bolehMenilai = true,
  });

  @override
  State<MerchantInfoScreen> createState() => _MerchantInfoScreenState();
}

class _MerchantInfoScreenState extends State<MerchantInfoScreen> {
  final _repo = MerchantReviewRepository();
  List<MerchantReview> _ulasan = const [];
  bool _memuat = true;

  @override
  void initState() {
    super.initState();
    _muat();
  }

  Future<void> _muat() async {
    try {
      final r = await _repo.forResto(widget.merchant.id);
      if (!mounted) return;
      setState(() {
        _ulasan = r;
        _memuat = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _memuat = false);
    }
  }

  double get _rata => _ulasan.isEmpty
      ? 0
      : _ulasan.map((u) => u.rating).reduce((a, b) => a + b) / _ulasan.length;

  Future<void> _beriPenilaian() async {
    final tersimpan = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => MerchantReviewForm(merchant: widget.merchant),
      ),
    );
    if (tersimpan == true) _muat();
  }

  @override
  Widget build(BuildContext context) {
    final m = widget.merchant;
    final auth = context.watch<AuthProvider>();
    final bisa = widget.bolehMenilai && auth.isLoggedIn && !auth.isEmployee;

    return Scaffold(
      backgroundColor: KaataTheme.backgroundOf(context),
      appBar: AppBar(title: Text(m.name)),
      floatingActionButton: bisa
          ? FloatingActionButton.extended(
              onPressed: _beriPenilaian,
              icon: const Icon(Icons.star_outline),
              label: const Text('Beri Penilaian'),
            )
          : null,
      body: RefreshIndicator(
        onRefresh: _muat,
        child: ResponsiveCenter(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 96),
            children: [
              _Kartu(
                ikon: Icons.storefront_outlined,
                judul: 'Alamat',
                anak: [
                  Text(m.address.isEmpty ? 'Belum diisi' : m.address,
                      style: const TextStyle(fontSize: 13.5, height: 1.4)),
                  if (m.hasLocation) ...[
                    const SizedBox(height: 6),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        style: TextButton.styleFrom(
                          padding: EdgeInsets.zero,
                          minimumSize: const Size(0, 30),
                        ),
                        icon: const Icon(Icons.directions_outlined, size: 16),
                        label: const Text('Buka di Google Maps'),
                        onPressed: () => openInMaps(
                          m.latitude!,
                          m.longitude!,
                          label: m.name,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
              if (m.phone != null && m.phone!.isNotEmpty)
                _Kartu(
                  ikon: Icons.call_outlined,
                  judul: 'Nomor Telepon',
                  anak: [
                    Text(m.phone!, style: const TextStyle(fontSize: 13.5)),
                  ],
                ),
              if (m.facilities.isNotEmpty)
                _Kartu(
                  ikon: Icons.chair_outlined,
                  judul: 'Fasilitas',
                  anak: [
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        for (final f in m.facilities)
                          Chip(
                            label: Text(f,
                                style: const TextStyle(fontSize: 12)),
                            visualDensity: VisualDensity.compact,
                          ),
                      ],
                    ),
                  ],
                ),
              if (m.openingHours.adaIsinya)
                _Kartu(
                  ikon: Icons.schedule_outlined,
                  judul: 'Jam Buka',
                  anak: [_JamBuka(jam: m.openingHours)],
                ),
              _Kartu(
                ikon: Icons.star_outline,
                judul: 'Penilaian',
                anak: [
                  if (_memuat)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 16),
                      child: Center(child: CircularProgressIndicator()),
                    )
                  else if (_ulasan.isEmpty)
                    Text(
                      bisa
                          ? 'Belum ada penilaian. Jadilah yang pertama.'
                          : 'Belum ada penilaian.',
                      style: TextStyle(
                          fontSize: 12.5, color: KaataTheme.mutedOf(context)),
                    )
                  else ...[
                    Row(
                      children: [
                        Text(
                          _rata.toStringAsFixed(1).replaceAll('.', ','),
                          style: const TextStyle(
                              fontSize: 32, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(width: 10),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _Bintang(nilai: _rata),
                            const SizedBox(height: 2),
                            Text('${_ulasan.length} penilaian',
                                style: TextStyle(
                                    fontSize: 12,
                                    color: KaataTheme.mutedOf(context))),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    for (final u in _ulasan) _BarisUlasan(ulasan: u),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _JamBuka extends StatelessWidget {
  final OpeningHours jam;

  const _JamBuka({required this.jam});

  @override
  Widget build(BuildContext context) {
    final hariIni = DateTime.now().weekday;
    return Column(
      children: [
        for (var h = 1; h <= 7; h++)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Row(
              children: [
                SizedBox(
                  width: 74,
                  child: Text(
                    OpeningHours.namaHari[h]!,
                    style: TextStyle(
                      fontSize: 13,
                      // Hari ini ditebalkan — yang membuka layar ini
                      // hampir selalu sedang bertanya "sekarang buka
                      // tidak", bukan "hari Kamis buka jam berapa".
                      fontWeight:
                          h == hariIni ? FontWeight.bold : FontWeight.normal,
                    ),
                  ),
                ),
                Text(
                  jam.perHari[h] == null
                      ? 'Tutup'
                      : '${jam.perHari[h]!.$1} – ${jam.perHari[h]!.$2}',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight:
                        h == hariIni ? FontWeight.bold : FontWeight.normal,
                    color: jam.perHari[h] == null
                        ? KaataTheme.mutedOf(context)
                        : null,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _BarisUlasan extends StatelessWidget {
  final MerchantReview ulasan;

  const _BarisUlasan({required this.ulasan});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(ulasan.customerName,
                    style: const TextStyle(
                        fontWeight: FontWeight.w600, fontSize: 13)),
              ),
              Text(_tanggal.format(ulasan.createdAt),
                  style: TextStyle(
                      fontSize: 11, color: KaataTheme.mutedOf(context))),
            ],
          ),
          const SizedBox(height: 3),
          _Bintang(nilai: ulasan.rating.toDouble(), ukuran: 14),
          if (ulasan.punyaKomentar) ...[
            const SizedBox(height: 5),
            Text(ulasan.comment!,
                style: const TextStyle(fontSize: 13, height: 1.4)),
          ],
          if (ulasan.punyaFoto) ...[
            const SizedBox(height: 8),
            SizedBox(
              height: 82,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: ulasan.photos.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (context, i) => ClipRRect(
                  borderRadius: BorderRadius.circular(9),
                  child: Image.memory(
                    byteGambar(ulasan.photos[i]),
                    width: 82,
                    height: 82,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _Bintang extends StatelessWidget {
  final double nilai;
  final double ukuran;

  const _Bintang({required this.nilai, this.ukuran = 17});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 1; i <= 5; i++)
          Icon(
            nilai >= i
                ? Icons.star
                : nilai >= i - 0.5
                    ? Icons.star_half
                    : Icons.star_border,
            size: ukuran,
            color: const Color(0xFFF59E0B),
          ),
      ],
    );
  }
}

class _Kartu extends StatelessWidget {
  final IconData ikon;
  final String judul;
  final List<Widget> anak;

  const _Kartu({required this.ikon, required this.judul, required this.anak});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: KaataTheme.surfaceOf(context),
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: KaataTheme.borderOf(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(ikon, size: 17, color: KaataTheme.brandOf(context)),
              const SizedBox(width: 8),
              Text(judul,
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 14)),
            ],
          ),
          const SizedBox(height: 10),
          ...anak,
        ],
      ),
    );
  }
}
