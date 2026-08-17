import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/voucher.dart';

class VoucherRepository {
  final _client = Supabase.instance.client;

  /// Seluruh voucher berikut jumlah pemakaiannya — untuk Super Admin.
  ///
  /// Pemakaiannya dihitung dari tabel pemakaian, bukan disimpan sebagai
  /// angka di baris vouchernya. Angka yang disimpan terpisah akan
  /// berpisah dari kenyataannya suatu hari, dan yang menemukannya adalah
  /// pelanggan yang ditolak padahal kuotanya masih ada.
  Future<List<Voucher>> all() async {
    final rows = await _client
        .from('vouchers')
        .select()
        .order('created_at', ascending: false);
    final pakai = await _client.from('voucher_redemptions').select('voucher_id');

    final hitung = <String, int>{};
    for (final r in pakai) {
      final id = r['voucher_id'] as String;
      hitung[id] = (hitung[id] ?? 0) + 1;
    }
    return [
      for (final r in rows)
        Voucher.fromMap(r, used: hitung[r['id'] as String] ?? 0),
    ];
  }

  /// Voucher yang sedang berlaku dan pantas ditawarkan ke pelanggan.
  ///
  /// Disaring di aplikasi, bukan lewat `where` tanggal di server:
  /// daftarnya pendek, dan aturan masa berlakunya sudah tertulis satu
  /// kali di [Voucher.isLive]. Menulis ulang aturan yang sama sebagai
  /// SQL berarti dua tempat yang harus selalu sepakat.
  Future<List<Voucher>> liveFor(String restoId) async {
    final rows = await _client.from('vouchers').select().eq('active', true);
    return [
      for (final r in rows)
        if (Voucher.fromMap(r).isLive() &&
            (Voucher.fromMap(r).berlakuDiSemuaResto ||
                Voucher.fromMap(r).restoIds.contains(restoId)))
          Voucher.fromMap(r),
    ];
  }

  /// Menanyakan berapa potongan sebuah kode untuk tagihan ini.
  ///
  /// Dihitung server, bukan aplikasi. Nominal potongan yang datang dari
  /// HP bisa diubah siapa pun yang ingin membayar seribu rupiah untuk
  /// tagihan seratus ribu — dan ini uang KaataGo sendiri yang keluar.
  Future<VoucherQuote> quote({
    required String code,
    required String restoId,
    required String customerLabel,
    required int total,
  }) async {
    final rows = await _client.rpc('voucher_quote', params: {
      'p_code': code,
      'p_resto_id': restoId,
      'p_customer': customerLabel,
      'p_total': total,
    });
    final list = (rows as List?) ?? const [];
    if (list.isEmpty) {
      return const VoucherQuote(reason: 'Kode voucher tidak ditemukan');
    }
    return VoucherQuote.fromMap(Map<String, dynamic>.from(list.first as Map));
  }

  Future<void> save(Voucher voucher) async {
    await _client.from('vouchers').upsert(voucher.toMap());
  }

  Future<void> delete(String id) async {
    await _client.from('vouchers').delete().eq('id', id);
  }

  /// Pemakaian voucher per resto — dasar hitungan yang harus dibayarkan
  /// KaataGo ke tiap resto.
  Future<Map<String, int>> owedPerResto() async {
    final rows = await _client
        .from('voucher_redemptions')
        .select('resto_id, amount')
        .limit(2000);
    final total = <String, int>{};
    for (final r in rows) {
      final id = r['resto_id'] as String?;
      if (id == null) continue;
      total[id] = (total[id] ?? 0) + ((r['amount'] as num?)?.toInt() ?? 0);
    }
    return total;
  }
}
