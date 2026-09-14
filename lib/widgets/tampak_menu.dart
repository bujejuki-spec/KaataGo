import 'package:flutter/widgets.dart';

import '../utils/akses_menu.dart';
import 'badged_hub_tile.dart';
import 'hub_group_tile.dart';
import 'hub_menu_tile.dart';

/// Apakah sebuah kartu menu akan benar-benar tampil.
///
/// Tiap kartu sudah menyembunyikan dirinya sendiri saat aksesnya
/// dicabut. Yang tidak ikut hilang adalah JARAK di sekelilingnya: tata
/// letaknya menyisipkan pemisah di antara kartu, dan pemisah milik
/// kartu yang menghilang tetap berdiri — meninggalkan lubang selebar
/// dua jarak di tengah daftar.
///
/// Lubang itu bukan sekadar kurang rapi. Ia terbaca sebagai menu yang
/// gagal dimuat, dan yang membacanya akan menutup lalu membuka
/// aplikasinya untuk memastikan.
///
/// Yang tidak dikenali dianggap tampil — sama seperti seluruh fitur
/// akses menu, yang tidak jelas jatuh ke "boleh".
bool tileTerlihat(BuildContext context, Widget tile) {
  if (tile is HubMenuTile) return bolehLihatMenu(context, tile.title);
  if (tile is BadgedHubTile) return bolehLihatMenu(context, tile.title);
  if (tile is HubGroupTile) return tile.terlihat(context);
  return true;
}

/// Kartu yang tersisa sesudah yang dicabut dibuang, berikut jaraknya.
List<Widget> tileTampak(BuildContext context, List<Widget> tiles) =>
    [for (final t in tiles) if (tileTerlihat(context, t)) t];

/// Kartu yang tersisa, berikut jaraknya disisipkan SESUDAH penyaringan.
///
/// Beranda yang menuliskan jaraknya sendiri di antara kartu punya
/// masalah yang tidak terlihat sampai ada menu yang dicabut UAM:
/// kartunya hilang, tapi dua `SizedBox` pengapitnya tetap tinggal.
/// Yang terlihat lubang selebar dua kali jarak biasa — dan itu terbaca
/// sebagai kartu yang gagal dimuat, bukan sebagai kartu yang memang
/// tidak boleh dilihat.
///
/// Jaraknya disisipkan di sini, sesudah yang dicabut dibuang, jadi tidak
/// ada beranda yang perlu ingat menyaring sendiri — dan tidak ada yang
/// bisa lupa.
List<Widget> tileBerjarak(
  BuildContext context,
  List<Widget> tiles, {
  double jarak = 12,
}) {
  final tampak = tileTampak(context, tiles);
  return [
    for (var i = 0; i < tampak.length; i++) ...[
      if (i > 0) SizedBox(height: jarak),
      tampak[i],
    ],
  ];
}
