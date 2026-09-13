import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/company_deposit.dart';

/// Saldo perusahaan: uang tunai yang dipegang, dan uang di rekening.
class CompanyBalanceRepository {
  final _client = Supabase.instance.client;

  /// Kedua saldonya, dihitung server dari pergerakan akun GL-nya.
  ///
  /// Bukan dijumlahkan ulang di sini dari tabel pesanan dan setoran.
  /// Perhitungan kedua yang berdiri sendiri akan berpisah dari jurnalnya
  /// pada perubahan berikutnya, dan yang terlihat adalah dua angka yang
  /// sama-sama mengaku menyebut uang perusahaan.
  Future<({int cash, int bank})> saldo(String restoId) async {
    final rows =
        await _client.rpc('saldo_perusahaan', params: {'p_resto_id': restoId});
    final list = (rows as List?) ?? const [];
    if (list.isEmpty) return (cash: 0, bank: 0);
    final r = Map<String, dynamic>.from(list.first as Map);
    return (
      cash: (r['cash'] as num?)?.toInt() ?? 0,
      bank: (r['bank'] as num?)?.toInt() ?? 0,
    );
  }

  Future<List<CompanyDeposit>> setoran(String restoId, {int batas = 60}) async {
    final rows = await _client
        .from('company_deposits')
        .select()
        .eq('resto_id', restoId)
        .order('created_at', ascending: false)
        .limit(batas);
    return rows.map((r) => CompanyDeposit.fromMap(r)).toList();
  }

  Future<void> setor(CompanyDeposit setoran) async {
    await _client.from('company_deposits').insert(setoran.toMap());
  }

  /// Menyatakan berapa isi kantong pada suatu tanggal, menurut kenyataan
  /// di luar aplikasi — mutasi bank, atau uang yang dihitung tangan.
  ///
  /// Server membandingkannya dengan yang tercatat sampai tanggal itu
  /// lalu menuliskan selisihnya sebagai penyesuaian. Mengembalikan
  /// selisih yang ditulis; nol berarti angkanya memang sudah cocok.
  Future<int> setelSaldoAwal({
    required String restoId,
    required String kantong,
    required int saldo,
    required DateTime tanggal,
    String? catatan,
  }) async {
    final hasil = await _client.rpc('setel_saldo_awal', params: {
      'p_resto_id': restoId,
      'p_kantong': kantong,
      'p_saldo': saldo,
      'p_tanggal': tanggal.toIso8601String().substring(0, 10),
      'p_note': catatan,
    });
    return (hasil as num?)?.toInt() ?? 0;
  }
}
