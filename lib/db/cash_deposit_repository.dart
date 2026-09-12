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

  /// Aliran langsung setoran resto ini, terbaru di atas.
  ///
  /// Dipakai penanda jumlah pengajuan yang menunggu dan pemberitahuan
  /// hasilnya — keduanya harus berubah tanpa layarnya dibuka ulang.
  Stream<List<CashDeposit>> watchForResto(String restoId) {
    return _client
        .from('cash_deposits')
        .stream(primaryKey: ['id'])
        .eq('resto_id', restoId)
        .order('created_at', ascending: false)
        .map((rows) => rows.map((r) => CashDeposit.fromMap(r)).toList());
  }

  /// Berapa setoran yang masih menunggu keputusan Finance.
  ///
  /// Dihitung di server dengan `count`, bukan dengan mengambil semua
  /// barisnya lalu menyaring di HP: yang dibutuhkan cuma satu angka,
  /// sedangkan tiap baris setoran membawa foto bukti dalam base64.
  Future<int> pendingCount(String restoId) async {
    return await _client
        .from('cash_deposits')
        .count(CountOption.exact)
        .eq('resto_id', restoId)
        .eq('status', 'pending');
  }

  Future<void> create(CashDeposit deposit) async {
    await _client.from('cash_deposits').insert(deposit.toMap());
  }

  Future<void> delete(String id) async {
    await _client.from('cash_deposits').delete().eq('id', id);
  }

  /// Menyetujui atau menolak satu setoran.
  ///
  /// Hanya baris ini yang disentuh, dan trigger jurnalnya pun bekerja per
  /// baris — jadi menyetujui satu setoran tidak akan ikut memindahkan
  /// setoran lain yang masih menunggu.
  Future<void> review(
    String id, {
    required DepositStatus status,
    required String reviewedBy,
    String? note,
  }) async {
    await _client.from('cash_deposits').update({
      'status': status.dbValue,
      'reviewed_by': reviewedBy,
      'reviewed_at': DateTime.now().toUtc().toIso8601String(),
      if (note != null && note.trim().isNotEmpty) 'review_note': note.trim(),
    }).eq('id', id);
  }

  /// Cash pickup di merchant ini, yang belum diterima lebih dulu.
  Future<List<CashDeposit>> pickup(String restoId) async {
    final rows = await _client
        .from('cash_deposits')
        .select()
        .eq('resto_id', restoId)
        .eq('method', 'pickup')
        .order('created_at', ascending: false);
    final semua = rows.map((r) => CashDeposit.fromMap(r)).toList();
    semua.sort((a, b) {
      if (a.sudahDiterima != b.sudahDiterima) return a.sudahDiterima ? 1 : -1;
      return b.createdAt.compareTo(a.createdAt);
    });
    return semua;
  }

  /// Berapa pickup yang uangnya sudah dibawa pergi dan belum diakui
  /// diterima siapa pun. Inilah penanda yang layak dipajang di menu.
  Future<int> pickupBelumDiterima(String restoId) async {
    return await _client
        .from('cash_deposits')
        .count(CountOption.exact)
        .eq('resto_id', restoId)
        .eq('method', 'pickup')
        .isFilter('received_at', null);
  }

  /// Menerima satu cash pickup.
  ///
  /// Lewat RPC, bukan update biasa: yang terjadi bukan cuma mengisi
  /// kolom — uangnya berpindah dari GL Cash Pickup ke GL Saldo Cash
  /// Perusahaan, dan jurnal itu tidak boleh bergantung pada aplikasi
  /// yang mengirimnya. Nama penerimanya juga diambil server dari data
  /// karyawan, bukan dari perangkat orang yang menekan tombolnya.
  Future<CashDeposit> terimaPickup({
    required String id,
    required int jumlahDiterima,
    required String namaPetugas,
    required String bukti,
    String? nomorSeal,
  }) async {
    final row = await _client.rpc('terima_pickup', params: {
      'p_id': id,
      'p_amount': jumlahDiterima,
      'p_officer': namaPetugas,
      'p_proof': bukti,
      'p_seal': nomorSeal,
    });
    return CashDeposit.fromMap(Map<String, dynamic>.from(row as Map));
  }
}
