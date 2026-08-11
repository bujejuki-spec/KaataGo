import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../db/expense_gl_account_repository.dart';
import '../db/expense_repository.dart';
import '../db/order_repository.dart';
import '../db/petty_cash_repository.dart';
import '../models/customer_order.dart';
import '../models/expense.dart';
import '../models/expense_gl_account.dart';
import '../models/petty_cash_entry.dart';
import '../providers/auth_provider.dart';
import '../utils/id_time.dart';
import '../widgets/dialog_actions.dart';
import '../utils/rupiah_input.dart';

/// Saldo Total = Saldo Penghasilan + Saldo Petty Cash − Saldo Pengeluaran.
///
/// - Saldo Penghasilan: sum of paid orders (all the resto's Cash/QRIS/
///   Transfer income — GL Penghasilan), minus whatever's been withdrawn
///   out of it into Petty Cash.
/// - Saldo Petty Cash: a small manually-managed float, topped up either by
///   withdrawing from Saldo Penghasilan or a manual entry (needed on day
///   one, before any income exists yet).
/// - Saldo Pengeluaran: sum of all recorded expenses (GL Pengeluaran,
///   tagged to whichever expense GL account — e.g. GL Operational).
///
/// Everything here is computed on the fly from `orders`/`expenses`/
/// `petty_cash_entries` rather than stored, so it's always consistent
/// with the underlying data.
class FinanceBalanceScreen extends StatefulWidget {
  const FinanceBalanceScreen({super.key});

  @override
  State<FinanceBalanceScreen> createState() => _FinanceBalanceScreenState();
}

class _FinanceBalanceScreenState extends State<FinanceBalanceScreen> {
  final _orderRepo = OrderRepository();
  final _expenseRepo = ExpenseRepository();
  final _expenseGlRepo = ExpenseGlAccountRepository();
  final _pettyCashRepo = PettyCashRepository();

  int _totalIncome = 0;
  List<Expense> _expenses = [];
  List<ExpenseGlAccount> _expenseGlAccounts = [];
  List<PettyCashEntry> _pettyCashEntries = [];
  String? _bankName;
  String? _accountNumber;
  String? _accountHolder;
  bool _loading = true;
  String? _loadError;

  String get _restoId => context.read<AuthProvider>().restoId!;

