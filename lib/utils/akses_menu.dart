import 'package:flutter/widgets.dart';

import '../models/menu_access.dart';

/// Parameter akses yang berlaku untuk orang yang sedang memakai aplikasi.
///
/// Dipasang sekali di atas seluruh pohon widget, lalu dibaca di dua
/// tempat saja: daftar menu (menyembunyikan yang tidak diberikan) dan
/// [ModeAkses] (mematikan penyimpanan di menu yang cuma boleh dilihat).
///
/// Peta yang kosong berarti tidak ada pembatasan sama sekali — itu
/// keadaan setiap merchant yang belum pernah diatur KaataGo Admin, dan
/// juga keadaan saat pemuatannya gagal. Gagal memuat parameter tidak
/// boleh mengunci orang dari pekerjaannya.
class AksesMenu extends InheritedWidget {
  final Map<String, TingkatAkses> peta;

  const AksesMenu({
    super.key,
    required this.peta,
    required super.child,
  });

  static AksesMenu? of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AksesMenu>();

  TingkatAkses tingkat(String menu) => peta[menu] ?? TingkatAkses.ubah;

  bool bolehLihat(String menu) => tingkat(menu).bolehLihat;
  bool bolehUbah(String menu) => tingkat(menu).bolehUbah;

  @override
  bool updateShouldNotify(AksesMenu oldWidget) => oldWidget.peta != peta;
}

/// Menu ini boleh muncul untuk orang yang sedang masuk.
bool bolehLihatMenu(BuildContext context, String menu) =>
    AksesMenu.of(context)?.bolehLihat(menu) ?? true;

/// Menandai bahwa layar di bawahnya sedang dibuka dalam mode baca-saja.
///
/// Dipasang layarnya sendiri, dengan menyebut nama menunya. Menyimpulkan
/// nama itu dari kartu yang diketuk sempat dicoba dan dibuang: kartunya
/// mendorong rute baru ke Navigator, jadi pembungkusnya tidak ikut
/// terbawa — dan menyiasatinya dengan mengingat "menu terakhir yang
/// diketuk" di satu tempat global membuat layar yang dibuka lewat jalan
/// lain (notifikasi, tautan) mewarisi mode milik menu yang salah.
class ModeAkses extends InheritedWidget {
  final bool bolehUbah;

  const ModeAkses({
    super.key,
    required this.bolehUbah,
    required super.child,
  });

  static bool bolehUbahDiSini(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<ModeAkses>()
          ?.bolehUbah ??
      true;

  @override
  bool updateShouldNotify(ModeAkses oldWidget) => oldWidget.bolehUbah != bolehUbah;
}

/// Membungkus isi sebuah layar dengan mode akses menunya.
///
/// Dipakai di `build` layar yang bersangkutan:
///
/// ```dart
/// return berdasarkanAkses(context, 'Kelola Produk', Scaffold(...));
/// ```
///
/// Sesudah itu widget mana pun di bawahnya — termasuk dialog yang
/// dibuka dari sana — bisa bertanya lewat [ModeAkses.bolehUbahDiSini].
Widget berdasarkanAkses(BuildContext context, String menu, Widget isi) =>
    ModeAkses(
      bolehUbah: AksesMenu.of(context)?.bolehUbah(menu) ?? true,
      child: isi,
    );

/// Apakah layar ini sedang boleh diubah. Di luar layar bermode, selalu
/// true — tidak ada layar yang terkunci karena lupa dibungkus.
bool bolehUbahDiSini(BuildContext context) =>
    ModeAkses.bolehUbahDiSini(context);
