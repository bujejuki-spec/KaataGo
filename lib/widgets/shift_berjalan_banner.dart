import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../services/notification_router.dart' show navigatorKey;
import '../providers/auth_provider.dart';
import '../screens/cashier_shift_screen.dart';
import '../utils/shift_berjalan.dart';

/// Penanda mengambang: shiftmu masih berjalan.
///
/// Dipasang di atas Navigator, jadi ia tetap terlihat di layar mana pun
/// — dan itu memang gunanya. Shift dibuka pagi di layar Shift Kasir,
/// lalu layar itu tidak dibuka lagi sampai tutup toko; penanda yang
/// hanya ada di sana berarti tidak ada yang mengingatkan.
///
/// Duduk di ATAS, bukan di bawah: bagian bawah layar sudah ditempati
/// tombol KaataGo Support, penanda unduhan, dan tombol mengambang tiap
/// layar. Yang bertumpuk di sana akan saling menutupi justru saat
/// keduanya penting.
class ShiftBerjalanBanner extends StatefulWidget {
  final Widget child;

  const ShiftBerjalanBanner({super.key, required this.child});

  @override
  State<ShiftBerjalanBanner> createState() => _ShiftBerjalanBannerState();
}

class _ShiftBerjalanBannerState extends State<ShiftBerjalanBanner> {
  static final _jam = DateFormat('HH:mm', 'id_ID');

  String? _restoTerakhir;

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

    return Stack(
      children: [
        widget.child,
        Positioned(
          left: 12,
          right: 12,
          top: 8,
          child: SafeArea(
            child: AnimatedBuilder(
              animation: ShiftBerjalan.instance,
              builder: (context, _) {
                final shift = ShiftBerjalan.instance;
                if (!shift.aktif) return const SizedBox.shrink();
                return _Pil(dibuka: shift.dibuka!, jam: _jam);
              },
            ),
          ),
        ),
      ],
    );
  }
}

class _Pil extends StatelessWidget {
  final DateTime dibuka;
  final DateFormat jam;

  const _Pil({required this.dibuka, required this.jam});

  @override
  Widget build(BuildContext context) {
    final lama = DateTime.now().difference(dibuka);
    final jamLama = lama.inHours;
    final menitLama = lama.inMinutes % 60;

    return Align(
      alignment: Alignment.topCenter,
      child: Material(
        // Sengaja bukan merah: merah berarti ada yang salah, dan shift
        // yang berjalan justru keadaan normal sepanjang jam buka. Yang
        // disampaikan cuma "ini masih menyala" — jadi amber tua,
        // sewarna kartu Shift Kasir di beranda.
        color: const Color(0xFFB45309),
        borderRadius: BorderRadius.circular(24),
        elevation: 6,
        child: InkWell(
          borderRadius: BorderRadius.circular(24),
          // Diketuk membuka layar Shift Kasir, bukan langsung menutup
          // shiftnya. Menutup shift berarti menghitung uang laci lebih
          // dulu — tombol yang menutupnya sekali ketuk akan melahirkan
          // selisih yang tidak pernah dihitung siapa pun.
          onTap: () {
            final nav = navigatorKey.currentState;
            if (nav == null) return;
            nav.push(MaterialPageRoute(
                builder: (_) => const CashierShiftScreen()));
          },
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 9, 10, 9),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.point_of_sale, color: Colors.white, size: 17),
                const SizedBox(width: 9),
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
                Text('· dibuka ${jam.format(dibuka.toLocal())}',
                    style: TextStyle(
                        color: Colors.white.withOpacity(0.82), fontSize: 12)),
                const SizedBox(width: 10),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.18),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Text('Akhiri',
                      style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 12.5)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