  /// Kasir gets this screen too, but only to see the balances and write
  /// down what they spent out of the float. Topping Petty Cash up moves
  /// money out of income, and deleting rewrites the GL journal — both
  /// stay with Finance/Admin, and the database enforces it as well (see
  /// supabase/kasir_balance_access.sql), so hiding the controls here
  /// just avoids offering something that would fail.
  bool get _canManageFunds => !context.read<AuthProvider>().isKasir;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final restoId = _restoId;
      final results = await Future.wait([
        _orderRepo.watchAll(restoId).first,
        _expenseRepo.getForResto(restoId),
        _expenseGlRepo.getForResto(restoId),
        _pettyCashRepo.getForResto(restoId),
        Supabase.instance.client.from('settings').select().eq('resto_id', restoId).limit(1),
      ]);
      if (!mounted) return;
      final orders = (results[0] as List<CustomerOrder>)
          .where((o) => o.paymentStatus == OrderPaymentStatus.paid);
      final settingsRows = results[4] as List<Map<String, dynamic>>;
      final settings = settingsRows.isNotEmpty ? settingsRows.first : null;
      setState(() {
        _totalIncome = orders.fold(0, (sum, o) => sum + o.total);
        _expenses = results[1] as List<Expense>;
        _expenseGlAccounts = results[2] as List<ExpenseGlAccount>;
        _pettyCashEntries = results[3] as List<PettyCashEntry>;
        _bankName = settings?['bank_name'] as String?;
        _accountNumber = settings?['account_number'] as String?;
        _accountHolder = settings?['account_holder'] as String?;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadError = '$e';
        _loading = false;
      });
    }
  }

  int get _expenseBalance => _expenses.fold(0, (sum, e) => sum + e.amount);

  int get _pettyCashWithdrawnFromIncome => _pettyCashEntries
      .where((e) => e.source == PettyCashSource.incomeWithdrawal)
      .fold(0, (sum, e) => sum + e.amount);

  int get _pettyCashToppedUp => _pettyCashEntries.fold(0, (sum, e) => sum + e.amount);

  /// Income only ever loses money by being withdrawn into Petty Cash —
  /// spending itself never comes straight out of it.
  int get _incomeBalance => _totalIncome - _pettyCashWithdrawnFromIncome;

  /// Every expense is paid from Petty Cash, so this bucket is shown net
  /// of them — which is why the total below just adds the two rather than
  /// subtracting expenses again (that would double-count them).
  int get _pettyCashBalance => _pettyCashToppedUp - _expenseBalance;

  int get _totalBalance => _incomeBalance + _pettyCashBalance;

  List<_DayGroup<Expense>> _groupByDay(List<Expense> items) {
    final byDay = <DateTime, List<Expense>>{};
    for (final e in items) {
      final wib = e.createdAt.toWib();
      final day = DateTime(wib.year, wib.month, wib.day);
      byDay.putIfAbsent(day, () => []).add(e);
    }
    final days = byDay.keys.toList()..sort((a, b) => b.compareTo(a));
    return days.map((d) => _DayGroup(d, byDay[d]!, byDay[d]!.fold(0, (s, e) => s + e.amount))).toList();
  }

  List<_DayGroup<PettyCashEntry>> _groupPettyCashByDay() {
    final byDay = <DateTime, List<PettyCashEntry>>{};
    for (final e in _pettyCashEntries) {
      final wib = e.createdAt.toWib();
      final day = DateTime(wib.year, wib.month, wib.day);
      byDay.putIfAbsent(day, () => []).add(e);
    }
    final days = byDay.keys.toList()..sort((a, b) => b.compareTo(a));
    return days.map((d) => _DayGroup(d, byDay[d]!, byDay[d]!.fold(0, (s, e) => s + e.amount))).toList();
  }

  Future<void> _addExpense() async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => _AddExpenseDialog(
        restoId: _restoId,
        glAccounts: _expenseGlAccounts,
        availablePettyCash: _pettyCashBalance,
      ),
    );
    if (saved == true) _load();
  }

  Future<void> _deleteExpense(Expense e) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Hapus pengeluaran?'),
        content: Text(
          '${e.description}\n\n'
          'Jurnal GL-nya tidak dihapus — akan dicatat sebagai baris pembatalan.',
        ),
        actionsAlignment: MainAxisAlignment.center,
        actions: [
          DialogActions(
            confirmLabel: 'Hapus',
            destructive: true,
            onConfirm: () => Navigator.pop(context, true),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    await _expenseRepo.delete(e.id);
    _load();
  }

  Future<void> _addPettyCash() async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => _AddPettyCashDialog(restoId: _restoId, availableIncome: _incomeBalance),
    );
    if (saved == true) _load();
  }

  Future<void> _deletePettyCashEntry(PettyCashEntry e) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Hapus entri Petty Cash?'),
        content: Text(
          '${kPettyCashSourceLabels[e.source]}'
          '${e.description != null && e.description!.isNotEmpty ? '\n${e.description}' : ''}'
          '\n\nJurnal GL-nya tidak dihapus — akan dicatat sebagai baris pembatalan.',
        ),
        actionsAlignment: MainAxisAlignment.center,
        actions: [
          DialogActions(
            confirmLabel: 'Hapus',
            destructive: true,
            onConfirm: () => Navigator.pop(context, true),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    await _pettyCashRepo.delete(e.id);
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final currency = NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0);

    return Scaffold(
      appBar: AppBar(title: const Text('Saldo & Pengeluaran')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _loadError != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.error_outline, size: 48, color: Colors.red),
                        const SizedBox(height: 12),
                        Text('Gagal memuat data:\n$_loadError', textAlign: TextAlign.center),
                        const SizedBox(height: 16),
                        FilledButton(onPressed: _load, child: const Text('Coba Lagi')),
                      ],
                    ),
                  ),
                )
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
                            colors: _totalBalance >= 0
                                ? [const Color(0xFF10B981), const Color(0xFF0F766E)]
                                : [const Color(0xFFEF4444), const Color(0xFFB91C1C)],
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: (_totalBalance >= 0
                                      ? const Color(0xFF10B981)
                                      : const Color(0xFFEF4444))
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
                                  Text('Saldo Total',
                                      style: TextStyle(color: Colors.white.withOpacity(0.85))),
                                ],
                              ),
                              const SizedBox(height: 6),
                              Text(
                                currency.format(_totalBalance),
                                style: const TextStyle(
                                    fontSize: 28, fontWeight: FontWeight.bold, color: Colors.white),
                              ),
                              Divider(height: 24, color: Colors.white.withOpacity(0.3)),
                              Text(
                                'Penghasilan + Petty Cash (pengeluaran sudah dikurangi)',
                                style: TextStyle(color: Colors.white.withOpacity(0.75), fontSize: 12),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: _BalanceMiniCard(
                              icon: Icons.trending_up,
                              label: 'Penghasilan',
                              value: currency.format(_incomeBalance),
                              color: const Color(0xFF10B981),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: _BalanceMiniCard(
                              icon: Icons.savings_outlined,
                              label: 'Petty Cash',
                              value: currency.format(_pettyCashBalance),
                              color: const Color(0xFF6366F1),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: _BalanceMiniCard(
                              icon: Icons.trending_down,
                              label: 'Pengeluaran',
                              value: '- ${currency.format(_expenseBalance)}',
                              color: const Color(0xFFEF4444),
                            ),
                          ),
                        ],
                      ),
                      if (_bankName != null &&
                          _bankName!.isNotEmpty &&
                          _accountNumber != null &&
                          _accountNumber!.isNotEmpty) ...[
                        const SizedBox(height: 20),
                        const Text('Rekening Bank', style: TextStyle(fontWeight: FontWeight.bold)),
                        const SizedBox(height: 8),
                        Card(
                          child: ListTile(
                            leading: CircleAvatar(
                              backgroundColor: const Color(0xFFEC4899).withOpacity(0.12),
                              child: const Icon(Icons.account_balance_outlined, color: Color(0xFFEC4899)),
                            ),
                            title: Text(_bankName!, style: const TextStyle(fontWeight: FontWeight.bold)),
                            subtitle: Text(
                              '$_accountNumber'
                              '${_accountHolder != null && _accountHolder!.isNotEmpty ? '\na.n. $_accountHolder' : ''}',
                            ),
                            isThreeLine: _accountHolder != null && _accountHolder!.isNotEmpty,
                          ),
                        ),
                      ],
                      const SizedBox(height: 24),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('Petty Cash', style: TextStyle(fontWeight: FontWeight.bold)),
                          if (_canManageFunds)
                            _PillButton(
                              icon: Icons.add_circle_outline,
                              label: 'Top Up',
                              color: const Color(0xFF6366F1),
                              onTap: _addPettyCash,
                            ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      if (_pettyCashEntries.isEmpty)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 16),
                          child: Text('Belum ada Petty Cash tercatat.', style: TextStyle(color: Colors.grey)),
                        )
                      else
                        ..._groupPettyCashByDay().map((group) {
                          return Card(
                            margin: const EdgeInsets.only(bottom: 8),
                            clipBehavior: Clip.antiAlias,
                            child: ExpansionTile(
                              title: Text(DateFormat('EEEE, dd MMM yyyy', 'id_ID').format(group.day),
                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                              subtitle: Text('+ ${currency.format(group.total)}',
                                  style: const TextStyle(color: Color(0xFF6366F1), fontWeight: FontWeight.w600)),
                              childrenPadding: const EdgeInsets.only(bottom: 4),
                              children: group.items
                                  .map((e) => ListTile(
                                        dense: true,
                                        leading: const Icon(Icons.savings_outlined),
                                        title: Text(kPettyCashSourceLabels[e.source]!),
                                        subtitle: Text(
                                          '${DateFormat('HH:mm').format(e.createdAt.toWib())} • ${e.createdBy}'
                                          '${e.description != null && e.description!.isNotEmpty ? ' • ${e.description}' : ''}',
                                        ),
                                        trailing: Text('+ ${currency.format(e.amount)}',
                                            style: const TextStyle(
                                                color: Color(0xFF6366F1), fontWeight: FontWeight.w600)),
                                        onLongPress:
                                            _canManageFunds ? () => _deletePettyCashEntry(e) : null,
                                      ))
                                  .toList(),
                            ),
                          );
                        }),
                      const SizedBox(height: 20),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('Riwayat Pengeluaran',
                              style: TextStyle(fontWeight: FontWeight.bold)),
                          _PillButton(
                            icon: Icons.remove_circle_outline,
                            label: 'Catat',
                            color: const Color(0xFFEF4444),
                            onTap: _addExpense,
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      if (_expenses.isEmpty)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 16),
                          child: Text('Belum ada pengeluaran tercatat.', style: TextStyle(color: Colors.grey)),
                        )
                      else
                        ..._groupByDay(_expenses).map((group) {
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
                              children: group.items
                                  .map((e) => ListTile(
                                        dense: true,
                                        leading: e.receiptBase64 != null
                                            ? _ReceiptThumb(base64Image: e.receiptBase64!)
                                            : const Icon(Icons.receipt_long_outlined),
                                        title: Text(e.description),
                                        subtitle: Text(
                                          '${DateFormat('HH:mm').format(e.createdAt.toWib())} • ${e.createdBy}'
                                          '${e.glCode != null ? ' • GL ${e.glCode}' : ''}'
                                          '${e.receiptBase64 != null ? ' • ada bukti' : ''}',
                                        ),
                                        trailing: Text('- ${currency.format(e.amount)}',
                                            style: const TextStyle(color: Colors.red, fontWeight: FontWeight.w600)),
                                        // Tapping opens the receipt when there
                                        // is one; deleting stays on long-press
                                        // either way.
                                        onTap: e.receiptBase64 == null
                                            ? null
                                            : () => Navigator.of(context).push(
                                                  MaterialPageRoute(
                                                    builder: (_) => _ReceiptViewer(
                                                      base64Image: e.receiptBase64!,
                                                      description: e.description,
                                                    ),
                                                  ),
                                                ),
                                        onLongPress:
                                            _canManageFunds ? () => _deleteExpense(e) : null,
                                      ))
                                  .toList(),
                            ),
                          );
                        }),
                    ],
                  ),
                ),
    );
  }
}

