import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/voucher_payout.dart';

/// Pembayaran KaataGo ke merchant atas voucher yang ditebus di sana.
class VoucherPayoutRepository {
  final _client = Supabase.instance.client;

  /// Yang jadi hak resto ini, terbaru lebih dulu.
  ///
  /// Disaring periodenya di server. Merchant yang sudah lama berjalan
  /// bisa punya ratusan baris, dan yang dicari orang hampir selalu satu
  /// bulan terakhir.
  Future<List<VoucherPayout>> untukResto(
    String restoId, {
    DateTime? mulai,
    DateTime? akhir,
  }) async {
    var q =
        _client.from('voucher_payouts').select().eq('resto_id', restoId);
    if (mulai != null) q = q.gte('created_at', mulai.toUtc().toIso8601String());
    if (akhir != null) q = q.lte('created_at', akhir.toUtc().toIso8601String());
    final rows = await q.order('created_at', ascending: false);
    return rows.map((r) => VoucherPayout.fromMap(r)).toList();
  }
}
