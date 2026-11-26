import 'package:flutter/material.dart';

import '../theme.dart';
import '../utils/gambar_base64.dart';
import 'gambar_bertanda.dart';

/// Satu gambar tersimpan, dalam bentuk apa pun ia tersimpan.
///
/// Dibawa sebagai satu nilai supaya tidak ada rantai pemanggilan yang
/// harus membawa dua parameter kembar — dan tidak ada tempat yang
/// kebetulan membawa salah satunya saja.
typedef RefGambar = ({String? base64, String? jalurLama});

/// Gambar yang tersimpan di basis data sebagai base64 — dengan jalan
/// mundur ke Storage untuk baris lama.
///
/// ── Kenapa dua-duanya ────────────────────────────────────────────────
///
/// Gambar unggahan sekarang disimpan sebagai base64. Tapi baris yang
/// dibuat sebelum itu menunjuk ke berkas di Storage, dan baris itu tidak
/// hilang: bukti absensi bulan lalu, bukti transfer langganan tahun
/// lalu, foto menu yang tidak pernah diganti sejak dipasang.
///
/// Memaksa semuanya lewat satu jalan berarti separuh riwayat berubah
/// jadi kotak kosong pada hari perubahannya dirilis — dan yang
/// membukanya tidak punya cara tahu apakah gambarnya memang tidak ada
/// atau aplikasinya yang rusak.
///
/// Jadi yang ada dipakai: base64 lebih dulu, jalur lama sebagai
/// cadangan.
class GambarTersimpan extends StatelessWidget {
  /// Isi base64-nya, kalau barisnya sudah memakai cara baru.
  final String? base64;

  /// Jalur atau URL lama di Storage, untuk baris yang belum.
  final String? jalurLama;

  /// Ember tempat [jalurLama] disimpan.
  final String ember;

  final BoxFit fit;
  final String kosong;

  /// Bentuk singkat dari sepasang [base64] dan [jalurLama].
  static GambarTersimpan dariRef(
    RefGambar? ref, {
    String ember = emberTertutup,
    BoxFit fit = BoxFit.cover,
    String kosong = 'Belum ada',
  }) =>
      GambarTersimpan(
        base64: ref?.base64,
        jalurLama: ref?.jalurLama,
        ember: ember,
        fit: fit,
        kosong: kosong,
      );

  const GambarTersimpan({
    super.key,
    this.base64,
    this.jalurLama,
    this.ember = emberTertutup,
    this.fit = BoxFit.cover,
    this.kosong = 'Belum ada',
  });

  @override
  Widget build(BuildContext context) {
    final b = base64?.trim();
    if (b != null && b.isNotEmpty) {
      // Byte-nya diingat, bukan didekode ulang tiap gambar.
      //
      // `base64Decode` mengembalikan Uint8List baru tiap kali, dan
      // MemoryImage memakai identitas byte itu sebagai kunci cache —
      // byte baru berarti Flutter mendekode ulang dari nol, dan selama
      // sekejap itu tempatnya kosong. Di layar yang dibangun ulang tiap
      // ketukan, hasilnya seluruh gambar berkedip bersamaan.
      return Image.memory(
        byteGambar(b),
        fit: fit,
        errorBuilder: (_, __, ___) => _kotak(context, 'Gagal dimuat'),
      );
    }

    final lama = jalurLama?.trim();
    if (lama != null && lama.isNotEmpty) {
      return GambarBertanda(
        simpanan: lama,
        ember: ember,
        fit: fit,
        kosong: kosong,
      );
    }

    return _kotak(context, kosong);
  }

  Widget _kotak(BuildContext context, String teks) => Container(
        color: KaataTheme.softFillOf(context),
        alignment: Alignment.center,
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Text(
            teks,
            textAlign: TextAlign.center,
            style: TextStyle(
                fontSize: 11.5, color: KaataTheme.mutedOf(context)),
          ),
        ),
      );
}
