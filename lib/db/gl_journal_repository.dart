import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/billing.dart';
import '../models/gl_journal_entry.dart';

class GlJournalRepository {
  final _client = Supabase.instance.client;

  /// Jurnal seluruh resto — hanya Super Admin yang bisa membacanya, dan
  /// hanya membaca: tidak ada kebijakan tulis untuk siapa pun.
  ///
  /// Pembukuan KaataGo sendiri disaring keluar. Ia memang tersimpan di
  /// tabel yang sama — penyewa platform memakai mesin pembukuan yang
  /// sama persis dengan resto — tapi mencampurnya di satu layar membuat
  /// total debit/kredit menjumlahkan dua pembukuan yang tidak punya
  /// hubungan satu sama lain: penjualan resto, dan tagihan yang kami
  /// terbitkan kepada mereka.
  ///
  /// Pembukuan KaataGo punya layarnya sendiri, Jurnal GL KaataGo.
  ///
  /// Disaring di kueri, bukan sesudah data sampai: baris platform yang
  /// ikut terangkut memakan jatah batas 1.000 baris, dan yang terpotong
  /// justru jurnal resto yang dicari.
  Future<List<GlJournalEntry>> getAll({int limit = 1000}) async {
    final rows = await _client
        .from('gl_journal_entries')
        .select()
        .neq('resto_id', kPlatformRestoId)
        .order('entry_date', ascending: false)
        .order('entry_time', ascending: false)
        .limit(limit);
    return rows.map((r) => GlJournalEntry.fromMap(r)).toList();
  }

  /// Jurnal sebuah resto, disaring periodenya di server.
  ///
  /// Penyaringan di sini, bukan sesudah barisnya sampai di perangkat:
  /// merchant yang sudah setahun berjalan punya puluhan ribu baris, dan
  /// menariknya seluruhnya demi menampilkan sebulan berarti menunggu
  /// lama untuk data yang langsung dibuang.
  Future<List<GlJournalEntry>> getForResto(
    String restoId, {
    DateTime? mulai,
    DateTime? akhir,
  }) async {
    var q = _client.from('gl_journal_entries').select().eq('resto_id', restoId);
    if (mulai != null) q = q.gte('entry_date', _tanggal(mulai));
    if (akhir != null) q = q.lte('entry_date', _tanggal(akhir));
    final rows = await q.order('created_at', ascending: false);
    return rows.map((r) => GlJournalEntry.fromMap(r)).toList();
  }

  static String _tanggal(DateTime t) =>
      '${t.year.toString().padLeft(4, '0')}-'
      '${t.month.toString().padLeft(2, '0')}-'
      '${t.day.toString().padLeft(2, '0')}';
}
