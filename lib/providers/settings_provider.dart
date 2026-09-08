import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Stores merchant-configurable payment info (QRIS identity + bank account
/// used on the Transfer screen). Persisted locally with SharedPreferences
/// so the employee app works fully offline, and mirrored to a
/// per-restaurant Supabase row (`settings` table, id = restoId) so the
/// customer app — a separate install/device — shows the right
/// restaurant's QRIS info at checkout.
class SettingsProvider extends ChangeNotifier {
  static const _kMerchantName = 'settings_merchant_name';
  static const _kQrisId = 'settings_qris_id';
  static const _kBankName = 'settings_bank_name';
  static const _kAccountNumber = 'settings_account_number';
  static const _kAccountHolder = 'settings_account_holder';

  String merchantName = 'Toko Kamu';
  String qrisId = 'ID12345678901';
  String bankName = 'Bank Dummy Indonesia (BDI)';
  String accountNumber = '1234 5678 9099';
  String accountHolder = 'a.n. Toko Kamu';

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    merchantName = prefs.getString(_kMerchantName) ?? merchantName;
    qrisId = prefs.getString(_kQrisId) ?? qrisId;
    bankName = prefs.getString(_kBankName) ?? bankName;
    accountNumber = prefs.getString(_kAccountNumber) ?? accountNumber;
    accountHolder = prefs.getString(_kAccountHolder) ?? accountHolder;
    notifyListeners();
  }

  /// Menarik info pembayaran milik resto yang sedang dibuka.
  ///
  /// SharedPreferences saja tidak cukup, dan itu yang membuat layar QRIS
  /// menampilkan "Toko Kamu": nilainya tersimpan PER PERANGKAT, jadi HP
  /// yang belum pernah membuka Info Pembayaran merchant ini memakai
  /// nilai bawaan yang tidak ada hubungannya dengan restonya. Kasir baru,
  /// HP baru, atau tablet kedua semuanya jatuh ke sana.
  ///
  /// Nama restonya jadi jaring terakhir. Merchant yang belum pernah
  /// menyimpan Info Pembayaran tetap punya nama — dan nama restonya jauh
  /// lebih benar daripada "Toko Kamu" milik siapa pun.
  Future<void> syncWithResto(String? restoId) async {
    if (restoId == null) return;
    try {
      final client = Supabase.instance.client;
      final rows = await client
          .from('settings')
          .select()
          .eq('resto_id', restoId)
          .limit(1);
      final row = rows.isEmpty ? null : rows.first;

      var nama = (row?['merchant_name'] as String?)?.trim() ?? '';
      if (nama.isEmpty || nama == 'Toko Kamu') {
        final resto = await client
            .from('restaurants')
            .select('name')
            .eq('id', restoId)
            .limit(1);
        if (resto.isNotEmpty) {
          nama = (resto.first['name'] as String?)?.trim() ?? nama;
        }
      }

      if (nama.isNotEmpty) merchantName = nama;
      qrisId = (row?['qris_id'] as String?) ?? qrisId;
      bankName = (row?['bank_name'] as String?) ?? bankName;
      accountNumber = (row?['account_number'] as String?) ?? accountNumber;
      accountHolder = (row?['account_holder'] as String?) ?? accountHolder;

      // Disimpan lokal juga, supaya perangkat yang sedang offline besok
      // tetap menyebut nama yang benar.
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kMerchantName, merchantName);
      await prefs.setString(_kQrisId, qrisId);
      await prefs.setString(_kBankName, bankName);
      await prefs.setString(_kAccountNumber, accountNumber);
      await prefs.setString(_kAccountHolder, accountHolder);

      notifyListeners();
    } catch (_) {
      // Tanpa jawaban server, yang lokal tetap dipakai. Layar pembayaran
      // yang gagal terbuka karena info merchantnya tidak bisa diambil
      // jauh lebih merepotkan daripada nama yang belum diperbarui.
    }
  }

  Future<void> save({
    required String restoId,
    required String merchantName,
    required String qrisId,
    required String bankName,
    required String accountNumber,
    required String accountHolder,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kMerchantName, merchantName);
    await prefs.setString(_kQrisId, qrisId);
    await prefs.setString(_kBankName, bankName);
    await prefs.setString(_kAccountNumber, accountNumber);
    await prefs.setString(_kAccountHolder, accountHolder);

    this.merchantName = merchantName;
    this.qrisId = qrisId;
    this.bankName = bankName;
    this.accountNumber = accountNumber;
    this.accountHolder = accountHolder;
    notifyListeners();

    // Best-effort mirror to Supabase for the customer app. Skipped
    // silently if there's no internet right now.
    try {
      await Supabase.instance.client.from('settings').upsert({
        'resto_id': restoId,
        'merchant_name': merchantName,
        'qris_id': qrisId,
        'bank_name': bankName,
        'account_number': accountNumber,
        'account_holder': accountHolder,
      });
    } catch (_) {}
  }
}
