import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../db/expense_gl_account_repository.dart';
import '../db/expense_repository.dart';
import '../db/order_repository.dart';
import '../models/customer_order.dart';
import '../models/expense.dart';
import '../models/expense_gl_account.dart';
import '../providers/auth_provider.dart';

/// Balance = total paid income (all time, from Supabase `orders`) minus
/// total expenses — computed on the fly rather than stored, so it's
/// always consistent with the underlying orders/expenses data. Finance
/// can also record new expenses here, each optionally tagged with a GL
/// code, which immediately reduces the balance shown.
class FinanceBalanceScreen extends StatefulWidget {
  const FinanceBalanceScreen({super.key});

  @override
  State<FinanceBalanceScreen> createState() => _FinanceBalanceScreenState();
}

class _FinanceBalanceScreenState extends State<FinanceBalanceScreen> {
  final _orderRepo = OrderRepository();
  final _expenseRepo = ExpenseRepository();
  final _expenseGlRepo = ExpenseGlAccountRepository();

  int _income = 0;
  List<Expense> _expenses = [];
  List<ExpenseGlAccount> _expenseGlAccounts = [];
  bool _loading = true;

  String get _restoId => context.read<AuthProvider>().restoId!;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final restoId = _restoId;
    final results = await Future.wait([
      _orderRepo.watchAll(restoId).first,
      _expenseRepo.getForResto(restoId),
      _expenseGlRepo.getForResto(restoId),
    ]);
    if (!mounted) return;
    final orders = (results[0] as List<CustomerOrder>)
        .where((o) => o.paymentStatus == OrderPaymentStatus.paid);
    setState(() {
      _income = orders.fold(0, (sum, o) => sum + o.total);
      _expenses = results[1] as List<Expense>;
      _expenseGlAccounts = results[2] as List<ExpenseGlAccount>;
      _loading = false;
    });
  }

  int get _totalExpenses => _expenses.fold(0, (sum, e) => sum + e.amount);
  int get _balance => _income - _totalExpenses;

  List<_DayExpenseGroup> _groupExpensesByDay() {
    final byDay = <DateTime, List<Expense>>{};
    for (final e in _expenses) {
      final day = DateTime(e.createdAt.year, e.createdAt.month, e.createdAt.day);
      byDay.putIfAbsent(day, () => []).add(e);
    }
    final days = byDay.keys.toList()..sort((a, b) => b.compareTo(a));
    return days.map((d) => _DayExpenseGroup(d, byDay[d]!)).toList();
  }

  Future<void> _addExpense() async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => _AddExpenseDialog(restoId: _restoId, glAccounts: _expenseGlAccounts),
    );
    if (saved == true) _load();
  }

  Future<void> _deleteExpense(Expense e) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Hapus pengeluaran?'),
        content: Text(e.description),
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
    await _expenseRepo.delete(e.id);
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final currency = NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0);

    return Scaffold(
      appBar: AppBar(title: const Text('Saldo & Pengeluaran')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addExpense,
        icon: const Icon(Icons.remove_circle_outline),
        label: const Text('Catat Pengeluaran'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(16),
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: _balance >= 0
                            ? [const Color(0xFF10B981), const Color(0xFF0F766E)]
                            : [const Color(0xFFEF4444), const Color(0xFFB91C1C)],
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: (_balance >= 0 ? const Color(0xFF10B981) : const Color(0xFFEF4444))
                              .withOpacity(0.25),
                          blurRadius: 18,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.account_balance_wallet_outlined,
                                  color: Colors.white.withOpacity(0.85), size: 18),
                              const SizedBox(width: 6),
                              Text('Saldo Total', style: TextStyle(color: Colors.white.withOpacity(0.85))),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Text(
                            currency.format(_balance),
                            style: const TextStyle(
                                fontSize: 28, fontWeight: FontWeight.bold, color: Colors.white),
                          ),
                          Divider(height: 28, color: Colors.white.withOpacity(0.3)),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text('Pemasukan', style: TextStyle(color: Colors.white.withOpacity(0.9))),
                              Text(currency.format(_income),
                                  style: const TextStyle(fontWeight: FontWeight.w600, color: Colors.white)),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text('Pengeluaran', style: TextStyle(color: Colors.white.withOpacity(0.9))),
                              Text('- ${currency.format(_totalExpenses)}',
                                  style: const TextStyle(fontWeight: FontWeight.w600, color: Colors.white)),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  const Text('Riwayat Pengeluaran', style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  if (_expenses.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 16),
                      child: Text('Belum ada pengeluaran tercatat.', style: TextStyle(color: Colors.grey)),
                    )
                  else
                    ..._groupExpensesByDay().map((group) {
                      return Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        clipBehavior: Clip.antiAlias,
                        child: ExpansionTile(
                          initiallyExpanded: true,
                          title: Text(DateFormat('EEEE, dd MMM yyyy', 'id_ID').format(group.day),
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                          subtitle: Text('- ${currency.format(group.total)}',
                              style: const TextStyle(color: Colors.red, fontWeight: FontWeight.w600)),
                          childrenPadding: const EdgeInsets.only(bottom: 4),
                          children: group.expenses.map((e) => ListTile(
                                dense: true,
                                leading: const Icon(Icons.receipt_long_outlined),
                                title: Text(e.description),
                                subtitle: Text(
                                  '${DateFormat('HH:mm').format(e.createdAt)} • ${e.createdBy}'
                                  '${e.glCode != null ? ' • GL ${e.glCode}' : ''}',
                                ),
                                trailing: Text('- ${currency.format(e.amount)}',
                                    style: const TextStyle(color: Colors.red, fontWeight: FontWeight.w600)),
                                onLongPress: () => _deleteExpense(e),
                              )).toList(),
                        ),
                      );
                    }),
                ],
              ),
            ),
    );
  }
}

