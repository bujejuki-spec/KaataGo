import '../utils/pesan_galat.dart';
import '../utils/field_rules.dart';
import '../models/bank_account.dart';
import '../db/bank_account_repository.dart';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../db/cash_deposit_repository.dart';
import '../db/cashier_shift_repository.dart';
import '../db/order_repository.dart';
import '../db/petty_cash_repository.dart';
import '../models/cash_deposit.dart';
import '../models/cash_variance.dart';
import '../models/customer_order.dart';
import '../models/petty_cash_entry.dart';
import '../utils/cash_balance.dart';
import '../providers/auth_provider.dart';
import '../theme.dart';
import '../utils/id_time.dart';
import '../utils/photo_picker.dart';
import '../utils/rupiah_input.dart';
import '../widgets/dialog_actions.dart';
import '../widgets/responsive.dart';
import '../widgets/app_toast.dart';
import '../widgets/required_label.dart';
import '../utils/lebar_web.dart';

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
  final _shiftRepo = CashierShiftRepository();

  int _cashIncome = 0;
  int _pettyCashFromCash = 0;
  List<CashDeposit> _deposits = [];
  List<PettyCashEntry> _pettyCash = const [];
  List<CashVariance> _selisih = const [];
  List<BankAccount> _rekening = const [];
  bool _loading = true;
  String? _loadError;

  String get _restoId => context.read<AuthProvider>().restoId!;

  /// Membatalkan setoran menulis ulang jurnal, jadi itu tetap urusan
  /// Finance/Admin — dan database menegakkannya juga (lihat
  /// supabase/cash_deposit.sql), sehingga menyembunyikannya di sini
  /// hanya menghindari menawarkan sesuatu yang pasti gagal.
  bool get _canDelete {
    final auth = context.read<AuthProvider>();
    return !auth.isKasir && !auth.isAdmin;
  }

  /// Menyetujui setoran adalah pemeriksaan atas pekerjaan kasir, jadi
  /// kasir tidak boleh menyetujui setorannya sendiri — kalau bisa,
  /// persetujuannya tidak berarti apa-apa. Database menegakkannya juga.
  bool get _canReview {
    final auth = context.read<AuthProvider>();
    return !auth.isKasir && !auth.isAdmin;
  }

  /// Setoran yang sudah keluar dari laci — termasuk yang masih menunggu
  /// persetujuan, karena uangnya memang sudah tidak ada di laci.
  int get _deposited => depositedFromDrawer(_deposits);

  /// Masih mengendap di GL Suspense: sudah disetor, belum diakui masuk
  /// kas resto.
  int get _pendingTotal => _deposits.where((d) => d.isPending).fold(0, (sum, d) => sum + d.amount);

  /// Yang seharusnya masih ada di laci.
  ///
  /// Dihitung [cashOnHand], bukan ditulis ulang di sini. Sebelumnya
  /// rumusnya disalin — pemasukan dikurangi setoran dikurangi petty cash
  /// — dan salinan itu tidak ikut berubah saat selisih shift mulai
  /// diperhitungkan. Hasilnya dua layar yang sama-sama mengaku menyebut
  /// "tunai di laci" menampilkan angka berbeda, dan tidak ada cara
  /// menebak yang mana yang benar dari layarnya saja. Persis penyakit
  /// yang dulu melahirkan berkas itu.
  int get _cashOnHand => cashOnHand(
        cashIncome: _cashIncome,
        deposits: _deposits,
        pettyCash: _pettyCash,
        selisih: _selisih,
      );

  /// Selisih shift yang menggeser isi laci, untuk ditulis di kartunya.
  ///
  /// Yang kurang mengurangi, yang lebih menambah — dan keduanya perlu
  /// terlihat, karena kasir yang menyetor isi laci membandingkan angka
  /// di layar dengan lembaran di tangannya.
  int get _selisihKurang => selisihBelumDibayar(_selisih);
  int get _selisihLebih => selisihLebihDiLaci(_selisih);


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
        _orderRepo.semua(restoId),
        _depositRepo.getForResto(restoId),
        _pettyCashRepo.getForResto(restoId),
        _shiftRepo.selisih(restoId),
      ]);
      // Dipisah dari Future.wait karena tipenya berbeda, dan gagalnya
      // tidak boleh menjatuhkan seluruh layar: tanpa rekening, setoran
      // masih bisa dicatat — cuma tujuannya yang belum tertulis.
      var rekening = <BankAccount>[];
      try {
        rekening = await BankAccountRepository().untukResto(restoId);
      } catch (_) {}
      if (!mounted) return;
      final orders = (results[0] as List<CustomerOrder>)
          .where((o) => o.paymentStatus == OrderPaymentStatus.paid);
      final pettyCash = results[2] as List<PettyCashEntry>;
      setState(() {
        _cashIncome =
            orders.where((o) => o.paymentMethod == 'cash').fold(0, (sum, o) => sum + o.total);
        _deposits = results[1] as List<CashDeposit>;
        _pettyCash = pettyCash;
        _selisih = results[3] as List<CashVariance>;
        _rekening = rekening;
        _pettyCashFromCash = pettyCashFromDrawer(pettyCash);
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

  Future<void> _addPickup() async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => _PickupDialog(
        restoId: _restoId,
        cashOnHand: _cashOnHand,
      ),
    );
    if (saved == true) _load();
  }

  Future<void> _addDeposit() async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => _AddDepositDialog(
        restoId: _restoId,
        cashOnHand: _cashOnHand,
        rekening: _rekening,
      ),
    );
    if (saved == true) _load();
  }

  /// Finance mengonfirmasi, bukan menyetujui: yang dia nyatakan adalah
  /// uangnya sudah benar-benar terlihat di rekening, bukan bahwa kasir
  /// boleh menyetor. Karena itu peringatannya menyebut saldo rekening —
  /// kesalahan yang paling mahal di sini adalah mengonfirmasi transfer
  /// yang nominalnya tidak sama.
  Future<void> _review(CashDeposit d, DepositStatus status) async {
    final approving = status == DepositStatus.approved;
    // Diambil sebelum dialog dibuka: sesudahnya context sudah melewati
    // await, dan pembacaan provider di titik itu tidak lagi terjamin.
    final reviewer = context.read<AuthProvider>().user?.email ?? 'Finance';
    final currency = NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0);
    final noteCtrl = TextEditingController();

    final confirm = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        icon: Icon(
          approving ? Icons.verified_outlined : Icons.block,
          size: 38,
          color: approving ? const Color(0xFF10B981) : Colors.red,
        ),
        title: Text(approving ? 'Konfirmasi setoran?' : 'Tolak setoran?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (approving) ...[
              Container(
                padding: const EdgeInsets.all(11),
                decoration: BoxDecoration(
                  color: const Color(0xFFF59E0B).withOpacity(0.10),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFFF59E0B).withOpacity(0.35)),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.warning_amber_rounded, size: 18, color: Color(0xFFB45309)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Pastikan nominal di Saldo Rekening kamu sudah sesuai '
                        'dengan nominal yang ditransfer: '
                        '${currency.format(d.amount)}.',
                        style: const TextStyle(fontSize: 12.5, color: Color(0xFF92400E)),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
            ],
            Text(
              approving
                  ? 'Setelah dikonfirmasi, ${currency.format(d.amount)} dipindah dari '
                      'GL Suspense ke GL Total Saldo dan statusnya menjadi Completed.'
                  : '${currency.format(d.amount)} akan dikembalikan dari GL Suspense '
                      'ke GL Cash, dan dihitung lagi sebagai tunai di laci.',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: noteCtrl,
              decoration: InputDecoration(
                labelText: approving ? 'Catatan (opsional)' : 'Alasan penolakan',
                isDense: true,
              ),
              maxLines: 2,
            ),
          ],
        ),
        actionsAlignment: MainAxisAlignment.center,
        actions: [
          DialogActions(
            confirmLabel: approving ? 'Konfirmasi' : 'Tolak',
            destructive: !approving,
            onConfirm: () => Navigator.pop(dialogContext, true),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    try {
      await _depositRepo.review(
        d.id,
        status: status,
        reviewedBy: reviewer,
        note: noteCtrl.text,
      );
      _load();
    } catch (e) {
      if (!mounted) return;
      showAppToast(context, 'Gagal memproses: $e', isError: true);
    }
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
      showAppToast(context, 'Gagal membatalkan: $e', isError: true);
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
                  child: ResponsiveCenter(
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
                      children: [
                        _CashOnHandCard(
                          cashOnHand: _cashOnHand,
                          cashIncome: _cashIncome,
                          deposited: _deposited,
                          toPettyCash: _pettyCashFromCash,
                          selisihKurang: _selisihKurang,
                          selisihLebih: _selisihLebih,
                          pending: _pendingTotal,
                          currency: currency,
                        ),
                        const SizedBox(height: 14),
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton.icon(
                            icon: const Icon(Icons.account_balance_outlined),
                            label: const Text('Setor ke Rekening Merchant'),
                            style: FilledButton.styleFrom(
                              minimumSize: const Size.fromHeight(50),
                            ),
                            onPressed: _cashOnHand > 0 ? _addDeposit : null,
                          ),
                        ),
                        const SizedBox(height: 9),
                        // Uangnya dijemput, bukan disetor sendiri. Yang
                        // terjadi pada lacinya sama — lembarannya keluar
                        // — jadi ia lewat jalur yang sama dan Saldo Cash
                        // ikut berkurang tanpa perlu diajari sumber baru.
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton.icon(
                            icon: const Icon(Icons.local_shipping_outlined),
                            label: const Text('Cash Pickup'),
                            style: OutlinedButton.styleFrom(
                              minimumSize: const Size.fromHeight(48),
                            ),
                            onPressed: _cashOnHand > 0 ? _addPickup : null,
                          ),
                        ),
                        if (_cashOnHand <= 0) ...[
                          const SizedBox(height: 7),
                          Text(
                            _cashIncome == 0
                                ? 'Belum ada pembayaran tunai yang masuk.'
                                : 'Semua uang tunai sudah disetor.',
                            textAlign: TextAlign.center,
                            style: TextStyle(fontSize: 12, color: KaataTheme.mutedOf(context)),
                          ),
                        ],
                        const SizedBox(height: 24),
                        Row(
                          children: [
                            const Text('Riwayat Setoran',
                                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                            const Spacer(),
                            Text('${_deposits.length} setoran',
                                style: TextStyle(fontSize: 12, color: KaataTheme.mutedOf(context))),
                          ],
                        ),
                        const SizedBox(height: 10),
                        if (_deposits.isEmpty)
                          Container(
                            padding: const EdgeInsets.symmetric(vertical: 30),
                            alignment: Alignment.center,
                            child: Text(
                              'Belum ada setoran dicatat.',
                              style: TextStyle(color: KaataTheme.mutedOf(context)),
                            ),
                          )
                        else
                          for (final d in _deposits)
                            _DepositTile(
                              deposit: d,
                              currency: currency,
                              dateFmt: dateFmt,
                              onDelete: _canDelete ? () => _deleteDeposit(d) : null,
                              onApprove: _canReview && d.isPending
                                  ? () => _review(d, DepositStatus.approved)
                                  : null,
                              onReject: _canReview && d.isPending
                                  ? () => _review(d, DepositStatus.rejected)
                                  : null,
                            ),
                      ],
                    ),
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
  final int selisihKurang;
  final int selisihLebih;
  final int pending;
  final NumberFormat currency;

  const _CashOnHandCard({
    required this.cashOnHand,
    required this.cashIncome,
    required this.deposited,
    required this.toPettyCash,
    required this.selisihKurang,
    required this.selisihLebih,
    required this.pending,
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
              Text('Tunai di Laci', style: TextStyle(color: Colors.white.withOpacity(0.85))),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            currency.format(cashOnHand),
            style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Colors.white),
          ),
          Divider(height: 24, color: Colors.white.withOpacity(0.3)),
          _row('Pemasukan tunai', currency.format(cashIncome)),
          if (deposited > 0) _row('Sudah disetor', '- ${currency.format(deposited)}'),
          if (toPettyCash > 0) _row('Dipindah ke Petty Cash', '- ${currency.format(toPettyCash)}'),
          // Rinciannya harus berjumlah sama dengan angka besar di atas.
          // Rincian yang tidak bertemu totalnya lebih buruk daripada
          // total yang salah: yang membacanya tahu ada yang keliru, tapi
          // tidak tahu di sebelah mana.
          if (selisihKurang > 0)
            _row('Selisih kurang shift', '- ${currency.format(selisihKurang)}'),
          if (selisihLebih > 0)
            _row('Selisih lebih shift', '+ ${currency.format(selisihLebih)}'),
          if (pending > 0) ...[
            const SizedBox(height: 4),
            _row('⏳ Menunggu approval Finance', currency.format(pending)),
          ],
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
            child:
                Text(label, style: TextStyle(color: Colors.white.withOpacity(0.8), fontSize: 12.5)),
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
  final VoidCallback? onApprove;
  final VoidCallback? onReject;

  const _DepositTile({
    required this.deposit,
    required this.currency,
    required this.dateFmt,
    this.onDelete,
    this.onApprove,
    this.onReject,
  });

  static const _statusColors = {
    DepositStatus.pending: Color(0xFFF59E0B),
    DepositStatus.approved: Color(0xFF10B981),
    DepositStatus.rejected: Color(0xFFEF4444),
  };

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: KaataTheme.surfaceOf(context),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: KaataTheme.softFillOf(context)),
      ),
      padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(currency.format(deposit.amount),
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15.5)),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: _statusColors[deposit.status]!.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(7),
                        border: Border.all(color: _statusColors[deposit.status]!.withOpacity(0.3)),
                      ),
                      child: Text(
                        kDepositStatusLabels[deposit.status]!,
                        style: TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.bold,
                          color: _statusColors[deposit.status],
                        ),
                      ),
                    ),
                    // Pickup ditandai, setoran biasa tidak. Yang membaca
                    // riwayat perlu tahu uangnya berpindah dengan cara
                    // apa — dibawa petugas atau disetor sendiri ke bank
                    // — karena yang ditanyakan saat ada selisih berbeda.
                    if (deposit.isPickup) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 7, vertical: 2),
                        decoration: BoxDecoration(
                          color: KaataTheme.softFillOf(context),
                          borderRadius: BorderRadius.circular(7),
                        ),
                        child: const Text('PICKUP',
                            style: TextStyle(
                                fontSize: 9.5, fontWeight: FontWeight.bold)),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                Text(dateFmt.format(deposit.createdAt.toWib()),
                    style: TextStyle(fontSize: 11.5, color: KaataTheme.mutedOf(context))),
                if (deposit.isPickup && deposit.pickedUpBy != null)
                  Text(
                    'Dijemput ${deposit.pickedUpBy}'
                    '${deposit.sealNumber == null ? '' : ' · Segel ${deposit.sealNumber}'}',
                    style: TextStyle(
                        fontSize: 12, color: KaataTheme.mutedOf(context)),
                  ),
                Text('Oleh ${deposit.createdBy}',
                    style: TextStyle(fontSize: 11.5, color: KaataTheme.mutedOf(context))),
                if (deposit.bankName != null)
                  Text(
                    '${deposit.bankName}'
                    '${deposit.accountNumber != null ? ' · ${deposit.accountNumber}' : ''}'
                    '${deposit.accountHolder != null ? ' · a.n. ${deposit.accountHolder}' : ''}',
                    style: TextStyle(fontSize: 11.5, color: KaataTheme.mutedOf(context)),
                  ),
                if (deposit.note != null && deposit.note!.trim().isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(deposit.note!,
                      style: TextStyle(
                          fontSize: 12, fontStyle: FontStyle.italic, color: KaataTheme.mutedOf(context))),
                ],
                if (deposit.reviewedBy != null) ...[
                  const SizedBox(height: 3),
                  Text(
                    '${deposit.isApproved ? 'Dikonfirmasi' : 'Ditolak'} oleh ${deposit.reviewedBy}'
                    '${deposit.reviewNote != null ? ' · ${deposit.reviewNote}' : ''}',
                    style: TextStyle(fontSize: 11.5, color: KaataTheme.mutedOf(context)),
                  ),
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
                if (onApprove != null || onReject != null) ...[
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      if (onApprove != null)
                        Expanded(
                          child: FilledButton.icon(
                            icon: const Icon(Icons.verified_outlined, size: 17),
                            label: const Text('Konfirmasi'),
                            style: FilledButton.styleFrom(
                              backgroundColor: const Color(0xFF10B981),
                              minimumSize: const Size.fromHeight(40),
                            ),
                            onPressed: onApprove,
                          ),
                        ),
                      if (onApprove != null && onReject != null) const SizedBox(width: 8),
                      if (onReject != null)
                        Expanded(
                          child: OutlinedButton.icon(
                            icon: const Icon(Icons.close, size: 17),
                            label: const Text('Tolak'),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Colors.red,
                              side: const BorderSide(color: Colors.red),
                              minimumSize: const Size.fromHeight(40),
                            ),
                            onPressed: onReject,
                          ),
                        ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          if (onDelete != null)
            IconButton(
              icon: const Icon(Icons.close, size: 18),
              color: KaataTheme.mutedOf(context),
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
        insetPadding: insetDialogWeb(context, minimal: 16, vertikal: 16),
        child: InteractiveViewer(
          child: Image.memory(base64Decode(deposit.proofBase64!)),
        ),
      ),
    );
  }
}