/// Small solid pill sitting beside a section heading — the action that
/// belongs to that section. Replaces a floating action button, which
/// covered the last rows of whatever list it hovered over.
class _PillButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _PillButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: color,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 16, color: Colors.white),
              const SizedBox(width: 6),
              Text(label,
                  style: const TextStyle(
                      color: Colors.white, fontWeight: FontWeight.w600, fontSize: 13)),
            ],
          ),
        ),
      ),
    );
  }
}

class _BalanceMiniCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;

  const _BalanceMiniCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(height: 6),
          Text(label, style: TextStyle(fontSize: 11, color: color.withOpacity(0.85))),
          const SizedBox(height: 2),
          Text(
            value,
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: color),
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

class _ReceiptThumb extends StatelessWidget {
  final String base64Image;

  const _ReceiptThumb({required this.base64Image});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: Image.memory(
        base64Decode(base64Image),
        width: 40,
        height: 40,
        fit: BoxFit.cover,
        // A corrupt blob would otherwise throw mid-paint and take the
        // whole expense list down with it.
        errorBuilder: (_, __, ___) => const Icon(Icons.broken_image_outlined),
      ),
    );
  }
}

/// Small circular button floated over the receipt thumbnail — a plain
/// IconButton would be invisible against a photo.
class _ReceiptAction extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  const _ReceiptAction({required this.icon, required this.tooltip, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.black.withOpacity(0.55),
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(6),
            child: Icon(icon, size: 16, color: Colors.white),
          ),
        ),
      ),
    );
  }
}

