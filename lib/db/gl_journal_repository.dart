import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/gl_journal_entry.dart';

class GlJournalRepository {
  final _client = Supabase.instance.client;

  Future<List<GlJournalEntry>> getForResto(String restoId) async {
    final rows = await _client
        .from('gl_journal_entries')
        .select()
        .eq('resto_id', restoId)
        .order('created_at', ascending: false);
    return rows.map((r) => GlJournalEntry.fromMap(r)).toList();
  }
}
