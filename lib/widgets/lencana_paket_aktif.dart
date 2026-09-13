import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../db/paket_langganan_repository.dart';
import '../models/paket_langganan.dart';
import '../providers/auth_provider.dart';
import '../screens/pilih_paket_screen.dart';

/// Penanda paket yang sedang berjalan, di header beranda tiap peran.
///
/// Kuning untuk Basic, hijau untuk Premium.
///
/// Ada supaya merchant tahu paketnya tanpa membuka menu mana pun — dan
/// supaya yang menu-menunya tidak muncul punya jawaban langsung di
/// depan matanya: bukan aplikasinya rusak, paketnya memang Basic.
///
/// Tidak menampilkan apa pun untuk merchant di luar jalur paket. Yang
/// belum pernah disentuh KaataGo Admin berjalan seperti sebelumnya, dan
/// lencana "tanpa paket" di berandanya cuma pertanyaan baru yang tidak
/// bisa dia jawab sendiri.
class LencanaPaketAktif extends StatefulWidget {
  const LencanaPaketAktif({super.key});

  /// Jawaban terakhir per merchant.
  ///
  /// Header dibangun ulang tiap kali berandanya digambar, dan tanpa
  /// ingatan ini tiap gambar ulang berarti satu panggilan server untuk
  /// menanyakan hal yang tidak berubah berhari-hari.
  static final Map<String, KeadaanLangganan> _ingatan = {};

  /// Dilupakan setelah paketnya berubah, supaya lencananya ikut
  /// berganti tanpa menunggu aplikasinya dibuka ulang.
  static void lupakan([String? restoId]) {
    if (restoId == null) {
      _ingatan.clear();
    } else {
      _ingatan.remove(restoId);
    }
  }

  @override
  State<LencanaPaketAktif> createState() => _LencanaPaketAktifState();
}

class _LencanaPaketAktifState extends State<LencanaPaketAktif> {
  final _repo = PaketLanggananRepository();

  KeadaanLangganan? _keadaan;
  String? _restoTerakhir;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final restoId = context.read<AuthProvider>().restoId;
    if (restoId == null || restoId == _restoTerakhir) return;
    _restoTerakhir = restoId;

    final ingat = LencanaPaketAktif._ingatan[restoId];
    if (ingat != null) {
      _keadaan = ingat;
      return;
    }
    _muat(restoId);
  }

  Future<void> _muat(String restoId) async {
    try {
      final k = await _repo.keadaan(restoId);
      LencanaPaketAktif._ingatan[restoId] = k;
      if (mounted) setState(() => _keadaan = k);
    } catch (_) {
      // Lencana yang gagal dimuat cukup tidak muncul. Menampilkan
      // "gagal" di header beranda memberi orang masalah yang tidak bisa
      // dia perbaiki, tentang hal yang tidak menghalangi pekerjaannya.
    }
  }

  @override
  Widget build(BuildContext context) {
    final k = _keadaan;
    if (k == null || k.diluarJalurPaket) return const SizedBox.shrink();

    // Masih percobaan: yang ditunjukkan sisa harinya, bukan paketnya —
    // paketnya memang belum ada.
    if (k.dalamPercobaan) {
      return Padding(
        padding: const EdgeInsets.only(top: 10),
        child: _Pil(
          warna: const Color(0xFF6366F1),
          ikon: Icons.hourglass_bottom,
          teks: 'Percobaan · ${k.sisaHari ?? 0} hari lagi',
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const PilihPaketScreen()),
          ),
        ),
      );
    }

    final paket = k.paket;
    if (paket == null) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: _Pil(
        warna: warnaPaket(paket),
        ikon: paket == Paket.premium
            ? Icons.workspace_premium
            : Icons.star_outline,
        teks: 'Langganan ${paket.label}',
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const PilihPaketScreen()),
        ),
      ),
    );
  }
}

class _Pil extends StatelessWidget {
  final Color warna;
  final IconData ikon;
  final String teks;
  final VoidCallback onTap;

  const _Pil({
    required this.warna,
    required this.ikon,
    required this.teks,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: warna,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(ikon, size: 14, color: Colors.white),
              const SizedBox(width: 6),
              Text(teks,
                  style: const TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.bold,
                      color: Colors.white)),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────
// Lencana paket
// ─────────────────────────────────────────────────────────────────────

/// Kuning untuk Basic, hijau untuk Premium.
///
/// Warnanya ditetapkan di satu tempat, bukan diketik ulang di tiap
/// layar. Lencana yang warnanya berbeda-beda antar layar berhenti
/// berfungsi sebagai penanda — orang berhenti membacanya sebagai
/// keterangan dan mulai membacanya sebagai hiasan.
Color warnaPaket(Paket paket) => switch (paket) {
      Paket.basic => const Color(0xFFF59E0B),
      Paket.premium => const Color(0xFF10B981),
    };

/// Penanda paket yang sedang berjalan.
class LencanaPaket extends StatelessWidget {
  final Paket paket;
  final bool kecil;

  const LencanaPaket({super.key, required this.paket, this.kecil = false});

  @override
  Widget build(BuildContext context) {
    final warna = warnaPaket(paket);
    return Container(
      padding: EdgeInsets.symmetric(
          horizontal: kecil ? 8 : 10, vertical: kecil ? 3 : 5),
      decoration: BoxDecoration(
        color: warna,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            paket == Paket.premium
                ? Icons.workspace_premium
                : Icons.star_outline,
            size: kecil ? 12 : 14,
            color: Colors.white,
          ),
          SizedBox(width: kecil ? 4 : 5),
          Text(
            paket.label,
            style: TextStyle(
              fontSize: kecil ? 10.5 : 12,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
        ],
      ),
    );
  }
}
