import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/cash_deposit.dart';

class CashDepositRepository {
  final _client = Supabase.instance.client;

  Future<List<CashDeposit>> getForResto(String restoId) async {
    final rows = await _client
        .from('cash_deposits')
        .select()
        .eq('resto_id', restoId)
        .order('created_at', ascending: false);
    return rows.map((r) => CashDeposit.fromMap(r)).toList();
  }

  Future<void> create(CashDeposit deposit) async {
    await _client.from('cash_deposits').insert(deposit.toMap());
  }

  Future<void> delete(String id) async {
    await _client.from('cash_deposits').delete().eq('id', id);
  }

  /// Menyetujui atau menolak satu setoran.
  ///
  /// Hanya baris ini yang disentuh, dan trigger jurnalnya pun bekerja per
  /// baris — jadi menyetujui satu setoran tidak akan ikut memindahkan
  /// setoran lain yang masih menunggu.
  Future<void> review(
    String id, {
    required DepositStatus status,
    required String reviewedBy,
    String? note,
  }) async {
    await _client.from('cash_deposits').update({
      'status': status.dbValue,
      'reviewed_by': reviewedBy,
      'reviewed_at': DateTime.now().toUtc().toIso8601String(),
      if (note != null && note.trim().isNotEmpty) 'review_note': note.trim(),
    }).eq('id', id);
  }
}
