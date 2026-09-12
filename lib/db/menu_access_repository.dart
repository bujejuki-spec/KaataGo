import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/menu_access.dart';

class MenuAccessRepository {
  final _client = Supabase.instance.client;

  /// Seluruh parameter sebuah resto, untuk layar pengaturannya.
  Future<List<MenuAccess>> untukResto(String restoId) async {
    final rows = await _client
        .from('menu_access')
        .select()
        .eq('resto_id', restoId);
    return rows.map((r) => MenuAccess.fromMap(r)).toList();
  }

  /// Parameter satu peran di satu resto, sebagai peta menu → tingkat.
  ///
  /// Inilah yang dibaca aplikasi tiap kali seseorang masuk. Yang tidak
  /// ada di peta berarti penuh — jadi merchant yang belum pernah diatur
  /// tidak kehilangan apa pun.
  Future<Map<String, TingkatAkses>> untukPeran(
      String restoId, String role) async {
    final rows = await _client
        .from('menu_access')
        .select()
        .eq('resto_id', restoId)
        .eq('role', role);
    return {
      for (final r in rows)
        r['menu_key'].toString(): TingkatAkses.dari(r['level'] as String?),
    };
  }

  /// Menyimpan satu parameter.
  ///
  /// Tingkat penuh menghapus barisnya, bukan menyimpan 'edit'. Peta yang
  /// isinya hanya pembatasan bisa dibaca sebagai daftar: apa saja yang
  /// dipersempit di merchant ini, dan tidak ada yang lain.
  Future<void> simpan(MenuAccess akses, {String? oleh}) async {
    if (akses.tingkat == TingkatAkses.ubah) {
      await _client
          .from('menu_access')
          .delete()
          .eq('resto_id', akses.restoId)
          .eq('role', akses.role)
          .eq('menu_key', akses.menuKey);
      return;
    }
    await _client.from('menu_access').upsert({
      ...akses.toMap(),
      if (oleh != null) 'updated_by': oleh,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    });
  }
}
