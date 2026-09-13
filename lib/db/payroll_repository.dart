import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/absensi.dart';

/// Aturan gaji, gaji per karyawan, dan rekap satu periode.
class PayrollRepository {
  final _client = Supabase.instance.client;

  static String _tgl(DateTime d) => '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  Future<AturanGaji> aturan(String restoId) async {
    final rows = await _client
        .from('payroll_settings')
        .select()
        .eq('resto_id', restoId)
        .limit(1);
    if (rows.isEmpty) return const AturanGaji();
    return AturanGaji.fromMap(rows.first);
  }

  Future<void> simpanAturan(String restoId, AturanGaji aturan, String oleh) =>
      _client.from('payroll_settings').upsert({
        'resto_id': restoId,
        ...aturan.toMap(),
        'updated_at': DateTime.now().toUtc().toIso8601String(),
        'updated_by': oleh,
      });

  Future<List<GajiKaryawan>> gajiSemua(String restoId) async {
    final rows =
        await _client.from('employee_payroll').select().eq('resto_id', restoId);
    return rows.map((r) => GajiKaryawan.fromMap(r)).toList();
  }

  Future<void> simpanGaji({
    required String restoId,
    required GajiKaryawan gaji,
    required String oleh,
  }) =>
      _client.from('employee_payroll').upsert({
        'resto_id': restoId,
        'employee_email': gaji.email.toLowerCase(),
        'gaji_pokok': gaji.gajiPokok,
        'tunjangan': gaji.tunjangan,
        'bank_name': gaji.bankName,
        'account_number': gaji.accountNumber,
        'account_holder': gaji.accountHolder,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
        'updated_by': oleh,
      });

  /// Rekap seluruh karyawan untuk satu periode. Owner dan Finance saja.
  Future<List<BarisPayroll>> rekap(
      String restoId, DateTime mulai, DateTime akhir) async {
    final rows = await _client.rpc('rekap_payroll', params: {
      'p_resto_id': restoId,
      'p_mulai': _tgl(mulai),
      'p_akhir': _tgl(akhir),
    });
    return [
      for (final r in (rows as List? ?? const []))
        BarisPayroll.fromMap(Map<String, dynamic>.from(r as Map)),
    ];
  }

  /// Slip gaji orang yang sedang masuk.
  ///
  /// Fungsi tersendiri di server, bukan [rekap] yang disaring: rekapnya
  /// menolak siapa pun selain Owner dan Finance, dan melonggarkan
  /// syaratnya supaya karyawan bisa masuk berarti melonggarkannya untuk
  /// seluruh baris sekaligus.
  Future<BarisPayroll?> slipSaya({
    required String restoId,
    required DateTime mulai,
    required DateTime akhir,
    required String email,
    required String nama,
  }) async {
    final rows = await _client.rpc('slip_gaji_saya', params: {
      'p_resto_id': restoId,
      'p_mulai': _tgl(mulai),
      'p_akhir': _tgl(akhir),
    });
    final list = (rows as List?) ?? const [];
    if (list.isEmpty) return null;
    return BarisPayroll.fromMap({
      ...Map<String, dynamic>.from(list.first as Map),
      'employee_email': email,
      'nama': nama,
    });
  }
}
