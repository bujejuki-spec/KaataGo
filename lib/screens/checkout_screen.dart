import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/order_type.dart';
import '../models/transaction.dart';
import '../providers/auth_provider.dart';
import '../providers/cart_provider.dart';
import '../providers/product_provider.dart';
import '../widgets/dialog_actions.dart';
import 'payment_qris_screen.dart';
import 'payment_transfer_screen.dart';
import 'receipt_screen.dart';
import '../utils/rupiah_input.dart';
import '../db/restaurant_repository.dart';
import '../models/restaurant.dart';
import '../widgets/charge_summary.dart';
import '../widgets/quantity_dialog.dart';
import '../widgets/cart_line_tile.dart';
import '../models/cart_item.dart';

class CheckoutScreen extends StatefulWidget {
  const CheckoutScreen({super.key});

  @override
  State<CheckoutScreen> createState() => _CheckoutScreenState();
}

class _CheckoutScreenState extends State<CheckoutScreen> {
  final _tableCtrl = TextEditingController();
  final _customerNameCtrl = TextEditingController();
  OrderType _orderType = OrderType.dineIn;

  @override
  void initState() {
    super.initState();
    _loadResto();
  }

  @override
  void dispose() {
    _tableCtrl.dispose();
    _customerNameCtrl.dispose();
    super.dispose();
  }

  final _restoRepo = RestaurantRepository();
  Restaurant? _resto;

  /// Rates come from the resto record, so the same order rung up on any
  /// device splits identically.
  double get _ppnPercent => _resto?.ppnPercent ?? 0;
  double get _servicePercent => _resto?.servicePercent ?? 0;

  Future<void> _loadResto() async {
    final restoId = context.read<AuthProvider>().restoId;
    if (restoId == null) return;
    try {
      final resto = await _restoRepo.getOnce(restoId);
      if (!mounted) return;
      setState(() => _resto = resto);
      context.read<CartProvider>().setRates(
            ppn: resto?.ppnPercent ?? 0,
            service: resto?.servicePercent ?? 0,
          );
    } catch (_) {
      // Offline — fall back to no charges rather than guessing a rate.
    }
  }

  bool get _isDineIn => _orderType == OrderType.dineIn;

  /// Free-form label, not a number — "A01" and "VIP-2" are valid tables.
  String? get _tableNumber {
    final raw = _tableCtrl.text.trim();
    return raw.isEmpty ? null : raw;
  }

  String get _customerName => _customerNameCtrl.text.trim();

  /// Dine In needs a table number; Take Away needs a customer name
  /// instead (there's no table to deliver it to).
  bool get _canPay => _isDineIn ? _tableNumber != null : _customerName.isNotEmpty;

  /// Reopens the options popup on an existing line, so a wrong spice
  /// level or a mistaken add can be fixed without clearing the cart.
  Future<void> _editLine(BuildContext context, CartProvider cart, CartItem item) async {
    final result = await showDialog<QuantityDialogResult>(
      context: context,
      builder: (_) => QuantityDialog(
        product: item.product,
        initialQuantity: item.quantity,
        initialLevels: item.selectedLevels,
        initialNotes: item.notes,
        ppnPercent: cart.ppnPercent,
        editing: true,
      ),
    );
    if (result == null) return;
    cart.updateLine(
      item.lineId,
      quantity: result.quantity,
      selectedLevels: result.selectedLevels,
      notes: result.notes,
    );
  }

