import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../services/notification_router.dart' show navigatorKey;
import '../providers/auth_provider.dart';
import '../screens/cashier_shift_screen.dart';
import '../utils/shift_berjalan.dart';
import 'penanda_mengambang.dart';

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
        PenandaMengambang(
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
