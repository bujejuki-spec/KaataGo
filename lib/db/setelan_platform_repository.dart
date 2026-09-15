import 'package:supabase_flutter/supabase_flutter.dart';

/// Setelan milik KaataGo sendiri, bukan milik merchant mana pun.
///
/// Dibaca siapa pun — termasuk sebelum login — dan hanya bisa diubah
/// KaataGo Admin. Penjaganya ada di basis data, bukan di sini.
class SetelanPlatformRepository {
  final _client = Supabase.instance.client;

  /// Tautan situs yang dipakai kalau basis data belum bisa dibaca.
  ///
  /// Tidak pernah jadi kosong. Layar Tentang KaataGo dibuka dari halaman
  /// login, sering tanpa sinyal yang bagus — dan tombol "Situs KaataGo"
  /// yang tidak bisa ditekan karena gagal memuat alamatnya lebih buruk
  /// daripada membuka alamat yang barangkali sudah sedikit tua.
  static const tautanSitusBawaan =
      'https://bujejuki-spec.github.io/KaataGo-LandingPage/';

  static const _kunciTautanSitus = 'tautan_situs';

  /// Jawaban terakhir, supaya membuka layar Tentang berkali-kali tidak
  /// berarti bertanya ke server berkali-kali untuk hal yang jarang sekali
  /// berubah.
  static String? _ingatan;

  Future<String> tautanSitus() async {
    final ingat = _ingatan;
    if (ingat != null) return ingat;
    try {
      final baris = await _client
          .from('setelan_platform')
          .select('nilai')
          .eq('kunci', _kunciTautanSitus)
          .maybeSingle();
      final nilai = baris?['nilai']?.toString().trim();
      if (nilai != null && tautanSah(nilai)) {
        return _ingatan = nilai;
      }
    } catch (_) {
      // Jatuh ke bawaan — lihat catatan di tautanSitusBawaan.
    }
    return tautanSitusBawaan;
  }

  Future<void> simpanTautanSitus(String tautan, {String? oleh}) async {
    final bersih = tautan.trim();
    if (!tautanSah(bersih)) {
      throw const FormatException(
          'Tautannya harus diawali https:// dan tidak boleh berisi spasi.');
    }
    await _client.from('setelan_platform').upsert({
      'kunci': _kunciTautanSitus,
      'nilai': bersih,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
      'updated_by': oleh,
    });
    _ingatan = bersih;
  }

  /// Sama dengan pemeriksaan di basis data: https, tanpa spasi.
  ///
  /// Diperiksa di dua tempat bukan karena yang satu tidak dipercaya,
  /// melainkan karena keduanya menjawab orang yang berbeda. Basis data
  /// menolak yang lolos; layar ini memberi tahu SEBELUM menyimpan,
  /// dengan kalimat yang bisa dibaca.
  static bool tautanSah(String tautan) {
    final uri = Uri.tryParse(tautan);
    return uri != null &&
        uri.scheme == 'https' &&
        uri.host.isNotEmpty &&
        !tautan.contains(RegExp(r'\s'));
  }
}
