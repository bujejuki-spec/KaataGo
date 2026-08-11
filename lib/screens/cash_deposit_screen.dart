import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../db/cash_deposit_repository.dart';
import '../db/order_repository.dart';
import '../db/petty_cash_repository.dart';
import '../models/cash_deposit.dart';
import '../models/customer_order.dart';
import '../models/petty_cash_entry.dart';
import '../providers/auth_provider.dart';
import '../theme.dart';
import '../utils/id_time.dart';
import '../utils/photo_picker.dart';
import '../utils/rupiah_input.dart';
import '../widgets/dialog_actions.dart';

/// Menyetorkan uang tunai dari laci kasir ke rekening resto.
///
/// Uang tunai adalah satu-satunya saldo yang benar-benar berbentuk
/// lembaran dan bisa hilang, jadi layar ini menjawab satu pertanyaan
/// lebih dulu — berapa yang seharusnya ada di laci sekarang — lalu
/// menyediakan cara mencatat penyetorannya berikut bukti fotonya.
///
/// Setoran memindahkan uang, bukan menghabiskannya: GL Cash berkurang,
/// GL Total Saldo bertambah, dan saldo total resto tidak berubah.
class CashDepositScreen extends StatefulWidget {
  const CashDepositScreen({super.key});

  @override
  State<CashDepositScreen> createState() => _CashDepositScreenState();
}

class _CashDepositScreenState extends State<CashDepositScreen> {
  final _depositRepo = CashDepositRepository();
  final _orderRepo = OrderRepository();
  final _pettyCashRepo = PettyCashRepository();

  int _cashIncome = 0;
  int _pettyCashFromCash = 0;
  List<CashDeposit> _deposits = [];
  bool _loading = true;
  String? _loadError;

  String get _restoId => context.read<AuthProvider>().restoId!;

  /// Membatalkan setoran menulis ulang jurnal, jadi itu tetap urusan
  /// Finance/Admin — dan database menegakkannya juga (lihat
  /// supabase/cash_deposit.sql), sehingga menyembunyikannya di sini
  /// hanya menghindari menawarkan sesuatu yang pasti gagal.
  bool get _canDelete => !context.read<AuthProvider>().isKasir;

  int get _deposited => _deposits.fold(0, (sum, d) => sum + d.amount);

  /// Yang seharusnya masih ada di laci.
  int get _cashOnHand => _cashIncome - _deposited - _pettyCashFromCash;

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
        _depositRepo.getForResto(restoId),
        _pettyCashRepo.getForResto(restoId),
      ]);
      if (!mounted) return;
      final orders = (results[0] as List<CustomerOrder>)
          .where((o) => o.paymentStatus == OrderPaymentStatus.paid);
      final pettyCash = results[2] as List<PettyCashEntry>;
      setState(() {
        _cashIncome = orders
            .where((o) => o.paymentMethod == 'cash')
            .fold(0, (sum, o) => sum + o.total);
        _deposits = results[1] as List<CashDeposit>;
        _pettyCashFromCash = pettyCash
            .where((e) => e.source == PettyCashSource.cashWithdrawal)
            .fold(0, (sum, e) => sum + e.amount);
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

  Future<void> _addDeposit() async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => _AddDepositDialog(restoId: _restoId, cashOnHand: _cashOnHand),
    );
    if (saved == true) _load();
  }

  Future<void> _deleteDeposit(CashDeposit d) async {
    final currency = NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0);
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Batalkan setoran?'),
        content: Text(
          '${currency.format(d.amount)}\n\n'
          'Jurnal GL-nya tidak dihapus — akan dicatat sebagai baris pembatalan, '
          'dan uangnya kembali dihitung sebagai saldo tunai di laci.',
        ),
        actionsAlignment: MainAxisAlignment.center,
        actions: [
          DialogActions(
            confirmLabel: 'Batalkan',
            destructive: true,
            onConfirm: () => Navigator.pop(context, true),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    try {
      await _depositRepo.delete(d.id);
      _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Gagal membatalkan: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final currency = NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0);
    final dateFmt = DateFormat('d MMM yyyy, HH:mm', 'id_ID');

    return Scaffold(
      appBar: AppBar(title: const Text('Setor Saldo Cash')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _loadError != null
              ? _ErrorState(message: _loadError!, onRetry: _load)
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
                    children: [
                      _CashOnHandCard(
                        cashOnHand: _cashOnHand,
                        cashIncome: _cashIncome,
                        deposited: _deposited,
                        toPettyCash: _pettyCashFromCash,
                        currency: currency,
                      ),
                      const SizedBox(height: 14),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          icon: const Icon(Icons.account_balance_outlined),
                          label: const Text('Setor ke Rekening Resto'),
                          style: FilledButton.styleFrom(
                            minimumSize: const Size.fromHeight(50),
                          ),
                          onPressed: _cashOnHand > 0 ? _addDeposit : null,
                        ),
                      ),
                      if (_cashOnHand <= 0) ...[
                        const SizedBox(height: 7),
                        Text(
                          _cashIncome == 0
                              ? 'Belum ada pembayaran tunai yang masuk.'
                              : 'Semua uang tunai sudah disetor.',
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                        ),
                      ],
                      const SizedBox(height: 24),
                      Row(
                        children: [
                          const Text('Riwayat Setoran',
                              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                          const Spacer(),
                          Text('${_deposits.length} setoran',
                              style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                        ],
                      ),
                      const SizedBox(height: 10),
                      if (_deposits.isEmpty)
                        Container(
                          padding: const EdgeInsets.symmetric(vertical: 30),
                          alignment: Alignment.center,
                          child: Text(
                            'Belum ada setoran dicatat.',
                            style: TextStyle(color: Colors.grey.shade500),
                          ),
                        )
                      else
                        for (final d in _deposits)
                          _DepositTile(
                            deposit: d,
                            currency: currency,
                            dateFmt: dateFmt,
                            onDelete: _canDelete ? () => _deleteDeposit(d) : null,
                          ),
                    ],
                  ),
                ),
    );
  }
}

