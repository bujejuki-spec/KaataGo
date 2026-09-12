import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/settlement.dart';

/// Tutup buku harian dan rekonsiliasi mutasi rekening.
class SettlementRepository {
  final _client = Supabase.instance.client;

  // ── Tutup buku ──────────────────────────────────────────────────────

  Future<List<DailySettlement>> riwayat(String restoId, {int batas = 60}) async {
    final rows = await _client
        .from('daily_settlements')
        .select()
        .eq('resto_id', restoId)
        .order('settled_on', ascending: false)
        .limit(batas);
    return rows.map((r) => DailySettlement.fromMap(r)).toList();
  }

  /// Angka sebuah hari, dihitung dari sumbernya.
  ///
  /// Dipakai untuk hari yang BELUM ditutup: inilah angkanya sekarang,
  /// dan ia masih akan berubah kalau ada koreksi. Hari yang sudah
  /// ditutup memakai angka beku di barisnya — selisih antara keduanya
  /// justru yang ingin dilihat orang.
  Future<DailySettlement> hitung(String restoId, DateTime tanggal) async {
    final tgl = tanggal.toIso8601String().substring(0, 10);
    final angka = await _client
        .rpc('hitung_hari', params: {'p_resto_id': restoId, 'p_tanggal': tgl});
    final cocok = await _client.rpc('hitung_tercocok',
        params: {'p_resto_id': restoId, 'p_tanggal': tgl});

    final a = (angka as List).isEmpty
        ? <String, dynamic>{}
        : Map<String, dynamic>.from(angka.first as Map);
    final c = (cocok as List).isEmpty
        ? <String, dynamic>{}
        : Map<String, dynamic>.from(cocok.first as Map);

    return DailySettlement.fromMap({
      'id': '',
      'resto_id': restoId,
      'settled_on': tgl,
      ...a,
      ...c,
      'status': 'open',
    });
  }

  Future<DailySettlement> tutup(String restoId, DateTime tanggal,
      {String? catatan}) async {
    final row = await _client.rpc('tutup_hari', params: {
      'p_resto_id': restoId,
      'p_tanggal': tanggal.toIso8601String().substring(0, 10),
      'p_note': catatan,
    });
    return DailySettlement.fromMap(Map<String, dynamic>.from(row as Map));
  }

  Future<void> buka(String restoId, DateTime tanggal) async {
    await _client.rpc('buka_hari', params: {
      'p_resto_id': restoId,
      'p_tanggal': tanggal.toIso8601String().substring(0, 10),
    });
  }

  // ── Mutasi rekening ─────────────────────────────────────────────────

  Future<List<BankMutation>> mutasi(String bankAccountId,
      {int batas = 120}) async {
    final rows = await _client
        .from('bank_mutations')
        .select()
        .eq('bank_account_id', bankAccountId)
        .order('mutated_on', ascending: false)
        .limit(batas);
    return rows.map((r) => BankMutation.fromMap(r)).toList();
  }

  Future<void> tambahMutasi(BankMutation m) async {
    await _client.from('bank_mutations').insert(m.toMap());
  }

  Future<void> hapusMutasi(String id) async {
    await _client.from('bank_mutations').delete().eq('id', id);
  }

  /// Menautkan sebuah mutasi ke hal yang menjelaskannya.
  ///
  /// `jenis` null melepas tautannya lagi — pencocokan yang keliru harus
  /// bisa dibatalkan, dan memaksa orang menghapus lalu memasukkan ulang
  /// mutasinya berarti nomor acuannya ikut hilang.
  Future<void> cocokkan(
    String mutasiId, {
    required String? jenis,
    String? sasaranId,
    String? oleh,
  }) async {
    await _client.from('bank_mutations').update({
      'matched_kind': jenis,
      'matched_id': jenis == null || jenis == 'other' ? null : sasaranId,
      'matched_by': jenis == null ? null : oleh,
      'matched_at': jenis == null ? null : DateTime.now().toIso8601String(),
    }).eq('id', mutasiId);
  }

  // ── Yang belum punya pasangan ───────────────────────────────────────

  Future<List<BelumCocok>> setoranBelumCocok(String restoId) async {
    final rows = await _client
        .rpc('setoran_belum_cocok', params: {'p_resto_id': restoId});
    return [
      for (final r in (rows as List))
        BelumCocok(
          id: r['id'].toString(),
          amount: (r['amount'] as num).toInt(),
          jenis: r['method']?.toString() ?? 'setor',
          waktu: DateTime.parse(r['created_at'].toString()).toUtc(),
          oleh: r['created_by'] as String?,
        ),
    ];
  }

  Future<List<BelumCocok>> pembayaranBelumCocok(String restoId) async {
    final rows = await _client
        .rpc('pembayaran_belum_cocok', params: {'p_resto_id': restoId});
    return [
      for (final r in (rows as List))
        BelumCocok(
          id: r['id'].toString(),
          amount: (r['total'] as num).toInt(),
          jenis: r['payment_method']?.toString() ?? 'transfer',
          waktu: DateTime.parse(r['created_at'].toString()).toUtc(),
        ),
    ];
  }
}