/// Uang laci dijemput petugas penjemputan.
///
/// Tercatat di tabel yang sama dengan setoran, dan itu disengaja: yang
/// terjadi pada uangnya sama persis — lembarannya keluar dari laci — dan
/// Saldo Cash sudah tahu cara menghitung itu. Tabel tersendiri berarti
/// Saldo Cash harus diajari sumber kedua, dan selama belum diajari, uang
/// yang sudah dibawa pergi masih dihitung ada di laci.
class _PickupDialog extends StatefulWidget {
  final String restoId;
  final int cashOnHand;

  const _PickupDialog({required this.restoId, required this.cashOnHand});

  @override
  State<_PickupDialog> createState() => _PickupDialogState();
}

class _PickupDialogState extends State<_PickupDialog> {
  final _formKey = GlobalKey<FormState>();
  final _amountCtrl = TextEditingController();
  final _petugasCtrl = TextEditingController();
  final _segelCtrl = TextEditingController();
  final _noteCtrl = TextEditingController();
  final _repo = CashDepositRepository();

  Uint8List? _bukti;
  bool _saving = false;

  @override
  void dispose() {
    _amountCtrl.dispose();
    _petugasCtrl.dispose();
    _segelCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  bool get _siap => _bukti != null;

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final auth = context.read<AuthProvider>();
    setState(() => _saving = true);
    try {
      await _repo.create(CashDeposit(
        id: '',
        restoId: widget.restoId,
        amount: parseRupiah(_amountCtrl.text)!,
        proofBase64: base64Encode(_bukti!),
        note: _noteCtrl.text.trim().isEmpty ? null : _noteCtrl.text.trim(),
        method: 'pickup',
        pickedUpBy: _petugasCtrl.text.trim(),
        sealNumber:
            _segelCtrl.text.trim().isEmpty ? null : _segelCtrl.text.trim(),
        createdBy: auth.user?.email ?? 'Kasir',
        createdAt: DateTime.now(),
      ));
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      showAppToast(context, 'Gagal menyimpan: ${pesanGalat(e)}', isError: true);
      setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final currency =
        NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0);

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      insetPadding: insetDialogWeb(context),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Cash Pickup',
                    style:
                        TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                Text(
                  'Uang laci yang dijemput petugas. Saldo Cash berkurang '
                  'sebesar ini begitu tersimpan.',
                  style: TextStyle(
                      fontSize: 12.5, color: KaataTheme.mutedOf(context)),
                ),
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: KaataTheme.softFillOf(context),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text('Tunai di laci: ${currency.format(widget.cashOnHand)}',
                      style: const TextStyle(
                          fontSize: 12.5, fontWeight: FontWeight.w600)),
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _amountCtrl,
                  decoration:
                      InputDecoration(label: requiredLabel('Nominal Dijemput')),
                  keyboardType: TextInputType.number,
                  inputFormatters: [ThousandsInputFormatter()],
                  style: const TextStyle(fontWeight: FontWeight.bold),
                  autofocus: true,
                  validator: (v) {
                    final n = parseRupiah(v ?? '');
                    if (n == null || n <= 0) return 'Wajib diisi, angka > 0';
                    // Menjemput lebih dari isi laci berarti salah hitung
                    // di suatu tempat, dan kalau dibiarkan saldonya jadi
                    // minus — angka yang tidak berarti apa-apa.
                    if (n > widget.cashOnHand) {
                      return 'Melebihi tunai di laci '
                          '(maks ${currency.format(widget.cashOnHand)})';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _petugasCtrl,
                  decoration:
                      InputDecoration(label: requiredLabel('Nama Petugas')),
                  inputFormatters: nameFormatters,
                  textCapitalization: TextCapitalization.words,
                  // Uang yang keluar laci tanpa nama penerima adalah uang
                  // yang tidak bisa ditanyakan ke siapa pun besok pagi.
                  validator: (v) =>
                      validateName(v, label: 'Nama petugas penjemput'),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _segelCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Nomor Segel (opsional)',
                    helperText: 'Kalau kantongnya bersegel',
                  ),
                  textCapitalization: TextCapitalization.characters,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _noteCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Catatan (opsional)',
                  ),
                  maxLines: 2,
                ),
                const SizedBox(height: 14),
                Text('Bukti Pickup',
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: KaataTheme.mutedOf(context))),
                const SizedBox(height: 8),
                if (_bukti == null)
                  OutlinedButton.icon(
                    onPressed: () async {
                      final picked = await pickProofPhoto(context);
                      if (picked != null && mounted) {
                        setState(() => _bukti = picked);
                      }
                    },
                    icon: const Icon(Icons.add_a_photo_outlined, size: 18),
                    label: const Text('Lampirkan Bukti'),
                    style: OutlinedButton.styleFrom(
                        minimumSize: const Size.fromHeight(46)),
                  )
                else
                  ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: Stack(
                      children: [
                        Image.memory(_bukti!,
                            width: double.infinity,
                            height: 150,
                            fit: BoxFit.cover),
                        Positioned(
                          top: 6,
                          right: 6,
                          child: GestureDetector(
                            onTap: () => setState(() => _bukti = null),
                            child: const CircleAvatar(
                              radius: 14,
                              backgroundColor: Colors.black54,
                              child: Icon(Icons.close,
                                  size: 16, color: Colors.white),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                if (_bukti == null) ...[
                  const SizedBox(height: 6),
                  const Text(
                    'Bukti pickup wajib dilampirkan.',
                    style: TextStyle(fontSize: 11.5, color: Colors.redAccent),
                  ),
                ],
                const SizedBox(height: 20),
                DialogActions(
                  confirmLabel: 'Simpan Pickup',
                  busy: _saving,
                  onConfirm: _siap ? _save : null,
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

class _AddDepositDialog extends StatefulWidget {
  final String restoId;
  final int cashOnHand;

  /// Rekening yang boleh jadi tujuan, dari Rekening Perusahaan.
  ///
  /// Dipilih, tidak diketik. Dulu ini isian biasa yang boleh ditimpa,
  /// dengan alasan kasir mungkin menyetor ke rekening lain. Yang terjadi
  /// justru sebaliknya: rekeningnya nyaris selalu itu-itu juga, dan yang
  /// berubah cuma salah ketik nomornya. Setoran yang tercatat ke nomor
  /// yang keliru tidak bisa dicocokkan Finance dengan mutasi bank mana
  /// pun, dan kekeliruannya baru ketahuan berhari-hari kemudian.
  ///
  /// Satu tempat mengaturnya: Owner/Finance → Rekening Perusahaan.
  final List<BankAccount> rekening;

  const _AddDepositDialog({
    required this.restoId,
    required this.cashOnHand,
    required this.rekening,
  });

  @override
  State<_AddDepositDialog> createState() => _AddDepositDialogState();
}

class _AddDepositDialogState extends State<_AddDepositDialog> {
  final _formKey = GlobalKey<FormState>();
  final _amountCtrl = TextEditingController();
  final _noteCtrl = TextEditingController();
  final _repo = CashDepositRepository();
  Uint8List? _proof;
  bool _saving = false;

  /// Rekening yang dipilih. Nomor rekeningnya yang dipilih orang; nama
  /// bank dan atas namanya mengikuti, tidak diketik ulang.
  ///
  /// Sebelumnya ketiganya cuma teks yang disalin dari satu rekening
  /// bawaan. Begitu merchant punya dua rekening, tidak ada cara
  /// menyebutkan setoran ini masuk ke yang mana — dan mencocokkannya
  /// dengan mutasi bank jadi tebakan.
  BankAccount? _rekening;

  @override
  void initState() {
    super.initState();
    // Rekening utama terpilih lebih dulu. Merchant yang cuma punya satu
    // tidak perlu memilih apa pun.
    for (final r in widget.rekening) {
      if (r.isPrimary) {
        _rekening = r;
        break;
      }
    }
    _rekening ??= widget.rekening.isEmpty ? null : widget.rekening.first;
  }

  @override
  void dispose() {
    _amountCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  /// Ada rekening tujuan yang bisa dipilih.
  bool get _accountReady => _rekening != null;

  /// Bukti wajib, dan servernya menegakkan hal yang sama.
  ///
  /// Setoran tanpa bukti adalah pernyataan sepihak bahwa uang sudah
  /// berpindah, dan yang memeriksanya nanti tidak punya apa pun untuk
  /// dibandingkan dengan mutasi rekening.
  bool get _siap => _accountReady && _proof != null;

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final auth = context.read<AuthProvider>();
    setState(() => _saving = true);
    try {
      final r = _rekening!;
      await _repo.create(CashDeposit(
        id: '',
        restoId: widget.restoId,
        amount: parseRupiah(_amountCtrl.text)!,
        proofBase64: base64Encode(_proof!),
        note: _noteCtrl.text.trim().isEmpty ? null : _noteCtrl.text.trim(),
        bankName: r.bankName,
        accountNumber: r.accountNumber,
        accountHolder: r.accountHolder,
        bankAccountId: r.id,
        createdBy: auth.user?.email ?? 'Kasir',
        createdAt: DateTime.now(),
      ));
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      showAppToast(context, 'Gagal menyimpan: $e', isError: true);
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
                          Text('Tunai di laci ke rekening merchant',
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
                  decoration: InputDecoration(label: requiredLabel('Jumlah Setoran'), prefixText: 'Rp '),
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
                const SizedBox(height: 14),
                Text('Rekening Tujuan',
                    style: TextStyle(
                        fontSize: 12, fontWeight: FontWeight.w600, color: KaataTheme.mutedOf(context))),
                const SizedBox(height: 8),
                // Nomor rekening yang dipilih, bukan nama banknya.
                // Yang dicocokkan orang dengan slip setoran di tangannya
                // adalah nomornya — nama bank cuma keterangan yang
                // mengikuti.
                DropdownButtonFormField<String>(
                  value: _rekening?.id,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Nomor Rekening',
                    isDense: true,
                  ),
                  items: [
                    for (final r in widget.rekening)
                      DropdownMenuItem(
                        value: r.id,
                        child: Text(
                          r.isPrimary
                              ? '${r.accountNumber}  (utama)'
                              : r.accountNumber,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                  onChanged: (v) => setState(() {
                    for (final r in widget.rekening) {
                      if (r.id == v) _rekening = r;
                    }
                  }),
                ),
                const SizedBox(height: 10),
                // Keduanya hasil dari pilihan di atas, bukan isian.
                // Mengetiknya ulang berarti membuka pintu bagi setoran
                // yang nomornya benar tapi namanya bukan milik rekening
                // itu.
                _ReadOnlyField(
                    label: 'Nama Pemilik Rekening',
                    value: _rekening?.accountHolder),
                const SizedBox(height: 10),
                _ReadOnlyField(label: 'Bank', value: _rekening?.bankName),
                if (!_accountReady) ...[
                  const SizedBox(height: 8),
                  const Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.info_outline, size: 16, color: Colors.redAccent),
                      SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          'Belum ada rekening perusahaan. Minta Owner atau '
                          'Finance menambahkannya di Rekening Perusahaan '
                          'sebelum menyetor.',
                          style: TextStyle(fontSize: 11.5, color: Colors.redAccent),
                        ),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 12),
                TextFormField(
                  controller: _noteCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Catatan (opsional)',
                    isDense: true,
                  ),
                  maxLines: 2,
                ),
                const SizedBox(height: 14),
                Text('Bukti Setor / Transfer',
                    style: TextStyle(
                        fontSize: 12, fontWeight: FontWeight.w600, color: KaataTheme.mutedOf(context))),
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
                        Image.memory(_proof!, width: double.infinity, height: 150, fit: BoxFit.cover),
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
                  // Setoran tanpa rekening tujuan tidak bisa dicocokkan
                  // Finance dengan mutasi bank mana pun. Sebelumnya
                  // ketiganya wajib diisi, jadi keadaan ini memang sudah
                  // selalu tertahan — yang berubah cuma siapa yang bisa
                  // memperbaikinya.
                  onConfirm: _siap ? _save : null,
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
            Icon(Icons.cloud_off, size: 40, color: KaataTheme.mutedOf(context)),
            const SizedBox(height: 12),
            Text('Gagal memuat data.\n$message',
                textAlign: TextAlign.center, style: TextStyle(color: KaataTheme.mutedOf(context))),
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


/// Isian yang cuma menampilkan, tidak menerima ketikan.
///
/// Dibuat sebagai widget tersendiri supaya ketiga baris rekening tujuan
/// tampil persis sama — abu-abu yang berbeda tipis antar baris terbaca
/// sebagai "yang ini mungkin bisa diketik".
class _ReadOnlyField extends StatelessWidget {
  final String label;
  final String? value;

  const _ReadOnlyField({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final text = (value ?? '').trim();
    return TextFormField(
      // key: nilainya datang belakangan dari Pengaturan Pembayaran, dan
      // tanpa ini isian yang sudah terbangun akan tetap memegang teks
      // kosong yang pertama.
      key: ValueKey('$label:$text'),
      initialValue: text.isEmpty ? '—' : text,
      enabled: false,
      decoration: InputDecoration(
        labelText: label,
        isDense: true,
        filled: true,
        fillColor: KaataTheme.disabledFillOf(context),
        helperText: text.isEmpty ? null : 'Dari Pengaturan Pembayaran',
        helperStyle: const TextStyle(fontSize: 10.5),
      ),
      style: TextStyle(
        fontWeight: FontWeight.w600,
        color: text.isEmpty ? KaataTheme.mutedOf(context) : KaataTheme.textOf(context),
      ),
    );
  }
}