class _CashOnHandCard extends StatelessWidget {
  final int cashOnHand;
  final int cashIncome;
  final int deposited;
  final int toPettyCash;
  final NumberFormat currency;

  const _CashOnHandCard({
    required this.cashOnHand,
    required this.cashIncome,
    required this.deposited,
    required this.toPettyCash,
    required this.currency,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF0EA5E9), Color(0xFF0369A1)],
        ),
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0EA5E9).withOpacity(0.28),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.payments_outlined, size: 18, color: Colors.white.withOpacity(0.85)),
              const SizedBox(width: 6),
              Text('Tunai di Laci',
                  style: TextStyle(color: Colors.white.withOpacity(0.85))),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            currency.format(cashOnHand),
            style: const TextStyle(
                fontSize: 28, fontWeight: FontWeight.bold, color: Colors.white),
          ),
          Divider(height: 24, color: Colors.white.withOpacity(0.3)),
          _row('Pemasukan tunai', currency.format(cashIncome)),
          if (deposited > 0) _row('Sudah disetor', '- ${currency.format(deposited)}'),
          if (toPettyCash > 0) _row('Dipindah ke Petty Cash', '- ${currency.format(toPettyCash)}'),
        ],
      ),
    );
  }

  Widget _row(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 3),
      child: Row(
        children: [
          Expanded(
            child: Text(label,
                style: TextStyle(color: Colors.white.withOpacity(0.8), fontSize: 12.5)),
          ),
          Text(value,
              style: TextStyle(
                  color: Colors.white.withOpacity(0.95),
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

class _DepositTile extends StatelessWidget {
  final CashDeposit deposit;
  final NumberFormat currency;
  final DateFormat dateFmt;
  final VoidCallback? onDelete;

  const _DepositTile({
    required this.deposit,
    required this.currency,
    required this.dateFmt,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey.shade200),
      ),
      padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(currency.format(deposit.amount),
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15.5)),
                const SizedBox(height: 2),
                Text(dateFmt.format(deposit.createdAt.toWib()),
                    style: TextStyle(fontSize: 11.5, color: Colors.grey.shade600)),
                Text('Oleh ${deposit.createdBy}',
                    style: TextStyle(fontSize: 11.5, color: Colors.grey.shade600)),
                if (deposit.note != null && deposit.note!.trim().isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(deposit.note!,
                      style: TextStyle(
                          fontSize: 12,
                          fontStyle: FontStyle.italic,
                          color: Colors.grey.shade700)),
                ],
                if (deposit.hasProof) ...[
                  const SizedBox(height: 8),
                  GestureDetector(
                    onTap: () => _openProof(context),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(9),
                      child: Image.memory(
                        base64Decode(deposit.proofBase64!),
                        width: 78,
                        height: 78,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (onDelete != null)
            IconButton(
              icon: const Icon(Icons.close, size: 18),
              color: Colors.grey.shade500,
              tooltip: 'Batalkan setoran',
              onPressed: onDelete,
            ),
        ],
      ),
    );
  }

  void _openProof(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (_) => Dialog(
        insetPadding: const EdgeInsets.all(16),
        child: InteractiveViewer(
          child: Image.memory(base64Decode(deposit.proofBase64!)),
        ),
      ),
    );
  }
}

class _AddDepositDialog extends StatefulWidget {
  final String restoId;
  final int cashOnHand;

  const _AddDepositDialog({required this.restoId, required this.cashOnHand});

  @override
  State<_AddDepositDialog> createState() => _AddDepositDialogState();
}

class _AddDepositDialogState extends State<_AddDepositDialog> {
  final _formKey = GlobalKey<FormState>();
  final _amountCtrl = TextEditingController();
  final _noteCtrl = TextEditingController();
  final _repo = CashDepositRepository();
  File? _proof;
  bool _saving = false;

  @override
  void dispose() {
    _amountCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final auth = context.read<AuthProvider>();
    setState(() => _saving = true);
    try {
      final proofBase64 = _proof == null ? null : base64Encode(await _proof!.readAsBytes());
      await _repo.create(CashDeposit(
        id: '',
        restoId: widget.restoId,
        amount: parseRupiah(_amountCtrl.text)!,
        proofBase64: proofBase64,
        note: _noteCtrl.text.trim().isEmpty ? null : _noteCtrl.text.trim(),
        createdBy: auth.user?.email ?? 'Kasir',
        createdAt: DateTime.now(),
      ));
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Gagal menyimpan: $e')));
      setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final currency = NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0);

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.all(20),
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
                        color: const Color(0xFF0EA5E9).withOpacity(0.12),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.account_balance_outlined, color: Color(0xFF0EA5E9)),
                    ),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Setor Saldo Cash',
                              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17)),
                          Text('Tunai di laci ke rekening resto',
                              style: TextStyle(fontSize: 12, color: Colors.grey)),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0EA5E9).withOpacity(0.08),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFF0EA5E9).withOpacity(0.2)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.info_outline, size: 15, color: Color(0xFF0369A1)),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Tunai di laci: ${currency.format(widget.cashOnHand)}',
                          style: const TextStyle(
                            fontSize: 12.5,
                            color: Color(0xFF0369A1),
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
                  decoration: const InputDecoration(labelText: 'Jumlah Setoran', prefixText: 'Rp '),
                  keyboardType: TextInputType.number,
                  inputFormatters: [ThousandsInputFormatter()],
                  style: const TextStyle(fontWeight: FontWeight.bold),
                  autofocus: true,
                  validator: (v) {
                    final n = parseRupiah(v ?? '');
                    if (n == null || n <= 0) return 'Wajib diisi, angka > 0';
                    // Menyetor lebih dari yang ada di laci berarti salah
                    // hitung di suatu tempat — dan kalau dibiarkan, saldo
                    // tunainya jadi minus, yang tidak berarti apa-apa.
                    if (n > widget.cashOnHand) {
                      return 'Melebihi tunai di laci '
                          '(maks ${currency.format(widget.cashOnHand)})';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _noteCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Catatan (opsional)',
                    hintText: 'mis. setor ke BCA a.n. Kaata Resto',
                  ),
                  maxLines: 2,
                ),
                const SizedBox(height: 14),
                Text('Bukti Setor / Transfer',
                    style: TextStyle(
                        fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey.shade700)),
                const SizedBox(height: 8),
                if (_proof == null)
                  OutlinedButton.icon(
                    onPressed: () async {
                      final picked = await pickProofPhoto(context);
                      if (picked != null && mounted) setState(() => _proof = picked);
                    },
                    icon: const Icon(Icons.add_a_photo_outlined, size: 18),
                    label: const Text('Lampirkan Bukti'),
                    style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(46)),
                  )
                else
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Stack(
                      children: [
                        Image.file(_proof!, width: double.infinity, height: 150, fit: BoxFit.cover),
                        Positioned(
                          top: 6,
                          right: 6,
                          child: Material(
                            color: Colors.black54,
                            shape: const CircleBorder(),
                            child: InkWell(
                              customBorder: const CircleBorder(),
                              onTap: () => setState(() => _proof = null),
                              child: const Padding(
                                padding: EdgeInsets.all(6),
                                child: Icon(Icons.close, size: 16, color: Colors.white),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                const SizedBox(height: 20),
                DialogActions(
                  confirmLabel: 'Simpan Setoran',
                  busy: _saving,
                  onConfirm: _save,
                  onCancel: () => Navigator.of(context).pop(false),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _ErrorState({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cloud_off, size: 40, color: Colors.grey.shade400),
            const SizedBox(height: 12),
            Text('Gagal memuat data.\n$message',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey.shade600)),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('Coba Lagi'),
              style: OutlinedButton.styleFrom(foregroundColor: KaataTheme.brand),
            ),
          ],
        ),
      ),
    );
  }
}
