import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/cashier_shift.dart';

class CashierShiftRepository {
  final _client = Supabase.instance.client;

  /// Shift yang masih terbuka di merchant ini, kalau ada.
  ///
  /// Paling banyak satu — basis datanya menjamin itu lewat unique index,
  /// bukan lewat kesepakatan antar layar.
  Future<CashierShift?> terbuka(String restoId) async {
    final rows = await _client
        .from('cashier_shifts')
        .select()
        .eq('resto_id', restoId)
        .isFilter('closed_at', null)
        .limit(1);
    return rows.isEmpty ? null : CashierShift.fromMap(rows.first);
  }

  /// Riwayat shift, yang terbaru lebih dulu.
  Future<List<CashierShift>> riwayat(String restoId, {int batas = 60}) async {
    final rows = await _client
        .from('cashier_shifts')
        .select()
        .eq('resto_id', restoId)
        .not('closed_at', 'is', null)
        .order('opened_at', ascending: false)
        .limit(batas);
    return rows.map((r) => CashierShift.fromMap(r)).toList();
  }

  Future<CashierShift> buka({
    required String restoId,
    required int modalAwal,
  }) async {
    final row = await _client.rpc('open_shift', params: {
      'p_resto_id': restoId,
      'p_opening_cash': modalAwal,
    });
    return CashierShift.fromMap(Map<String, dynamic>.from(row as Map));
  }

  /// Berapa yang seharusnya ada di laci saat ini.
  ///
  /// Hanya untuk ditunjukkan sebagai perkiraan sesudah kasir menuliskan
  /// hitungannya — supaya salah ketik nominal bisa diperbaiki sebelum
  /// shiftnya benar-benar ditutup.
  ///
  /// Angka ini TIDAK dipakai menyimpan apa pun. Saat ditutup, server
  /// menghitungnya lagi dari awal di dalam `close_shift`, dan itulah
  /// yang tersimpan — jadi perkiraan yang basi atau dipalsukan di
  /// perjalanan tidak bisa mengubah selisih yang tercatat.
  Future<int> perkiraan(String shiftId) async {
    final hasil =
        await _client.rpc('shift_expected_cash', params: {'p_shift_id': shiftId});
    return (hasil as num?)?.toInt() ?? 0;
  }

  /// Menutup shift dan mengembalikan hasilnya — termasuk selisihnya, yang
  /// baru dihitung server pada saat ini juga.
  Future<CashierShift> tutup({
    required String shiftId,
    required int uangDihitung,
    String? catatan,
  }) async {
    final row = await _client.rpc('close_shift', params: {
      'p_shift_id': shiftId,
      'p_counted_cash': uangDihitung,
      'p_note': catatan,
    });
    return CashierShift.fromMap(Map<String, dynamic>.from(row as Map));
  }
}