/// Full-screen, zoomable look at a stored receipt.
class _ReceiptViewer extends StatelessWidget {
  final String base64Image;
  final String description;

  const _ReceiptViewer({required this.base64Image, required this.description});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(description, style: const TextStyle(fontSize: 15)),
      ),
      body: Center(
        child: InteractiveViewer(
          minScale: 0.5,
          maxScale: 5,
          child: Image.memory(
            base64Decode(base64Image),
            fit: BoxFit.contain,
            errorBuilder: (_, __, ___) => const Text(
              'Gambar tidak bisa ditampilkan.',
              style: TextStyle(color: Colors.white70),
            ),
          ),
        ),
      ),
    );
  }
}

class _DayGroup<T> {
  final DateTime day;
  final List<T> items;
  final int total;

  _DayGroup(this.day, this.items, this.total);
}

/// Records an expense, always drawn from the Petty Cash float — capped at
/// [availablePettyCash] so the balance can't go negative. Top up Petty
/// Cash first if there isn't enough in it.
class _AddExpenseDialog extends StatefulWidget {
  final String restoId;
  final List<ExpenseGlAccount> glAccounts;
  final int availablePettyCash;

  const _AddExpenseDialog({
    required this.restoId,
    required this.glAccounts,
    required this.availablePettyCash,
  });

