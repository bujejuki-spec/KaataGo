import 'package:supabase_flutter/supabase_flutter.dart';

/// Satu aturan pembukuan yang sedang dilanggar.
class TemuanPembukuan {
  final String aturan;
  final String keterangan;
  final int selisih;
  final String petunjuk;

  const TemuanPembukuan({
    required this.aturan,
    required this.keterangan,
    required this.selisih,
    required this.petunjuk,
  });

  factory TemuanPembukuan.fromMap(Map<String, dynamic> map) =>
      TemuanPembukuan(
        aturan: map['aturan']?.toString() ?? '',
        keterangan: map['keterangan']?.toString() ?? '',
        selisih: (map['selisih'] as num?)?.toInt() ?? 0,
        petunjuk: map['petunjuk']?.toString() ?? '',
      );
}

/// Pemeriksa konsistensi pembukuan.
///
/// Dijalankan di server, bukan di aplikasi: sebagian aturannya menyapu
/// seluruh riwayat pesanan dan jurnal, dan sebagian lagi membaca baris
/// yang memang tidak boleh terbaca perangkat siapa pun.
class PeriksaPembukuanRepository {
  final _client = Supabase.instance.client;

  /// Yang dilanggar saja. Daftar kosong berarti semuanya cocok.
  Future<List<TemuanPembukuan>> periksa(String restoId) async {
    final rows = await _client
        .rpc('periksa_pembukuan', params: {'p_resto_id': restoId});
    return [
      for (final r in (rows as List? ?? const []))
        TemuanPembukuan.fromMap(Map<String, dynamic>.from(r as Map)),
    ];
  }
}
