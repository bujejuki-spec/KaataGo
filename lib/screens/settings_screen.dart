import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../providers/auth_provider.dart';
import '../providers/settings_provider.dart';
import '../widgets/edit_action_bar.dart';
import '../utils/field_rules.dart';
import '../widgets/app_toast.dart';

/// Payment settings (QRIS + bank transfer info) — Finance only, since
/// they're the only role allowed to change these. Admin gets
/// [PaymentInfoScreen] instead, a plain read-only detail view.
///
/// Opens read-only even for Finance: tapping "Edit" is what unlocks the
/// fields, so nothing can change just from opening the screen.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _merchantCtrl;
  late final TextEditingController _qrisIdCtrl;
  late final TextEditingController _bankNameCtrl;
  late final TextEditingController _accountNumberCtrl;
  late final TextEditingController _accountHolderCtrl;
  final _gatewayAccountCtrl = TextEditingController();
  bool _loading = true;
  bool _editing = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    // Pre-fill from this device's local cache first (instant, no flash of
    // empty fields), then refresh from Supabase below — the source of
    // truth, since Admin and Finance are very likely different devices.
    final s = context.read<SettingsProvider>();
    _merchantCtrl = TextEditingController(text: s.merchantName);
    _qrisIdCtrl = TextEditingController(text: s.qrisId);
    _bankNameCtrl = TextEditingController(text: s.bankName);
    _accountNumberCtrl = TextEditingController(text: s.accountNumber);
    _accountHolderCtrl = TextEditingController(text: s.accountHolder);
    _loadFromSupabase();
    _loadGatewayAccount();
  }

  /// Pengenal sub-akun penyedia pembayaran untuk resto ini.
  ///
  /// Disimpan terpisah dari `settings`, yang disiarkan realtime ke layar
  /// pembayaran pelanggan. Bukan karena pengenal ini rahasia, tapi
  /// karena tidak ada gunanya di HP pelanggan — dan yang tidak berguna
  /// di sana sebaiknya tidak ada di sana.
  Future<void> _loadGatewayAccount() async {
    final restoId = context.read<AuthProvider>().restoId;
    if (restoId == null) return;
    try {
      final row = await Supabase.instance.client
          .from('resto_payment_accounts')
          .select('account_id')
          .eq('resto_id', restoId)
          .maybeSingle();
      if (!mounted || row == null) return;
      setState(() => _gatewayAccountCtrl.text = row['account_id'] as String? ?? '');
    } catch (_) {
      // Tabelnya belum dimigrasi, atau perannya tidak boleh membacanya.
      // Layar pengaturan lainnya tetap harus bisa dipakai.
    }
  }

  Future<void> _saveGatewayAccount(String restoId) async {
    final id = _gatewayAccountCtrl.text.trim();
    final table = Supabase.instance.client.from('resto_payment_accounts');
    if (id.isEmpty) {
      await table.delete().eq('resto_id', restoId);
      return;
    }
    await table.upsert({
      'resto_id': restoId,
      'account_id': id,
      'updated_by': context.read<AuthProvider>().user?.email,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }, onConflict: 'resto_id');
  }

  Future<void> _loadFromSupabase() async {
    try {
      final restoId = context.read<AuthProvider>().restoId!;
      final rows = await Supabase.instance.client
          .from('settings')
          .select()
          .eq('resto_id', restoId)
          .limit(1);
      if (rows.isNotEmpty && mounted) {
        final row = rows.first;
        _merchantCtrl.text = row['merchant_name'] as String? ?? _merchantCtrl.text;
        _qrisIdCtrl.text = row['qris_id'] as String? ?? _qrisIdCtrl.text;
        _bankNameCtrl.text = row['bank_name'] as String? ?? _bankNameCtrl.text;
        _accountNumberCtrl.text = row['account_number'] as String? ?? _accountNumberCtrl.text;
        _accountHolderCtrl.text = row['account_holder'] as String? ?? _accountHolderCtrl.text;
      }
    } catch (_) {
      // Offline — keep showing the local cache loaded above.
    }
    if (mounted) setState(() => _loading = false);
  }

  @override
  void dispose() {
    _merchantCtrl.dispose();
    _qrisIdCtrl.dispose();
    _bankNameCtrl.dispose();
    _accountNumberCtrl.dispose();
    _accountHolderCtrl.dispose();
    _gatewayAccountCtrl.dispose();
    super.dispose();
  }

  /// Snapshot taken when Edit is tapped, so Batal can put every field
  /// back exactly as it was rather than leaving half-typed changes on
  /// screen looking saved.
  Map<String, String> _snapshot = const {};

  void _startEdit() {
    _snapshot = {
      'merchant': _merchantCtrl.text,
      'qrisId': _qrisIdCtrl.text,
      'bankName': _bankNameCtrl.text,
      'accountNumber': _accountNumberCtrl.text,
      'accountHolder': _accountHolderCtrl.text,
    };
    setState(() => _editing = true);
  }

  void _cancelEdit() {
    _merchantCtrl.text = _snapshot['merchant'] ?? '';
    _qrisIdCtrl.text = _snapshot['qrisId'] ?? '';
    _bankNameCtrl.text = _snapshot['bankName'] ?? '';
    _accountNumberCtrl.text = _snapshot['accountNumber'] ?? '';
    _accountHolderCtrl.text = _snapshot['accountHolder'] ?? '';
    // Drops any validation errors raised during the abandoned edit.
    _formKey.currentState?.reset();
    setState(() => _editing = false);
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final restoId = context.read<AuthProvider>().restoId!;
    setState(() => _saving = true);
    try {
      await context.read<SettingsProvider>().save(
            restoId: restoId,
            merchantName: _merchantCtrl.text.trim(),
            qrisId: _qrisIdCtrl.text.trim(),
            bankName: _bankNameCtrl.text.trim(),
            accountNumber: _accountNumberCtrl.text.trim(),
            accountHolder: _accountHolderCtrl.text.trim(),
          );
      await _saveGatewayAccount(restoId);
      if (!mounted) return;
      setState(() {
        _editing = false;
        _saving = false;
      });
      showAppToast(context, 'Pengaturan disimpan');
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      showAppToast(context, 'Gagal menyimpan: $e', isError: true);
    }
  }

  InputDecoration _decoration(String label) {
    return InputDecoration(
      labelText: label,
      filled: !_editing,
      fillColor: _editing ? null : const Color(0xFFEEEEEE),
    );
  }

  String? _requiredValidator(String? v) {
    if (!_editing) return null; // view-only: nothing to validate
    return (v == null || v.trim().isEmpty) ? 'Wajib diisi' : null;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Pengaturan Pembayaran'),
        actions: [
          if (_loading)
            const Padding(
              padding: EdgeInsets.only(right: 16),
              child: Center(
                child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                ),
              ),
            )
          else if (!_editing)
            IconButton(
              icon: const Icon(Icons.edit_outlined),
              tooltip: 'Edit',
              onPressed: _startEdit,
            ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: ListView(
            children: [
              const Text(
                'QRIS',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _merchantCtrl,
                enabled: _editing,
                decoration: _decoration('Nama Merchant'),
                inputFormatters: nameFormatters,
                textCapitalization: TextCapitalization.words,
                validator: (v) =>
                    _editing ? validateName(v, label: 'Nama merchant') : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _qrisIdCtrl,
                enabled: _editing,
                decoration: _decoration('ID QRIS Merchant'),
                validator: _requiredValidator,
              ),
              const SizedBox(height: 24),
              const Text(
                'Transfer Bank',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _bankNameCtrl,
                enabled: _editing,
                decoration: _decoration('Nama Bank'),
                inputFormatters: nameFormatters,
                textCapitalization: TextCapitalization.characters,
                validator: (v) => _editing ? validateName(v, label: 'Nama bank') : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _accountNumberCtrl,
                enabled: _editing,
                decoration: _decoration('Nomor Rekening'),
                keyboardType: TextInputType.number,
                inputFormatters: accountNumberFormatters,
                validator: (v) => _editing ? validateAccountNumber(v) : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _accountHolderCtrl,
                enabled: _editing,
                decoration: _decoration('Atas Nama (a.n. ...)'),
                inputFormatters: nameFormatters,
                textCapitalization: TextCapitalization.words,
                validator: (v) =>
                    _editing ? validateName(v, label: 'Nama pemilik rekening') : null,
              ),
              const SizedBox(height: 20),
              const Divider(),
              const SizedBox(height: 12),
              Text('Payment Gateway',
                  style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                      color: Colors.grey.shade700)),
              const SizedBox(height: 8),
              TextFormField(
                controller: _gatewayAccountCtrl,
                enabled: _editing,
                decoration: _decoration('ID Akun Xendit').copyWith(
                  helperText: 'Sub-akun resto ini. Dana QRIS cair langsung '
                      'ke rekening yang terdaftar di sub-akun itu.',
                  helperMaxLines: 3,
                ),
              ),
              const SizedBox(height: 24),
              if (_editing)
                EditActionBar(
                  onCancel: _cancelEdit,
                  onSave: _save,
                  saving: _saving,
                ),
            ],
          ),
        ),
      ),
    );
  }
}