  @override
  State<_AddExpenseDialog> createState() => _AddExpenseDialogState();
}

class _AddExpenseDialogState extends State<_AddExpenseDialog> {
  final _formKey = GlobalKey<FormState>();
  final _amountCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  String? _glCode;
  File? _receipt;
  final _picker = ImagePicker();
  final _repo = ExpenseRepository();
  bool _saving = false;

  @override
  void dispose() {
    _amountCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  /// Receipts are mostly photographed on the spot, so the camera is
  /// offered alongside the gallery. Kept at 900px/70% — big enough that
  /// the nota's numbers stay readable, small enough that the base64 blob
  /// doesn't bloat the row (product photos use the same approach at a
  /// smaller size, since those don't need to be legible as text).
  Future<void> _pickReceipt(ImageSource source) async {
    // mobile_scanner declares android.permission.CAMERA, which makes
    // Android refuse the capture intent outright unless it's been
    // granted — and image_picker doesn't ask for it. A Finance user has
    // no reason to have hit the QR scanner that would have.
    if (source == ImageSource.camera) {
      final status = await Permission.camera.request();
      if (!mounted) return;
      if (!status.isGranted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Izin kamera ditolak. Pakai galeri, atau aktifkan lewat Pengaturan.'),
            action: status.isPermanentlyDenied
                ? const SnackBarAction(label: 'Pengaturan', onPressed: openAppSettings)
                : null,
          ),
        );
        return;
      }
    }

