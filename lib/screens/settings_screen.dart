import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../providers/auth_provider.dart';
import '../providers/settings_provider.dart';

/// Payment settings (QRIS + bank transfer info). Admin only gets a
/// read-only view here (all fields greyed out, "Kembali" instead of
/// "Simpan") — Finance is the one who can actually edit these, via
/// [editable] = true (see FinanceHomeScreen's own "Pengaturan
/// Pembayaran" entry).
class SettingsScreen extends StatefulWidget {
  final bool editable;

  const SettingsScreen({super.key, this.editable = false});

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
  bool _loading = true;

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
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final restoId = context.read<AuthProvider>().restoId!;
    await context.read<SettingsProvider>().save(
          restoId: restoId,
          merchantName: _merchantCtrl.text.trim(),
          qrisId: _qrisIdCtrl.text.trim(),
          bankName: _bankNameCtrl.text.trim(),
          accountNumber: _accountNumberCtrl.text.trim(),
          accountHolder: _accountHolderCtrl.text.trim(),
        );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Pengaturan disimpan')),
    );
  }

  InputDecoration _decoration(String label) {
    return InputDecoration(
      labelText: label,
      filled: !widget.editable,
      fillColor: widget.editable ? null : const Color(0xFFEEEEEE),
    );
  }

  String? _requiredValidator(String? v) {
    if (!widget.editable) return null; // view-only: nothing to validate
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
                enabled: widget.editable,
                decoration: _decoration('Nama Merchant'),
                validator: _requiredValidator,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _qrisIdCtrl,
                enabled: widget.editable,
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
                enabled: widget.editable,
                decoration: _decoration('Nama Bank'),
                validator: _requiredValidator,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _accountNumberCtrl,
                enabled: widget.editable,
                decoration: _decoration('Nomor Rekening'),
                keyboardType: TextInputType.number,
                validator: _requiredValidator,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _accountHolderCtrl,
                enabled: widget.editable,
                decoration: _decoration('Atas Nama (a.n. ...)'),
                validator: _requiredValidator,
              ),
              const SizedBox(height: 24),
              if (widget.editable)
                FilledButton(
                  onPressed: _save,
                  child: const Text('Simpan'),
                )
              else
                OutlinedButton.icon(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.arrow_back),
                  label: const Text('Kembali'),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
