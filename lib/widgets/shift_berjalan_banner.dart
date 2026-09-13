import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../services/notification_router.dart' show navigatorKey;
import '../providers/auth_provider.dart';
import '../screens/cashier_shift_screen.dart';
import '../utils/shift_berjalan.dart';

/// Penanda mengambang soal shift: yang sedang berjalan, atau yang belum
/// dibuka.
///
/// Dipasang di atas Navigator, jadi ia tetap terlihat di layar mana pun
/// — dan itu memang gunanya. Shift dibuka pagi di layar Shift Kasir,
/// lalu layar itu tidak dibuka lagi sampai tutup toko; penanda yang
/// hanya ada di sana berarti tidak ada yang mengingatkan.
///
/// Keduanya satu pil yang sama, bukan dua: pada satu saat cuma satu yang
/// benar, dan tempatnya di layar memang tempat yang sama.
class ShiftBerjalanBanner extends StatefulWidget {
  final Widget child;

  const ShiftBerjalanBanner({super.key, required this.child});

  @override
  State<ShiftBerjalanBanner> createState() => _ShiftBerjalanBannerState();
}

class _ShiftBerjalanBannerState extends State<ShiftBerjalanBanner> {
  static final _jam = DateFormat('HH:mm', 'id_ID');

  String? _restoTerakhir;

  void _bukaLayarShift() {
    final nav = navigatorKey.currentState;
    if (nav == null) return;
    nav.push(MaterialPageRoute(builder: (_) => const CashierShiftScreen()));
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();

    // Ditanyakan saat orangnya berganti atau restonya berpindah, bukan
    // berkala. Penanda ini tidak perlu tepat sampai ke detik; yang
    // dijaga cuma supaya ia tidak ketinggalan satu hari penuh.
    final kunci = '${auth.user?.email}|${auth.restoId}';
    if (kunci != _restoTerakhir) {
      _restoTerakhir = kunci;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ShiftBerjalan.instance.segarkan(auth.restoId, auth.user?.email);
      });
    }

    final kasir = auth.isKasir;

    return Stack(
      children: [
        widget.child,
        _Mengambang(
          child: AnimatedBuilder(
            animation: ShiftBerjalan.instance,
            builder: (context, _) {
              final shift = ShiftBerjalan.instance;
              if (shift.aktif) {
                return _PilBerjalan(
                  dibuka: shift.dibuka!,
                  jam: _jam,
                  onTap: _bukaLayarShift,
                );
              }
              // Hanya kasir yang berandanya menunggu shift. Peran lain
              // memang bekerja tanpa membuka shift, dan pil yang
              // menyuruh mereka membukanya cuma menyuruh yang salah.
              if (kasir && shift.diketahui) {
                return _PilMenunggu(onTap: _bukaLayarShift);
              }
              return const SizedBox.shrink();
            },
          ),
        ),
      ],
    );
  }
}

/// Pembungkus yang menaruh pilnya di bawah dan membiarkannya digeser.
///
/// Bawah, bukan atas: yang di atas menutupi judul layar dan tombol
/// kembali — dua hal yang dipakai terus-menerus. Yang di bawah memang
/// bisa bertabrakan dengan tombol mengambang tiap layar, dan justru
/// itulah sebabnya pilnya bisa dipindahkan: yang tahu mana yang sedang
/// terhalang cuma orang yang sedang memakainya.
///
/// Letaknya disimpan selama aplikasi berjalan saja, tidak disimpan ke
/// penyimpanan. Letak yang diingat lintas pemakaian berarti pil yang
/// suatu hari muncul di tempat yang tidak dipahami lagi asalnya.
class _Mengambang extends StatefulWidget {
  final Widget child;

  const _Mengambang({required this.child});

  @override
  State<_Mengambang> createState() => _MengambangState();
}

class _MengambangState extends State<_Mengambang> {
  static const _tepi = 12.0;

  final _kunciPil = GlobalKey();

  /// Kiri-atas pilnya di dalam Stack, atau null selama belum digeser —
  /// selama itu ia mengikuti tempat bawaannya di bawah tengah.
  Offset? _letak;
  Size? _ukuran;

  void _mulai() {
    final pil = _kunciPil.currentContext?.findRenderObject() as RenderBox?;
    final wadah = context.findRenderObject() as RenderBox?;
    if (pil == null || wadah == null) return;
    _ukuran = pil.size;
    // Digeser dari tempatnya yang sekarang, bukan melompat ke jari.
    _letak ??= wadah.globalToLocal(pil.localToGlobal(Offset.zero));
  }