class _DayExpenseGroup {
  final DateTime day;
  final List<Expense> expenses;
  final int total;

  _DayExpenseGroup(this.day, this.expenses)
      : total = expenses.fold(0, (sum, e) => sum + e.amount);
}

class _AddExpenseDialog extends StatefulWidget {
  final String restoId;
  final List<ExpenseGlAccount> glAccounts;

  const _AddExpenseDialog({required this.restoId, required this.glAccounts});

  @override
  State<_AddExpenseDialog> createState() => _AddExpenseDialogState();
}

class _AddExpenseDialogState extends State<_AddExpenseDialog> {
  final _formKey = GlobalKey<FormState>();
  final _amountCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  String? _glCode;
  final _repo = ExpenseRepository();
  bool _saving = false;

  @override
  void dispose() {
    _amountCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final auth = context.read<AuthProvider>();
    setState(() => _saving = true);
    try {
      await _repo.create(Expense(
        id: '',
        restoId: widget.restoId,
        amount: int.parse(_amountCtrl.text.trim()),
        description: _descCtrl.text.trim(),
        glCode: _glCode,
        createdBy: auth.user?.email ?? 'Finance',
        createdAt: DateTime.now(),
      ));
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Gagal menyimpan: $e')));
      setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Catat Pengeluaran'),
      content: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _amountCtrl,
                decoration: const InputDecoration(labelText: 'Jumlah (Rp)'),
                keyboardType: TextInputType.number,
                validator: (v) {
                  if (v == null || v.trim().isEmpty) return 'Wajib diisi';
                  final n = int.tryParse(v.trim());
                  if (n == null || n <= 0) return 'Harus angka > 0';
                  return null;
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _descCtrl,
                decoration: const InputDecoration(labelText: 'Deskripsi'),
                maxLines: 2,
                validator: (v) => (v == null || v.trim().isEmpty) ? 'Wajib diisi' : null,
              ),
              if (widget.glAccounts.isNotEmpty) ...[
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: _glCode,
                  decoration: const InputDecoration(labelText: 'GL Account (opsional)'),
                  items: widget.glAccounts
                      .map((g) => DropdownMenuItem(
                            value: g.glCode,
                            child: Text('${g.glCode} — ${g.glName}'),
                          ))
                      .toList(),
                  onChanged: (v) => setState(() => _glCode = v),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Batal')),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: _saving
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Simpan'),
        ),
      ],
    );
  }
}
