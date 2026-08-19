import 'dart:async';
import 'dart:convert';
import 'dart:ui';

import 'package:flutter/material.dart';

import '../db/promo_banner_repository.dart';
import '../models/promo_banner.dart';
import '../theme.dart';

/// Banner promo resto di bagian atas halaman menu.
///
/// Tidak menampilkan apa pun kalau restonya belum memasang banner —
/// ruang kosong bergaris di atas daftar menu lebih mengganggu daripada
/// tidak ada apa-apa, dan sebagian besar resto baru memang belum punya
/// promo.
class PromoBannerCarousel extends StatefulWidget {
  final String restoId;

  const PromoBannerCarousel({super.key, required this.restoId});

  @override
  State<PromoBannerCarousel> createState() => _PromoBannerCarouselState();
}

class _PromoBannerCarouselState extends State<PromoBannerCarousel> {
  final _controller = PageController();
  List<PromoBanner> _banners = [];
  int _index = 0;
  Timer? _timer;

  /// Perbandingan sisi gambar bannernya, dibaca dari gambarnya sendiri.
  ///
  /// Sebelumnya kotaknya dipatok 16:9 dengan anggapan banner promo
  /// hampir selalu dibuat begitu. Yang bukan 16:9 jadi menyisakan pita
  /// kabur di sisinya — dan pita itu yang membuat bannernya terlihat
  /// tidak menyatu dengan halamannya.
  ///
  /// Null selama gambarnya belum selesai dibaca; selama itu kotaknya
  /// memakai 16:9 supaya tata letaknya tidak melompat dua kali.
  double? _rasio;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(PromoBannerCarousel old) {
    super.didUpdateWidget(old);
    // Berpindah resto berarti bannernya ikut berganti; tanpa ini, promo
    // resto sebelumnya tertinggal di layar.
    if (old.restoId != widget.restoId) _load();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final items = await PromoBannerRepository().activeForResto(widget.restoId);
      if (!mounted) return;
      setState(() {
        _banners = items;
        _index = 0;
        _rasio = null;
      });
      unawaited(_bacaRasio(items));
      _restartAutoplay();
    } catch (_) {
      // Offline atau tabelnya belum ada — halaman menunya tetap jalan
      // tanpa banner.
    }
  }

  void _restartAutoplay() {
    _timer?.cancel();
    if (_banners.length < 2) return;
    _timer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (!mounted || !_controller.hasClients) return;
      final next = (_index + 1) % _banners.length;
      _controller.animateToPage(
        next,
        duration: const Duration(milliseconds: 450),
        curve: Curves.easeInOut,
      );
    });
  }

  void _openDetail(PromoBanner banner) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => Dialog(
        insetPadding: const EdgeInsets.all(16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        clipBehavior: Clip.antiAlias,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            InteractiveViewer(
              child: Image.memory(
                base64Decode(banner.imageBase64),
                fit: BoxFit.contain,
                errorBuilder: (_, __, ___) => const SizedBox.shrink(),
              ),
            ),
            if ((banner.title != null && banner.title!.isNotEmpty) ||
                (banner.description != null && banner.description!.isNotEmpty))
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (banner.title != null && banner.title!.isNotEmpty)
                      Text(banner.title!,
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                    if (banner.description != null && banner.description!.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(banner.description!,
                            style: TextStyle(fontSize: 13, color: KaataTheme.mutedOf(context))),
                      ),
                  ],
                ),
              ),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Tutup'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Membaca ukuran asli tiap banner, lalu memakai yang paling jangkung.
  ///
  /// Yang paling jangkung, bukan rata-ratanya: kotak yang lebih pendek
  /// dari salah satu gambarnya akan menyisakan pita untuk gambar itu —
  /// dan tidak ada satu kotak pun yang pas untuk semuanya kalau
  /// bannernya beda-beda bentuk.
  Future<void> _bacaRasio(List<PromoBanner> items) async {
    double? paling;
    for (final b in items) {
      try {
        final gambar = await decodeImageFromList(base64Decode(b.imageBase64));
        final r = gambar.width / gambar.height;
        gambar.dispose();
        if (paling == null || r < paling) paling = r;
      } catch (_) {
        // Satu banner rusak tidak boleh menghentikan pembacaan yang lain.
      }
    }
    if (!mounted || paling == null) return;
    // Dijepit supaya banner yang salah ukuran — potret, atau pita
    // sangat panjang — tidak mengambil alih halaman menunya.
    setState(() => _rasio = paling!.clamp(1.6, 3.2));
  }

  @override
  Widget build(BuildContext context) {
    if (_banners.isEmpty) return const SizedBox.shrink();

    return Column(
      children: [
        const SizedBox(height: 10),
        // Lebarnya dibatasi lalu ditaruh di tengah. Tanpa ini, 16:9
        // selebar tablet berarti banner ratusan piksel tingginya yang
        // mendorong seluruh menunya keluar layar. Di HP batas ini tidak
        // berpengaruh apa-apa — layarnya memang lebih sempit.
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: AspectRatio(
          // Mengikuti bentuk gambarnya, bukan angka yang dipatok. Kotak
          // yang bentuknya berbeda dari gambarnya menyisakan pita di
          // sisinya, dan pita itu yang membuat bannernya terlihat tidak
          // menyatu dengan halamannya.
          aspectRatio: _rasio ?? 16 / 9,
          child: PageView.builder(
            controller: _controller,
            itemCount: _banners.length,
            onPageChanged: (i) => setState(() => _index = i),
            itemBuilder: (context, i) {
              final banner = _banners[i];
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: GestureDetector(
                  onTap: () => _openDetail(banner),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        // Latar: gambar yang sama, dipotong penuh lalu
                        // dikaburkan. Yang tampil di depan harus utuh,
                        // dan itu menyisakan pita kosong di sisi gambar
                        // yang bentuknya tidak pas — pita abu-abu polos
                        // terlihat seperti gambarnya gagal dimuat,
                        // sedangkan latar kabur ini terbaca sebagai
                        // bagian dari bannernya.
                        ImageFiltered(
                          imageFilter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
                          child: Image.memory(
                            base64Decode(banner.imageBase64),
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) =>
                                Container(color: KaataTheme.softFillOf(context)),
                          ),
                        ),
                        Image.memory(
                          base64Decode(banner.imageBase64),
                          // Utuh, tidak dipotong: yang terpotong biasanya
                          // justru nominal diskon atau tanggal
                          // berlakunya, yang ditaruh perancangnya di tepi
                          // gambar.
                          fit: BoxFit.contain,
                          // Satu banner rusak tidak boleh mengosongkan
                          // seluruh halaman menu.
                          errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                        ),
                        if (banner.title != null && banner.title!.isNotEmpty)
                          Positioned(
                            left: 0,
                            right: 0,
                            bottom: 0,
                            child: Container(
                              padding: const EdgeInsets.fromLTRB(12, 18, 12, 10),
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment.topCenter,
                                  end: Alignment.bottomCenter,
                                  colors: [
                                    Colors.transparent,
                                    Colors.black.withOpacity(0.55),
                                  ],
                                ),
                              ),
                              child: Text(
                                banner.title!,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13.5,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
            ),
          ),
        ),
        if (_banners.length > 1) ...[
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (var i = 0; i < _banners.length; i++)
                AnimatedContainer(
                  duration: const Duration(milliseconds: 250),
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  width: i == _index ? 18 : 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: i == _index ? KaataTheme.brand : KaataTheme.borderOf(context),
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
            ],
          ),
        ],
        const SizedBox(height: 4),
      ],
    );
  }
}