  void _geser(DragUpdateDetails d, BoxConstraints batas) {
    final ukuran = _ukuran;
    if (_letak == null || ukuran == null) return;
    final calon = _letak! + d.delta;
    setState(() {
      _letak = Offset(
        calon.dx.clamp(_tepi, (batas.maxWidth - ukuran.width - _tepi)
            .clamp(_tepi, double.infinity)),
        calon.dy.clamp(_tepi, (batas.maxHeight - ukuran.height - _tepi)
            .clamp(_tepi, double.infinity)),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, batas) {
        // Lebarnya tetap dibatasi meski sudah digeser: Positioned yang
        // cuma menyebut kiri dan atas memberi ruang tak terbatas, dan
        // teks yang seharusnya dipendekkan malah melimpah keluar layar.
        final pil = ConstrainedBox(
          constraints: BoxConstraints(maxWidth: batas.maxWidth - _tepi * 2),
          child: GestureDetector(
            onPanStart: (_) => _mulai(),
            onPanUpdate: (d) => _geser(d, batas),
            child: KeyedSubtree(key: _kunciPil, child: widget.child),
          ),
        );
        if (_letak == null) {
          return Positioned(
            left: _tepi,
            right: _tepi,
            bottom: _tepi,
            child: SafeArea(
              top: false,
              child: Align(alignment: Alignment.bottomCenter, child: pil),
            ),
          );
        }
        return Positioned(left: _letak!.dx, top: _letak!.dy, child: pil);
      },
    );
  }
}

/// Bentuk pilnya. Satu badan untuk dua keadaan, supaya yang berpindah di
/// mata orang cuma isinya — bukan benda yang hilang lalu diganti benda
/// lain di tempat lain.
class _Badan extends StatelessWidget {
  final Color warna;
  final IconData ikon;
  final List<Widget> isi;
  final String aksi;
  final VoidCallback onTap;

  const _Badan({
    required this.warna,
    required this.ikon,
    required this.isi,
    required this.aksi,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: warna,
      borderRadius: BorderRadius.circular(24),
      elevation: 6,
      child: InkWell(
        borderRadius: BorderRadius.circular(24),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 9, 10, 9),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(ikon, color: Colors.white, size: 17),
              const SizedBox(width: 9),
              ...isi,
              const SizedBox(width: 10),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.18),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(aksi,
                    style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 12.5)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Kasir yang berandanya masih menunggu.
///
/// Tanpa ini, kasir yang menu-menunya belum muncul mengira aplikasinya
/// belum selesai memuat — lalu menunggu sesuatu yang tidak akan datang
/// sampai dia membuka shift.
class _PilMenunggu extends StatelessWidget {
  final VoidCallback onTap;

  const _PilMenunggu({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return _Badan(
      warna: const Color(0xFF475569),
      ikon: Icons.lock_clock,
      aksi: 'Buka',
      onTap: onTap,
      isi: const [
        Flexible(
          child: Text(
            'Buka shift dulu',
            style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w600,
                fontSize: 13),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

class _PilBerjalan extends StatefulWidget {
  final DateTime dibuka;
  final DateFormat jam;
  final VoidCallback onTap;

  const _PilBerjalan(
      {required this.dibuka, required this.jam, required this.onTap});

  @override
  State<_PilBerjalan> createState() => _PilBerjalanState();
}

class _PilBerjalanState extends State<_PilBerjalan> {
  Timer? _detak;

  @override
  void initState() {
    super.initState();
    _jadwalkan();
  }

  @override
  void dispose() {
    _detak?.cancel();
    super.dispose();
  }

  /// Berdetak tiap menit, dan detak pertamanya disetel ke pergantian
  /// menit berikutnya.
  ///
  /// Timer satu menit yang dimulai sembarang waktu membuat angkanya
  /// tertinggal sampai 59 detik dari yang sebenarnya — dan penanda yang
  /// terlihat berhenti sebentar lalu melompat dua menit sekaligus
  /// terbaca seperti aplikasi yang macet.
  ///
  /// Timernya hidup hanya selama pilnya terpasang, yaitu hanya selama
  /// ada shift yang berjalan. Tidak ada yang berdetak saat tidak ada
  /// yang perlu dihitung.
  void _jadwalkan() {
    final lewat = DateTime.now().difference(widget.dibuka);
    final keMenitBerikutnya =
        const Duration(minutes: 1) - Duration(seconds: lewat.inSeconds % 60);
    _detak = Timer(keMenitBerikutnya, () {
      if (!mounted) return;
      setState(() {});
      _detak = Timer.periodic(const Duration(minutes: 1), (_) {
        if (mounted) setState(() {});
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final dibuka = widget.dibuka;
    final lama = DateTime.now().difference(dibuka);
    final jamLama = lama.inHours;
    final menitLama = lama.inMinutes % 60;

    return _Badan(
      // Sengaja bukan merah: merah berarti ada yang salah, dan shift
      // yang berjalan justru keadaan normal sepanjang jam buka. Yang
      // disampaikan cuma "ini masih menyala" — jadi amber tua, sewarna
      // kartu Shift Kasir di beranda.
      warna: const Color(0xFFB45309),
      ikon: Icons.point_of_sale,
      // Diketuk membuka layar Shift Kasir, bukan langsung menutup
      // shiftnya. Menutup shift berarti menghitung uang laci lebih
      // dulu — tombol yang menutupnya sekali ketuk akan melahirkan
      // selisih yang tidak pernah dihitung siapa pun.
      aksi: 'Akhiri',
      onTap: widget.onTap,
      isi: [
        Flexible(
          child: Text(
            jamLama > 0
                ? 'Shift berjalan ${jamLama}j ${menitLama}m'
                : 'Shift berjalan ${menitLama}m',
            style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w600,
                fontSize: 13),
            overflow: TextOverflow.ellipsis,
          ),
        ),
        const SizedBox(width: 6),
        Text('· dibuka ${widget.jam.format(dibuka.toLocal())}',
            style: TextStyle(
                color: Colors.white.withOpacity(0.82), fontSize: 12)),
      ],
    );
  }
}
