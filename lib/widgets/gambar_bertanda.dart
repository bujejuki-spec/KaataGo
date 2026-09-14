import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../theme.dart';

/// Ember penyimpanan yang isinya tidak boleh dibuka umum.
const emberTertutup = 'absensi';

/// Mengubah apa yang tersimpan di basis data jadi URL yang benar-benar
/// bisa dibuka.
///
/// ── Kenapa tidak bisa pakai URL publik ───────────────────────────────
///
/// Ember `absensi` sengaja TIDAK publik: isinya foto wajah karyawan dan
/// surat keterangan sakit, dan keduanya tidak boleh bisa dibuka siapa
/// pun yang kebetulan menebak alamatnya.
///
/// `getPublicUrl()` tetap mengembalikan alamat untuk ember tertutup —
/// alamat yang selalu ditolak. Tidak ada galat saat menyimpannya, dan
/// yang terlihat baru berbulan-bulan kemudian sebagai kotak "Gagal
/// dimuat" di layar orang yang sedang memutuskan gaji.
///
/// Jadi yang dipakai URL bertanda tangan, dibuat saat gambarnya mau
/// ditampilkan dan berumur pendek.
///
/// ── Menerima dua bentuk ──────────────────────────────────────────────
///
/// Baris lama terlanjur menyimpan URL publik yang tidak pernah bisa
/// dibuka. Jalur berkasnya masih ada di dalam alamat itu, jadi ia
/// dipungut kembali alih-alih dibiarkan jadi baris yang rusak selamanya.
Future<String?> urlBertanda(String? simpanan, {String ember = emberTertutup}) async {
  final nilai = simpanan?.trim() ?? '';
  if (nilai.isEmpty) return null;

  var jalur = nilai;
  // Bentuk lama: .../storage/v1/object/public/absensi/<jalur>
  for (final penanda in ['/object/public/$ember/', '/object/sign/$ember/',
    '/object/$ember/']) {
    final i = nilai.indexOf(penanda);
    if (i >= 0) {
      jalur = nilai.substring(i + penanda.length);
      break;
    }
  }
  // Sisa tanda tanya dari URL bertanda tangan yang lama.
  final tanya = jalur.indexOf('?');
  if (tanya >= 0) jalur = jalur.substring(0, tanya);
  if (jalur.isEmpty) return null;

  try {
    // Satu jam. Cukup lama untuk memeriksa sebulan absensi dalam satu
    // duduk, cukup pendek untuk tidak jadi alamat yang beredar.
    return await Supabase.instance.client.storage
        .from(ember)
        .createSignedUrl(jalur, 3600);
  } catch (_) {
    return null;
  }
}

/// Gambar dari ember tertutup, lengkap dengan penandanya.
///
/// Tandanya dibuat saat gambarnya benar-benar mau ditampilkan, bukan
/// disimpan di basis data: tanda yang tersimpan akan kedaluwarsa, dan
/// baris yang menyimpannya berubah jadi kotak kosong tanpa ada yang
/// mengubah apa pun.
class GambarBertanda extends StatefulWidget {
  /// Apa yang tersimpan di basis data — jalur berkas atau URL lama.
  final String? simpanan;

  final BoxFit fit;
  final String kosong;

  const GambarBertanda({
    super.key,
    required this.simpanan,
    this.fit = BoxFit.cover,
    this.kosong = 'Belum ada',
  });

  @override
  State<GambarBertanda> createState() => _GambarBertandaState();
}

class _GambarBertandaState extends State<GambarBertanda> {
  late Future<String?> _url;

  @override
  void initState() {
    super.initState();
    _url = urlBertanda(widget.simpanan);
  }

  @override
  void didUpdateWidget(GambarBertanda lama) {
    super.didUpdateWidget(lama);
    if (lama.simpanan != widget.simpanan) {
      _url = urlBertanda(widget.simpanan);
    }
  }

  @override
  Widget build(BuildContext context) {
    final muted = KaataTheme.mutedOf(context);

    Widget kotak(String teks) => Container(
          color: KaataTheme.softFillOf(context),
          alignment: Alignment.center,
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Text(teks,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 11.5, color: muted)),
          ),
        );

    if (widget.simpanan == null || widget.simpanan!.trim().isEmpty) {
      return kotak(widget.kosong);
    }

    return FutureBuilder<String?>(
      future: _url,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Container(
            color: KaataTheme.softFillOf(context),
            alignment: Alignment.center,
            child: const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          );
        }
        final url = snapshot.data;
        if (url == null) return kotak('Gagal dimuat');
        return Image.network(
          url,
          fit: widget.fit,
          errorBuilder: (_, __, ___) => kotak('Gagal dimuat'),
        );
      },
    );
  }
}
