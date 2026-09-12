import 'package:flutter/material.dart';

import '../theme.dart';
import '../utils/akses_menu.dart';
import 'badged_hub_tile.dart';
import 'hub_menu_tile.dart';
import 'responsive.dart';

/// Satu kelompok menu, dibuka sebagai halaman tersendiri.
///
/// Hub dengan belasan menu memaksa orang membaca seluruh daftar tiap
/// kali, karena tidak ada yang menandai di mana satu urusan berakhir.
/// Menumpuknya jadi beberapa pintu membuat halaman awalnya bisa dibaca
/// sekali lihat.
///
/// ── Yang harus ikut naik: penandanya ─────────────────────────────────
///
/// Menyembunyikan menu di balik pintu juga menyembunyikan titik merahnya
/// — dan titik merah itu satu-satunya cara orang tahu ada pengajuan yang
/// menunggu keputusannya tanpa membuka apa pun. Karena itu [loadCount]
/// di sini menjumlahkan penanda seluruh isinya: pintunya sendiri yang
/// memakai bulatan itu.
class HubGroupTile extends StatelessWidget {
  final IconData icon;
  final String title;

  /// Isi kelompoknya, ditulis apa adanya: "Kasir, Pesanan Masuk,
  /// Riwayat". Judul kelompok saja tidak memberi tahu siapa pun apa yang
  /// ada di baliknya, dan pintu yang isinya harus ditebak akan dibuka
  /// satu per satu sampai ketemu.
  final String subtitle;

  final Color color;

  /// Menu di dalamnya. Dibuat lewat fungsi supaya layarnya baru dibangun
  /// saat pintunya benar-benar dibuka.
  final List<Widget> Function() tiles;

  /// Jumlah penanda seluruh isinya. Null berarti tidak ada yang perlu
  /// ditandai.
  final Future<int> Function()? loadCount;

  const HubGroupTile({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.tiles,
    this.loadCount,
  });

  void _buka(BuildContext context) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => HubGroupScreen(title: title, tiles: tiles()),
    ));
  }

  /// Judul menu di dalam sebuah kartu, kalau kartunya memang menu.
  static String? _judul(Widget w) {
    if (w is HubMenuTile) return w.title;
    if (w is BadgedHubTile) return w.title;
    return null;
  }

  /// Apakah pintunya akan dipajang.
  ///
  /// Ditanyakan juga oleh tata letak di sekelilingnya: kartu yang
  /// menghilang tapi jaraknya tetap ada meninggalkan lubang di tengah
  /// daftar, dan lubang itu terbaca sebagai menu yang gagal dimuat.
  bool terlihat(BuildContext context) {
    final akses = AksesMenu.of(context);
    if (akses == null || akses.peta.isEmpty) return true;
    final judulIsi = [
      for (final w in tiles())
        if (_judul(w) != null) _judul(w)!,
    ];
    return judulIsi.isEmpty || judulIsi.any(akses.bolehLihat);
  }

  @override
  Widget build(BuildContext context) {
    // Pintu yang di baliknya tidak ada apa-apa tidak dipajang.
    //
    // Tiap menu menyembunyikan dirinya sendiri saat aksesnya dicabut,
    // dan itu cukup untuk menunya — tapi kelompoknya tidak ikut tahu.
    // Yang tersisa adalah kartu yang mengundang orang masuk ke halaman
    // kosong, dan halaman kosong tanpa sebab terbaca sebagai aplikasi
    // yang rusak.
    //
    // Yang dihitung hanya kartu yang memang menu. Kelompok yang isinya
    // bukan menu sama sekali — keterangan, pemisah, apa pun — tidak
    // pernah disembunyikan: sama seperti seluruh fitur ini, yang tidak
    // dikenali jatuh ke "boleh".
    //
    // Isinya baru dibangun kalau merchant ini memang punya pembatasan.
    // [tiles] sengaja berupa fungsi supaya isinya tidak dibangun sampai
    // pintunya dibuka; memanggilnya di sini untuk setiap kelompok
    // membatalkan itu. Selama petanya kosong — keadaan setiap merchant
    // yang belum diatur KaataGo Admin — tidak ada yang perlu diperiksa,
    // jadi tidak ada yang dibangun.
    if (!terlihat(context)) return const SizedBox.shrink();

    if (loadCount == null) {
      return HubMenuTile(
        icon: icon,
        title: title,
        subtitle: subtitle,
        color: color,
        onTap: () => _buka(context),
      );
    }
    return BadgedHubTile(
      icon: icon,
      title: title,
      subtitle: subtitle,
      color: color,
      loadCount: loadCount!,
      destination: () => HubGroupScreen(title: title, tiles: tiles()),
    );
  }
}

/// Halaman isi sebuah kelompok menu.
class HubGroupScreen extends StatelessWidget {
  final String title;
  final List<Widget> tiles;

  const HubGroupScreen({super.key, required this.title, required this.tiles});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: KaataTheme.backgroundOf(context),
      appBar: AppBar(title: Text(title)),
      body: HubMenuLayout(tiles: tiles),
    );
  }
}
