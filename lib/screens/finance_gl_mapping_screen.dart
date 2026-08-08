import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../db/expense_gl_account_repository.dart';
import '../db/gl_account_repository.dart';
import '../models/expense_gl_account.dart';
import '../models/gl_account.dart';
import '../providers/auth_provider.dart';

const _paymentMethods = ['cash', 'qris', 'transfer'];
const _paymentLabels = {'cash': 'Tunai', 'qris': 'QRIS', 'transfer': 'Transfer'};

/// Lets Finance set which GL (General Ledger) account code each payment
/// method's INCOME should be booked to (one per method, per resto), plus
/// maintain a separate chart of GL accounts for EXPENSES (as many
/// categories as needed — Sewa, Gaji, Bahan Baku, ...), offered as the
/// GL tag when recording an expense in [FinanceBalanceScreen].
class FinanceGlMappingScreen extends StatefulWidget {
  const FinanceGlMappingScreen({super.key});

  @override
  State<FinanceGlMappingScreen> createState() => _FinanceGlMappingScreenState();
}

class _FinanceGlMappingScreenState extends State<FinanceGlMappingScreen> {
  final _repo = GlAccountRepository();
  final _expenseGlRepo = ExpenseGlAccountRepository();
  final _formKey = GlobalKey<FormState>();
  final Map<String, TextEditingController> _codeCtrls = {
    for (final m in _paymentMethods) m: TextEditingController(),
  };
  final Map<String, TextEditingController> _nameCtrls = {
    for (final m in _paymentMethods) m: TextEditingController(),
  };
  List<ExpenseGlAccount> _expenseAccounts = [];
  bool _loading = true;
  bool _saving = false;

  String get _restoId => context.read<AuthProvider>().restoId!;

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
    final restoId = _restoId;
    final results = await Future.wait([
      _repo.getForResto(restoId),
      _expenseGlRepo.getForResto(restoId),
    ]);
    if (!mounted) return;
    for (final a in results[0] as List<GlAccount>) {
      _codeCtrls[a.paymentMethod]?.text = a.glCode;
      _nameCtrls[a.paymentMethod]?.text = a.glName;
    }
    setState(() {
      _expenseAccounts = results[1] as List<ExpenseGlAccount>;
      _loading = false;
    });
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final restoId = _restoId;
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

  Future<void> _addExpenseGlAccount() async {
    final codeCtrl = TextEditingController();
    final nameCtrl = TextEditingController();
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Tambah GL Pengeluaran'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: codeCtrl,
              decoration: const InputDecoration(labelText: 'Kode GL Account'),
              autofocus: true,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: nameCtrl,
              decoration: const InputDecoration(labelText: 'Nama GL Account'),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Batal')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Tambah')),
        ],
      ),
    );
    if (saved != true) return;
    final code = codeCtrl.text.trim();
    final name = nameCtrl.text.trim();
    if (code.isEmpty || name.isEmpty) return;
    await _expenseGlRepo.create(_restoId, code, name);
    _load();
  }

  Future<void> _deleteExpenseGlAccount(ExpenseGlAccount a) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Hapus GL Account?'),
        content: Text('${a.glCode} — ${a.glName}'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Batal')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Hapus', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    await _expenseGlRepo.delete(a.id);
    _load();
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
                    const Text('GL Pemasukan', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                    const SizedBox(height: 4),
                    Text(
                      'Tentukan nomor & nama GL Account untuk tiap metode pembayaran, '
                      'supaya pemasukan tercatat ke akun yang tepat.',
                      style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
                    ),
                    const SizedBox(height: 16),
                    for (final method in _paymentMethods) ...[
                      Text(_paymentLabels[method]!,
                          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
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
                          : const Text('Simpan Mapping Pemasukan'),
                    ),
                    const Divider(height: 40),
                    const Text('GL Pengeluaran', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                    const SizedBox(height: 4),
                    Text(
                      'Daftar akun GL untuk kategori pengeluaran (bisa lebih dari satu) — '
                      'akan muncul sebagai pilihan saat mencatat pengeluaran.',
                      style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
                    ),
                    const SizedBox(height: 12),
                    if (_expenseAccounts.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Text('Belum ada GL pengeluaran.', style: TextStyle(color: Colors.grey.shade600)),
                      )
                    else
                      ..._expenseAccounts.map((a) => Card(
                            child: ListTile(
                              leading: const Icon(Icons.numbers),
                              title: Text('${a.glCode} — ${a.glName}'),
                              trailing: IconButton(
                                icon: const Icon(Icons.delete_outline, color: Colors.red),
                                onPressed: () => _deleteExpenseGlAccount(a),
                              ),
                            ),
                          )),
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      onPressed: _addExpenseGlAccount,
                      icon: const Icon(Icons.add),
                      label: const Text('Tambah GL Pengeluaran'),
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}
