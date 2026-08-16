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
      });
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

  @override
  Widget build(BuildContext context) {
    if (_banners.isEmpty) return const SizedBox.shrink();

    return Column(
      children: [
        const SizedBox(height: 10),
        AspectRatio(
          // 16:9, bukan tinggi tetap. Banner promo hampir selalu dibuat
          // dengan perbandingan itu, jadi gambarnya mengisi kotaknya
          // hampir persis — dan tinggi tetap 148 memaksa gambar apa pun
          // masuk ke kotak yang bukan bentuknya.
          aspectRatio: 16 / 9,
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
