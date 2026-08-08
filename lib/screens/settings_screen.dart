import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/auth_provider.dart';
import '../providers/settings_provider.dart';

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

  @override
  void initState() {
    super.initState();
    final s = context.read<SettingsProvider>();
    _merchantCtrl = TextEditingController(text: s.merchantName);
    _qrisIdCtrl = TextEditingController(text: s.qrisId);
    _bankNameCtrl = TextEditingController(text: s.bankName);
    _accountNumberCtrl = TextEditingController(text: s.accountNumber);
    _accountHolderCtrl = TextEditingController(text: s.accountHolder);
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Pengaturan Pembayaran')),
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
                decoration: const InputDecoration(labelText: 'Nama Merchant'),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Wajib diisi' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _qrisIdCtrl,
                decoration: const InputDecoration(labelText: 'ID QRIS Merchant'),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Wajib diisi' : null,
              ),
              const SizedBox(height: 24),
              const Text(
                'Transfer Bank',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _bankNameCtrl,
                decoration: const InputDecoration(labelText: 'Nama Bank'),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Wajib diisi' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _accountNumberCtrl,
                decoration: const InputDecoration(labelText: 'Nomor Rekening'),
                keyboardType: TextInputType.number,
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Wajib diisi' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _accountHolderCtrl,
                decoration:
                    const InputDecoration(labelText: 'Atas Nama (a.n. ...)'),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Wajib diisi' : null,
              ),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: _save,
                child: const Text('Simpan'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
