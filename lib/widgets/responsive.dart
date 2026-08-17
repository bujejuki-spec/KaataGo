import 'package:flutter/material.dart';

import '../theme.dart';

/// Ambang lebar layar.
///
/// Angkanya diambil dari perangkat yang benar-benar dipakai di resto:
/// HP genggam di bawah 600, tablet 7–10 inci di kisaran 600–1000, dan
/// monitor kasir atau tablet besar di atas itu.
class Breakpoints {
  static const tablet = 600.0;
  static const desktop = 1000.0;

  static bool isPhone(BuildContext c) => MediaQuery.sizeOf(c).width < tablet;
  static bool isTablet(BuildContext c) {
    final w = MediaQuery.sizeOf(c).width;
    return w >= tablet && w < desktop;
  }

  static bool isWide(BuildContext c) => MediaQuery.sizeOf(c).width >= desktop;
}

/// Ruang kosong yang harus disisakan di dasar daftar bergulir pada layar
/// yang punya tombol mengambang.
///
/// Tombol mengambang melayang di atas isi, jadi tanpa ruang ini baris
/// terakhir selalu tertutup — dan justru baris terakhir yang paling
/// sering baru saja ditambahkan orangnya. Ukurannya: tinggi tombol
/// diperpanjang (56) + jarak amannya.
const kFabSafeBottom = 96.0;

/// Membatasi lebar isi lalu menaruhnya di tengah.
///
/// Di monitor kasir, daftar dan formulir yang dibiarkan selebar layar
/// membuat mata harus menyapu 1300 piksel untuk membaca satu baris, dan
/// tombol di ujung kanan jauh dari isi yang dituju. Membatasi lebarnya
/// membuat layar lebar terasa lapang, bukan melar.
class ResponsiveCenter extends StatelessWidget {
  final Widget child;
  final double maxWidth;
  final EdgeInsetsGeometry? padding;

  const ResponsiveCenter({
    super.key,
    required this.child,
    this.maxWidth = 840,
    this.padding,
  });

  @override
  Widget build(BuildContext context) {
    return Align(
      // heightFactor: 1 — tingginya mengikuti isinya, bukan memakan
      // seluruh ruang yang ditawarkan.
      //
      // `Center` biasa melebar ke ukuran terbesar yang diizinkan di
      // kedua arah. Di badan layar itu tidak terasa, karena badan layar
      // memberi ukuran yang sudah pasti. Tapi di bottomNavigationBar —
      // yang batasnya longgar setinggi layar — Center akan tumbuh
      // setinggi layar penuh, mendorong badan layarnya jadi nol, dan
      // hasilnya sebuah layar yang isinya lenyap sama sekali sementara
      // deretan tombolnya melayang di tengah.
      //
      // Di tempat yang batasnya sudah pasti, heightFactor ini tidak
      // berpengaruh apa-apa: ukuran pasti tetap menang.
      heightFactor: 1,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: padding == null ? child : Padding(padding: padding!, child: child),
      ),
    );
  }
}

/// Menyusun kartu menu hub jadi beberapa kolom saat layarnya cukup lebar.
///
/// Satu kolom di tablet berarti setengah layar kosong dan menu paling
/// bawah butuh gulir — padahal seluruhnya muat sekaligus kalau dibagi
/// dua. Pada HP tetap satu kolom, karena kartu berdampingan di layar
/// sempit menyisakan terlalu sedikit ruang untuk keterangannya.
/// Judul kelompok menu.
///
/// Dipakai bersama oleh seluruh hub supaya kelompok yang sama terbaca
/// sama di peran mana pun — "Keuangan" di layar Admin dan di layar Owner
/// harus terlihat sebagai hal yang sama, karena memang hal yang sama.
class HubSectionLabel extends StatelessWidget {
  final String text;

  const HubSectionLabel(this.text, {super.key});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 18, bottom: 10),
        child: Text(
          text.toUpperCase(),
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 12,
            letterSpacing: 0.8,
            color: KaataTheme.mutedOf(context),
          ),
        ),
      );
}

/// Satu kelompok menu berikut isinya.
class HubMenuSection {
  final String label;
  final List<Widget> tiles;

  const HubMenuSection(this.label, this.tiles);
}

class HubMenuLayout extends StatelessWidget {
  final List<Widget> tiles;

  /// Menu yang dikelompokkan per fungsi.
  ///
  /// Kalau diisi, [tiles] diabaikan. Dipisah jadi dua jalur, bukan satu
  /// daftar berisi label sebagai "tile": pada layar lebar tiap tile
  /// dibungkus SizedBox selebar satu kolom, dan label yang ikut terjepit
  /// di sana berhenti terbaca sebagai judul — ia jadi kartu tak
  /// bergambar di tengah barisan kartu.
  final List<HubMenuSection> sections;
  final EdgeInsetsGeometry padding;

  /// Isi tambahan di atas daftar menu (mis. judul "Menu").
  final List<Widget> header;

  const HubMenuLayout({
    super.key,
    this.tiles = const [],
    this.sections = const [],
    this.header = const [],
    this.padding = const EdgeInsets.all(20),
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= Breakpoints.desktop
            ? 3
            : constraints.maxWidth >= Breakpoints.tablet
                ? 2
                : 1;

        if (columns == 1) {
          return ListView(
            padding: padding,
            children: [
              ...header,
              if (sections.isEmpty)
                for (final tile in tiles) ...[tile, const SizedBox(height: 12)]
              else
                for (final s in sections) ...[
                  HubSectionLabel(s.label),
                  for (final tile in s.tiles) ...[tile, const SizedBox(height: 12)],
                ],
            ],
          );
        }

        return ListView(
          padding: padding,
          children: [
            ...header,
            // Wrap, bukan GridView: tinggi tiap kartu mengikuti panjang
            // keterangannya, dan grid berpetak sama besar akan memaksa
            // semuanya setinggi kartu terpanjang.
            LayoutBuilder(
              builder: (context, inner) {
                const gap = 12.0;
                final width = (inner.maxWidth - gap * (columns - 1)) / columns;

                Widget petak(List<Widget> isi) => Wrap(
                      spacing: gap,
                      runSpacing: gap,
                      children: [
                        for (final tile in isi)
                          SizedBox(width: width, child: tile),
                      ],
                    );

                if (sections.isEmpty) return petak(tiles);

                // Labelnya di luar Wrap, jadi ia tetap selebar layar.
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final s in sections) ...[
                      HubSectionLabel(s.label),
                      petak(s.tiles),
                    ],
                  ],
                );
              },
            ),
          ],
        );
      },
    );
  }
}
