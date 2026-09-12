import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/bank_account.dart';

/// Rekening perusahaan, berikut resto mana yang memakainya.
class BankAccountRepository {
  final _client = Supabase.instance.client;

  /// Rekening yang dipakai sebuah resto, yang utama lebih dulu.
  Future<List<BankAccount>> untukResto(String restoId) async {
    final rows = await _client
        .from('resto_bank_accounts')
        .select('is_primary, bank_accounts(*)')
        .eq('resto_id', restoId);

    final hasil = <BankAccount>[
      for (final r in rows)
        if (r['bank_accounts'] != null)
          BankAccount.fromMap({
            ...Map<String, dynamic>.from(r['bank_accounts'] as Map),
            'is_primary': r['is_primary'],
          }),
    ];
    hasil.sort((a, b) {
      if (a.isPrimary != b.isPrimary) return a.isPrimary ? -1 : 1;
      return a.tampilan.toLowerCase().compareTo(b.tampilan.toLowerCase());
    });
    return hasil;
  }

  /// Rekening utama resto ini, atau null kalau belum ada satu pun.
  Future<BankAccount?> utama(String restoId) async {
    final semua = await untukResto(restoId);
    for (final r in semua) {
      if (r.isPrimary) return r;
    }
    return semua.isEmpty ? null : semua.first;
  }

  /// Menambah rekening, lalu menautkannya ke resto.
  ///
  /// Nomor yang sama di bank yang sama adalah rekening yang SAMA, dan
  /// basis datanya menegakkan itu lewat unique index. Jadi menambahkan
  /// rekening yang sudah ada — misalnya karena cabang kedua memakai
  /// rekening yang sama — tidak melahirkan baris kedua, cuma menautkan
  /// yang sudah ada. Itu justru yang diinginkan: satu rekening satu
  /// tempat menautkan mutasinya.
  Future<BankAccount> tambah({
    required String restoId,
    required BankAccount rekening,
    bool jadikanUtama = false,
  }) async {
    final adaRow = await _client
        .from('bank_accounts')
        .select()
        .ilike('bank_name', rekening.bankName.trim())
        .eq('account_number', rekening.accountNumber.trim())
        .limit(1);

    final Map<String, dynamic> baris;
    if (adaRow.isNotEmpty) {
      baris = Map<String, dynamic>.from(adaRow.first);
    } else {
      baris = Map<String, dynamic>.from(await _client
          .from('bank_accounts')
          .insert(rekening.toMap())
          .select()
          .single());
    }

    await _tautkan(restoId, baris['id'].toString(), jadikanUtama);
    return BankAccount.fromMap({...baris, 'is_primary': jadikanUtama});
  }

  Future<void> ubah(BankAccount rekening) async {
    await _client
        .from('bank_accounts')
        .update(rekening.toMap())
        .eq('id', rekening.id);
  }

  /// Melepas rekening dari sebuah resto.
  ///
  /// Barisnya sendiri tidak dihapus: rekening yang sama bisa sedang
  /// dipakai cabang lain, dan mutasi bank yang sudah tertaut padanya
  /// akan kehilangan acuannya. Yang dilepas cuma pemakaiannya di sini.
  Future<void> lepas(String restoId, String bankAccountId) async {
    await _client
        .from('resto_bank_accounts')
        .delete()
        .eq('resto_id', restoId)
        .eq('bank_account_id', bankAccountId);
  }

  Future<void> jadikanUtama(String restoId, String bankAccountId) =>
      _tautkan(restoId, bankAccountId, true);

  Future<void> _tautkan(
      String restoId, String bankAccountId, bool utama) async {
    if (utama) {
      // Yang lama diturunkan lebih dulu. Basis datanya cuma
      // mengizinkan satu yang utama per resto, jadi menaikkan yang baru
      // sebelum menurunkan yang lama akan ditolak — dan penolakannya
      // terbaca sebagai "gagal menyimpan", bukan sebagai aturan.
      await _client
          .from('resto_bank_accounts')
          .update({'is_primary': false})
          .eq('resto_id', restoId);
    }
    await _client.from('resto_bank_accounts').upsert({
      'resto_id': restoId,
      'bank_account_id': bankAccountId,
      'is_primary': utama,
    });
  }
}