    try {
      final picked = await _picker.pickImage(
        source: source,
        maxWidth: 900,
        imageQuality: 70,
      );
      if (picked == null || !mounted) return;
      setState(() => _receipt = File(picked.path));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Gagal mengambil gambar: $e')),
      );
    }
  }

  Future<void> _chooseReceiptSource() async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('Ambil Foto'),
              onTap: () => Navigator.pop(context, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Pilih dari Galeri'),
              onTap: () => Navigator.pop(context, ImageSource.gallery),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (source == null) return;
    await _pickReceipt(source);
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final auth = context.read<AuthProvider>();
    setState(() => _saving = true);
    try {
      String? receiptBase64;
      if (_receipt != null) {
        receiptBase64 = base64Encode(await _receipt!.readAsBytes());
      }
      await _repo.create(Expense(
        id: '',
        restoId: widget.restoId,
        amount: parseRupiah(_amountCtrl.text)!,
        description: _descCtrl.text.trim(),
        glCode: _glCode,
        receiptBase64: receiptBase64,
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
    final currency = NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0);
    const accentColor = Color(0xFF6366F1); // Petty Cash's colour throughout the app
    final noFunds = widget.availablePettyCash <= 0;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 24, 20, 12),
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: const Color(0xFFEF4444).withOpacity(0.12),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.remove_circle_outline, color: Color(0xFFEF4444)),
                    ),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Catat Pengeluaran',
                              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17)),
                          Text('Uang keluar dari saldo resto',
                              style: TextStyle(fontSize: 12, color: Colors.grey)),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: noFunds
                        ? Colors.orange.withOpacity(0.08)
                        : accentColor.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                        color: noFunds
                            ? Colors.orange.withOpacity(0.3)
                            : accentColor.withOpacity(0.2)),
                  ),
                  child: Row(
                    children: [
                      Icon(noFunds ? Icons.warning_amber_outlined : Icons.savings_outlined,
                          size: 15, color: noFunds ? Colors.orange.shade800 : accentColor),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          noFunds
                              ? 'Saldo Petty Cash kosong — top up dulu sebelum mencatat pengeluaran.'
                              : 'Dipotong dari Petty Cash • tersedia ${currency.format(widget.availablePettyCash)}',
                          style: TextStyle(
                            fontSize: 12.5,
                            color: noFunds ? Colors.orange.shade800 : accentColor,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _amountCtrl,
                  decoration: const InputDecoration(labelText: 'Jumlah', prefixText: 'Rp '),
                  keyboardType: TextInputType.number,
                  inputFormatters: [ThousandsInputFormatter()],
                  style: const TextStyle(fontWeight: FontWeight.bold),
                  validator: (v) {
                    final n = parseRupiah(v ?? '');
                    if (n == null || n <= 0) return 'Wajib diisi, angka > 0';
                    if (n > widget.availablePettyCash) {
                      return 'Melebihi saldo Petty Cash yang tersedia';
                    }
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
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'GL Account (opsional)'),
                    items: widget.glAccounts
                        .map((g) => DropdownMenuItem(
                              value: g.glCode,
                              child: Text('${g.glCode} — ${g.glName}',
                                  overflow: TextOverflow.ellipsis),
                            ))
                        .toList(),
                    onChanged: (v) => setState(() => _glCode = v),
                  ),
                ],
                const SizedBox(height: 14),
                Text('Bukti Pengeluaran (opsional)',
                    style: TextStyle(
                        fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey.shade700)),
                const SizedBox(height: 8),
                if (_receipt == null)
                  OutlinedButton.icon(
                    onPressed: _chooseReceiptSource,
                    icon: const Icon(Icons.add_a_photo_outlined, size: 18),
                    label: const Text('Lampirkan Foto Nota'),
                    style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(46)),
                  )
                else
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Stack(
                      children: [
                        Image.file(
                          _receipt!,
                          width: double.infinity,
                          height: 150,
                          fit: BoxFit.cover,
                        ),
                        Positioned(
                          top: 6,
                          right: 6,
                          child: Row(
                            children: [
                              _ReceiptAction(
                                icon: Icons.edit_outlined,
                                tooltip: 'Ganti foto',
                                onTap: _chooseReceiptSource,
                              ),
                              const SizedBox(width: 6),
                              _ReceiptAction(
                                icon: Icons.close,
                                tooltip: 'Hapus foto',
                                onTap: () => setState(() => _receipt = null),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.of(context).pop(false),
                        child: const Text('Batal'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton(
                        style: FilledButton.styleFrom(backgroundColor: accentColor),
                        onPressed: _saving ? null : _save,
                        child: _saving
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: Colors.white))
                            : const Text('Simpan'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Funds Petty Cash either by withdrawing from Saldo Penghasilan (capped
/// at [availableIncome] so it can't go negative) or a manual top-up entry
/// (needed on day one, before any income exists to withdraw from).
class _AddPettyCashDialog extends StatefulWidget {
  final String restoId;
  final int availableIncome;

  const _AddPettyCashDialog({required this.restoId, required this.availableIncome});

  @override
  State<_AddPettyCashDialog> createState() => _AddPettyCashDialogState();
}

class _AddPettyCashDialogState extends State<_AddPettyCashDialog> {
  final _formKey = GlobalKey<FormState>();
  final _amountCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  PettyCashSource _source = PettyCashSource.incomeWithdrawal;
  final _repo = PettyCashRepository();
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
      await _repo.create(PettyCashEntry(
        id: '',
        restoId: widget.restoId,
        amount: parseRupiah(_amountCtrl.text)!,
        source: _source,
        description: _descCtrl.text.trim().isEmpty ? null : _descCtrl.text.trim(),
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
    final currency = NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0);
    final isWithdrawal = _source == PettyCashSource.incomeWithdrawal;
    final accentColor = isWithdrawal ? const Color(0xFF10B981) : const Color(0xFF6366F1);

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 24, 20, 12),
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: const Color(0xFF6366F1).withOpacity(0.12),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.savings_outlined, color: Color(0xFF6366F1)),
                    ),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Top Up Petty Cash',
                              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17)),
                          Text('Tambah saldo kas kecil',
                              style: TextStyle(fontSize: 12, color: Colors.grey)),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF4F5FB),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: _SourceTab(
                          icon: Icons.trending_up,
                          label: 'Dari Penghasilan',
                          selected: isWithdrawal,
                          color: const Color(0xFF10B981),
                          onTap: () => setState(() => _source = PettyCashSource.incomeWithdrawal),
                        ),
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: _SourceTab(
                          icon: Icons.edit_outlined,
                          label: 'Manual',
                          selected: !isWithdrawal,
                          color: const Color(0xFF6366F1),
                          onTap: () => setState(() => _source = PettyCashSource.manual),
                        ),
                      ),
                    ],
                  ),
                ),
                if (isWithdrawal) ...[
                  const SizedBox(height: 12),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                      color: accentColor.withOpacity(0.08),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: accentColor.withOpacity(0.2)),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.info_outline, size: 15, color: accentColor),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Saldo Penghasilan tersedia: ${currency.format(widget.availableIncome)}',
                            style: TextStyle(
                                fontSize: 12.5, color: accentColor, fontWeight: FontWeight.w600),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                TextFormField(
                  controller: _amountCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Jumlah',
                    prefixText: 'Rp ',
                  ),
                  keyboardType: TextInputType.number,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) return 'Wajib diisi';
                    final n = int.tryParse(v.trim());
                    if (n == null || n <= 0) return 'Harus angka > 0';
                    if (isWithdrawal && n > widget.availableIncome) {
                      return 'Melebihi Saldo Penghasilan yang tersedia';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _descCtrl,
                  decoration: const InputDecoration(labelText: 'Catatan (opsional)'),
                  maxLines: 2,
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.of(context).pop(false),
                        child: const Text('Batal'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton(
                        style: FilledButton.styleFrom(backgroundColor: accentColor),
                        onPressed: _saving ? null : _save,
                        child: _saving
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                            : const Text('Simpan'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SourceTab extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final Color color;
  final VoidCallback onTap;

  const _SourceTab({
    required this.icon,
    required this.label,
    required this.selected,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? color : Colors.transparent,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 18, color: selected ? Colors.white : Colors.grey.shade500),
              const SizedBox(height: 3),
              Text(
                label,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                  color: selected ? Colors.white : Colors.grey.shade600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
