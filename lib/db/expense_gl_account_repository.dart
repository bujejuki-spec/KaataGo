import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/expense_gl_account.dart';

class ExpenseGlAccountRepository {
  final _client = Supabase.instance.client;

  Future<List<ExpenseGlAccount>> getForResto(String restoId) async {
    final rows = await _client
        .from('expense_gl_accounts')
        .select()
        .eq('resto_id', restoId)
        .order('gl_code');
    return rows.map((r) => ExpenseGlAccount.fromMap(r)).toList();
  }

  Future<void> create(String restoId, String glCode, String glName) async {
    await _client.from('expense_gl_accounts').insert({
      'resto_id': restoId,
      'gl_code': glCode,
      'gl_name': glName,
    });
  }

  Future<void> delete(String id) async {
    await _client.from('expense_gl_accounts').delete().eq('id', id);
  }
}
