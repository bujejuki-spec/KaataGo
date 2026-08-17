import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/gl_journal_entry.dart';

class GlJournalRepository {
  final _client = Supabase.instance.client;

  /// Jurnal seluruh resto — hanya Super Admin yang bisa membacanya, dan
  /// hanya membaca: tidak ada kebijakan tulis untuk siapa pun.
  Future<List<GlJournalEntry>> getAll({int limit = 1000}) async {
    final rows = await _client
        .from('gl_journal_entries')
        .select()
        .order('entry_date', ascending: false)
        .order('entry_time', ascending: false)
        .limit(limit);
    return rows.map((r) => GlJournalEntry.fromMap(r)).toList();
  }

  Future<List<GlJournalEntry>> getForResto(String restoId) async {
    final rows = await _client
        .from('gl_journal_entries')
        .select()
        .eq('resto_id', restoId)
        .order('created_at', ascending: false);
    return rows.map((r) => GlJournalEntry.fromMap(r)).toList();
  }
}
