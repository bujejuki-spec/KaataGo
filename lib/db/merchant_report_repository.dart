import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/merchant_report.dart';

/// Laporan penjualan milik merchant sendiri.
///
/// Seluruhnya dihitung server. Menghitungnya di HP berarti mengunduh
/// seluruh pesanan lalu menguraikan `items` satu per satu — dan batas
/// 1.000 baris PostgREST memotongnya diam-diam pada merchant yang ramai,
/// yaitu merchant yang paling butuh laporan ini.
class MerchantReportRepository {
  final _client = Supabase.instance.client;

  Map<String, dynamic> _rentang(String restoId, DateTime dari, DateTime sampai) => {
        'p_resto_id': restoId,
        'p_from': _tanggal(dari),
        'p_to': _tanggal(sampai),
      };

  static String _tanggal(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  Future<RingkasanPenjualan> ringkasan(
      String restoId, DateTime dari, DateTime sampai) async {
    final rows = await _client.rpc('report_sales_summary',
        params: _rentang(restoId, dari, sampai));
    final list = rows as List? ?? const [];
    if (list.isEmpty) return const RingkasanPenjualan();
    return RingkasanPenjualan.fromMap(
        Map<String, dynamic>.from(list.first as Map));
  }

  Future<List<PenjualanMenu>> terlaris(
      String restoId, DateTime dari, DateTime sampai,
      {int batas = 10}) async {
    final rows = await _client.rpc('report_menu_sales', params: {
      ..._rentang(restoId, dari, sampai),
      'p_limit': batas,
    });
    return [
      for (final r in (rows as List? ?? const []))
        PenjualanMenu.fromMap(Map<String, dynamic>.from(r as Map)),
    ];
  }

  Future<List<MenuTidakLaku>> tidakLaku(
      String restoId, DateTime dari, DateTime sampai) async {
    final rows = await _client.rpc('report_idle_menus',
        params: _rentang(restoId, dari, sampai));
    return [
      for (final r in (rows as List? ?? const []))
        MenuTidakLaku.fromMap(Map<String, dynamic>.from(r as Map)),
    ];
  }

  Future<List<JamRamai>> jamRamai(
      String restoId, DateTime dari, DateTime sampai) async {
    final rows = await _client.rpc('report_busy_hours',
        params: _rentang(restoId, dari, sampai));
    return [
      for (final r in (rows as List? ?? const []))
        JamRamai.fromMap(Map<String, dynamic>.from(r as Map)),
    ];
  }
  /// Deret waktu penjualan, lubangnya sudah diisi nol oleh server.
  ///
  /// [satuan] 'day' | 'week' | 'month'. Rentang setahun yang digambar
  /// harian menjadi 365 batang selebar rambut di layar HP.
  Future<List<TitikPenjualan>> deret(
    String restoId,
    DateTime dari,
    DateTime sampai, {
    String satuan = 'day',
  }) async {
    final rows = await _client.rpc('report_sales_series', params: {
      ..._rentang(restoId, dari, sampai),
      'p_bucket': satuan,
    });
    return [
      for (final r in (rows as List? ?? const []))
        TitikPenjualan.fromMap(Map<String, dynamic>.from(r as Map)),
    ];
  }

  /// Pembagian omzet menurut [dimensi]: 'payment_method' | 'order_type'
  /// | 'source' | 'cashier'.
  Future<List<PotongPenjualan>> pembagian(
    String restoId,
    DateTime dari,
    DateTime sampai, {
    required String dimensi,
  }) async {
    final rows = await _client.rpc('report_sales_breakdown', params: {
      ..._rentang(restoId, dari, sampai),
      'p_dimensi': dimensi,
    });
    return [
      for (final r in (rows as List? ?? const []))
        PotongPenjualan.fromMap(Map<String, dynamic>.from(r as Map)),
    ];
  }

  /// Pembagian per kategori menu.
  ///
  /// Jumlahnya tidak persis sama dengan omzet: yang dijumlahkan harga
  /// baris menunya, sedangkan service per tagihan dan potongan tidak
  /// menempel di baris mana pun.
  Future<List<PotongPenjualan>> perKategori(
      String restoId, DateTime dari, DateTime sampai) async {
    final rows = await _client.rpc('report_sales_by_category',
        params: _rentang(restoId, dari, sampai));
    return [
      for (final r in (rows as List? ?? const []))
        PotongPenjualan.fromMap(Map<String, dynamic>.from(r as Map)),
    ];
  }
}
