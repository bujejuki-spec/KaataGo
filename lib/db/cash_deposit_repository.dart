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
}
