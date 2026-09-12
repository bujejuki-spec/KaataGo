import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/cash_variance.dart';
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

  /// Ada tidaknya shift yang sedang berjalan, tanpa menyebut siapa.
  ///
  /// Kasir tidak lagi bisa membaca baris shift orang lain, jadi
  /// [terbuka] mengembalikan null untuknya sekalipun lacinya sedang
  /// dipegang. Tanpa jawaban ini, tombol Buka Shift terpajang, ditekan,
  /// lalu ditolak server — dan penolakan yang muncul setelah tombol
  /// ditekan terbaca sebagai aplikasi yang rusak.
  Future<({bool ada, bool milikSaya})> ringkasTerbuka(String restoId) async {
    final rows = await _client
        .rpc('shift_terbuka_ringkas', params: {'p_resto_id': restoId});
    final list = (rows as List?) ?? const [];
    if (list.isEmpty) return (ada: false, milikSaya: false);
    final r = Map<String, dynamic>.from(list.first as Map);
    return (
      ada: r['ada'] as bool? ?? false,
      milikSaya: r['milik_saya'] as bool? ?? false,
    );
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

  /// Tagihan selisih kasir di merchant ini, yang terbuka lebih dulu.
  Future<List<CashVariance>> selisih(String restoId, {int batas = 60}) async {
    final rows = await _client
        .from('cash_variances')
        .select()
        .eq('resto_id', restoId)
        .order('status')
        .order('created_at', ascending: false)
        .limit(batas);
    return rows.map((r) => CashVariance.fromMap(r)).toList();
  }

  /// Mencatat kasir sudah menyerahkan uang tunai sebesar kekurangannya.
  ///
  /// Siapa yang boleh ditegakkan server: kasir melihat tagihannya, tapi
  /// tidak menutup tagihan atas namanya sendiri.
  Future<CashVariance> bayarSelisih({
    required String id,
    String cara = 'cash',
    String? catatan,
  }) async {
    final row = await _client.rpc('settle_cash_variance', params: {
      'p_id': id,
      'p_note': catatan,
      'p_method': cara,
    });
    return CashVariance.fromMap(Map<String, dynamic>.from(row as Map));
  }

  /// Menutup selisih lebih setelah ditelusuri.
  ///
  /// [cara] hanya `input_penjualan` atau `pendapatan`. Keduanya sama-
  /// sama melepas titipannya di GL Selisih Kasir; yang kedua sekaligus
  /// mengakuinya sebagai pendapatan lain-lain.
  ///
  /// Siapa yang boleh ditegakkan server, dan di sini lebih sempit
  /// daripada pelunasan selisih kurang: hanya Owner dan Finance.
  /// Memutuskan uang tak dikenal menjadi pendapatan adalah keputusan
  /// pembukuan, bukan keputusan operasional.
  Future<CashVariance> selesaikanSelisihLebih({
    required String id,
    required String cara,
    String? catatan,
  }) async {
    final row = await _client.rpc('resolve_cash_overage', params: {
      'p_id': id,
      'p_cara': cara,
      'p_note': catatan,
    });
    return CashVariance.fromMap(Map<String, dynamic>.from(row as Map));
  }

  /// Berapa yang seharusnya ada di laci sekarang, menurut pembukuan.
  ///
  /// Angka yang sama persis dengan Saldo Cash di layar Saldo &
  /// Pengeluaran — dan itu inti perubahannya. Dulu buka dan tutup shift
  /// memakai perkiraan yang dimulai dari `opening_cash` KETIKAN kasir,
  /// jadi satu angka salah ketik jadi dasar perhitungan seluruh shift
  /// sesudahnya dan pembukuan tidak pernah bisa mengoreksinya.
  ///
  /// Dihitung server, bukan dikirim aplikasi: angka yang menilai
  /// seseorang tidak boleh berasal dari perangkat orang itu.
  Future<int> saldoCashLaci(String restoId) async {
    final hasil =
        await _client.rpc('saldo_cash_laci', params: {'p_resto_id': restoId});
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