  @override
  Widget build(BuildContext context) {
    final currency = NumberFormat.currency(
      locale: 'id_ID',
      symbol: 'Rp ',
      decimalDigits: 0,
    );

    return Scaffold(
      appBar: AppBar(title: const Text('Kasir')),
      body: Consumer<CartProvider>(
        builder: (context, cart, _) {
          if (cart.items.isEmpty) {
            return const Center(child: Text('Keranjang kosong. Pilih produk dulu.'));
          }
          return Column(
            children: [
              Expanded(
                child: ListView.builder(
                  itemCount: cart.items.length,
                  itemBuilder: (context, index) {
                    final item = cart.items[index];
                    return CartLineTile(
                      item: item,
                      unitPrice: cart.menuSubtotalOf(item) ~/ item.quantity,
                      lineTotal: cart.menuSubtotalOf(item),
                      currency: currency,
                      onIncrement: () => cart.incrementLine(item.lineId),
                      onDecrement: () => cart.decrementLine(item.lineId),
                      onDelete: () => cart.removeLine(item.lineId),
                      onEdit: () => _editLine(context, cart, item),
                    );
                  },
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    SegmentedButton<OrderType>(
                      segments: const [
                        ButtonSegment(
                          value: OrderType.dineIn,
                          label: Text('Dine In'),
                          icon: Icon(Icons.restaurant_outlined),
                        ),
                        ButtonSegment(
                          value: OrderType.takeAway,
                          label: Text('Take Away'),
                          icon: Icon(Icons.shopping_bag_outlined),
                        ),
                      ],
                      selected: {_orderType},
                      onSelectionChanged: (v) => setState(() => _orderType = v.first),
                    ),
                    const SizedBox(height: 12),
                    if (_isDineIn)
                      TextField(
                        controller: _tableCtrl,
                        textCapitalization: TextCapitalization.characters,
                        decoration: const InputDecoration(
                          labelText: 'Nomor Meja',
                          hintText: 'Contoh: 7, A01, VIP-2',
                          prefixIcon: Icon(Icons.table_bar_outlined),
                          border: OutlineInputBorder(),
                        ),
                        onChanged: (_) => setState(() {}),
                      )
                    else
                      TextField(
                        controller: _customerNameCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Nama Customer',
                          prefixIcon: Icon(Icons.person_outline),
                          border: OutlineInputBorder(),
                          helperText: 'Wajib diisi — dipanggil saat pesanan siap diambil',
                        ),
                        onChanged: (_) => setState(() {}),
                      ),
                    const SizedBox(height: 16),
                    ChargeSummary(
                      charges: cart.chargesFor(_orderType),
                      menuSubtotal: cart.total,
                      ppnPercent: _ppnPercent,
                      servicePercent: _servicePercent,
                      serviceApplies: _isDineIn,
                      currency: currency,
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: !_canPay
                                ? null
                                : () => _handlePayment(context, cart, PaymentMethod.cash),
                            child: const Text('Tunai'),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: OutlinedButton(
                            onPressed: !_canPay
                                ? null
                                : () => _handlePayment(context, cart, PaymentMethod.qris),
                            child: const Text('QRIS'),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: OutlinedButton(
                            onPressed: !_canPay
                                ? null
                                : () => _handlePayment(context, cart, PaymentMethod.transfer),
                            child: const Text('Transfer'),
                          ),
                        ),
                      ],
                    ),
                    if (!_canPay) ...[
                      const SizedBox(height: 8),
                      Text(
                        _isDineIn
                            ? 'Isi nomor meja dulu sebelum bisa checkout.'
                            : 'Isi nama customer dulu sebelum bisa checkout.',
                        style: const TextStyle(color: Colors.red, fontSize: 12),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _handlePayment(BuildContext context, CartProvider cart, PaymentMethod method) async {
    if (!_canPay) return;
    final tableNumber = _isDineIn ? _tableNumber : null;

    // Cash: the cashier keys in what the customer handed over so the
    // change is worked out here instead of in their head — and so the
    // receipt can print both figures.
    int? cashReceived;
    if (method == PaymentMethod.cash) {
      cashReceived = await showDialog<int>(
        context: context,
        builder: (_) => _CashPaymentDialog(total: cart.total),
      );
      if (cashReceived == null || !context.mounted) return;
    }

    // QRIS/Transfer show a dummy "simulate payment" screen first, and
    // only proceed if the cashier confirms it went through.
    if (method != PaymentMethod.cash) {
      final confirmed = await Navigator.of(context).push<bool>(
        MaterialPageRoute(
          builder: (_) => method == PaymentMethod.qris
              ? PaymentQrisScreen(amount: cart.total)
              : PaymentTransferScreen(amount: cart.total),
        ),
      );
      if (confirmed != true) return;
    }

    if (!context.mounted) return;

    final auth = context.read<AuthProvider>();
    final tx = await cart.checkout(
      method,
      cashierLabel: auth.user?.email,
      cashierName:
          auth.employeeName?.isNotEmpty == true ? auth.employeeName : (auth.roleLabel ?? 'Kasir'),
      tableNumber: tableNumber,
      restoId: auth.restoId!,
      orderType: _orderType,
      customerName: _isDineIn ? null : _customerName,
      cashReceived: cashReceived,
    );

    // Refresh product list so updated stock is reflected everywhere
    // (grid on the home screen, product management list, etc.)
    if (context.mounted) {
      await context.read<ProductProvider>().load();
    }

    if (!context.mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => ReceiptScreen(transaction: tx)),
    );
  }
}

/// Asks how much cash the customer handed over and shows the change back
/// live as it's typed.
///
/// Quick-pick chips cover what a cashier reaches for most — exact money,
/// then the next round notes up from the total — because typing the full
/// amount on every sale is the slowest part of taking cash.
class _CashPaymentDialog extends StatefulWidget {
  final int total;

  const _CashPaymentDialog({required this.total});

  @override
  State<_CashPaymentDialog> createState() => _CashPaymentDialogState();
}

class _CashPaymentDialogState extends State<_CashPaymentDialog> {
  final _ctrl = TextEditingController();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  int? get _received {
    final n = parseRupiah(_ctrl.text);
    return (n != null && n > 0) ? n : null;
  }

  int? get _change {
    final r = _received;
    return r == null ? null : r - widget.total;
  }

  bool get _enough => _change != null && _change! >= 0;

  /// Exact money, then the next few round notes above the total —
  /// duplicates dropped so "uang pas" never repeats a suggestion.
  List<int> get _suggestions {
    final out = <int>{widget.total};
    for (final note in [5000, 10000, 20000, 50000, 100000]) {
      final rounded = ((widget.total / note).ceil()) * note;
      if (rounded > widget.total) out.add(rounded);
    }
    return out.toList()..sort();
  }

  @override
  Widget build(BuildContext context) {
    final currency = NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0);

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 24, 20, 12),
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
                      color: const Color(0xFF10B981).withOpacity(0.12),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.payments_outlined, color: Color(0xFF10B981)),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Pembayaran Tunai',
                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17)),
                        Text('Masukkan uang yang diterima',
                            style: TextStyle(fontSize: 12, color: Colors.grey)),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  color: const Color(0xFFF4F5FB),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Total', style: TextStyle(fontWeight: FontWeight.w600)),
                    Text(currency.format(widget.total),
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _ctrl,
                keyboardType: TextInputType.number,
                inputFormatters: [ThousandsInputFormatter()],
                autofocus: true,
                decoration: const InputDecoration(labelText: 'Uang Diterima', prefixText: 'Rp '),
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 17),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final amount in _suggestions)
                    ActionChip(
                      label: Text(amount == widget.total ? 'Uang pas' : currency.format(amount)),
                      onPressed: () => setState(() => _ctrl.text = formatRupiahInput(amount)),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  color: (_enough ? const Color(0xFF10B981) : Colors.orange).withOpacity(0.10),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(_enough ? 'Kembalian' : 'Kurang',
                        style: TextStyle(
                            fontWeight: FontWeight.w600,
                            color: _enough ? const Color(0xFF0F766E) : Colors.orange.shade900)),
                    Text(
                      _change == null ? '-' : currency.format(_change!.abs()),
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 20,
                        color: _enough ? const Color(0xFF0F766E) : Colors.orange.shade900,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              DialogActions(
                confirmLabel: 'Terima Pembayaran',
                onConfirm: _enough ? () => Navigator.pop(context, _received) : null,
                onCancel: () => Navigator.pop(context),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
