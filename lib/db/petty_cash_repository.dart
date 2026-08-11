import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/petty_cash_entry.dart';

class PettyCashRepository {
  final _client = Supabase.instance.client;

  Future<List<PettyCashEntry>> getForResto(String restoId) async {
    final rows = await _client
        .from('petty_cash_entries')
        .select()
        .eq('resto_id', restoId)
        .order('created_at', ascending: false);
    return rows.map((r) => PettyCashEntry.fromMap(r)).toList();
  }

  Future<void> create(PettyCashEntry entry) async {
    await _client.from('petty_cash_entries').insert(entry.toMap());
  }

  Future<void> delete(String id) async {
    await _client.from('petty_cash_entries').delete().eq('id', id);
  }
}
