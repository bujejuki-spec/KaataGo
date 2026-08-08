import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../db/gl_account_repository.dart';
import '../models/gl_account.dart';
import '../providers/auth_provider.dart';

const _paymentMethods = ['cash', 'qris', 'transfer'];
const _paymentLabels = {'cash': 'Tunai', 'qris': 'QRIS', 'transfer': 'Transfer'};

/// Lets Finance set which GL (General Ledger) account code each payment
/// method's income should be booked to — one code+name per method, per
/// resto. Used by [FinanceIncomeScreen]'s totals and offered as the GL
/// tag when recording an expense in [FinanceBalanceScreen].
class FinanceGlMappingScreen extends StatefulWidget {
  const FinanceGlMappingScreen({super.key});

  @override
  State<FinanceGlMappingScreen> createState() => _FinanceGlMappingScreenState();
}

class _FinanceGlMappingScreenState extends State<FinanceGlMappingScreen> {
  final _repo = GlAccountRepository();
  final _formKey = GlobalKey<FormState>();
  final Map<String, TextEditingController> _codeCtrls = {
    for (final m in _paymentMethods) m: TextEditingController(),
  };
  final Map<String, TextEditingController> _nameCtrls = {
    for (final m in _paymentMethods) m: TextEditingController(),
  };
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final c in _codeCtrls.values) {
      c.dispose();
    }
    for (final c in _nameCtrls.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    final restoId = context.read<AuthProvider>().restoId!;
    final accounts = await _repo.getForResto(restoId);
    if (!mounted) return;
    for (final a in accounts) {
      _codeCtrls[a.paymentMethod]?.text = a.glCode;
      _nameCtrls[a.paymentMethod]?.text = a.glName;
    }
    setState(() => _loading = false);
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final restoId = context.read<AuthProvider>().restoId!;
    setState(() => _saving = true);
    try {
      for (final method in _paymentMethods) {
        final code = _codeCtrls[method]!.text.trim();
        final name = _nameCtrls[method]!.text.trim();
        if (code.isEmpty && name.isEmpty) continue; // leave unmapped methods alone
        await _repo.upsert(GlAccount(
          restoId: restoId,
          paymentMethod: method,
          glCode: code,
          glName: name,
        ));
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Mapping GL Account tersimpan.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Gagal menyimpan: $e')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Mapping GL Account')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Padding(
              padding: const EdgeInsets.all(16),
              child: Form(
                key: _formKey,
                child: ListView(
                  children: [
                    Text(
                      'Tentukan nomor & nama GL Account untuk tiap metode pembayaran, '
                      'supaya pemasukan tercatat ke akun yang tepat.',
                      style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
                    ),
                    const SizedBox(height: 20),
                    for (final method in _paymentMethods) ...[
                      Text(_paymentLabels[method]!,
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                      const SizedBox(height: 8),
                      TextFormField(
                        controller: _codeCtrls[method],
                        decoration: const InputDecoration(labelText: 'Kode GL Account'),
                      ),
                      const SizedBox(height: 8),
                      TextFormField(
                        controller: _nameCtrls[method],
                        decoration: const InputDecoration(labelText: 'Nama GL Account'),
                      ),
                      const SizedBox(height: 20),
                    ],
                    FilledButton(
                      onPressed: _saving ? null : _save,
                      child: _saving
                          ? const SizedBox(
                              width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Text('Simpan Mapping'),
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}
