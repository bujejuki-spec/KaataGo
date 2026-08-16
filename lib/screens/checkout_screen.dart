import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/order_type.dart';
import '../models/transaction.dart';
import '../providers/auth_provider.dart';
import '../providers/cart_provider.dart';
import '../providers/product_provider.dart';
import 'payment_qris_screen.dart';
import 'payment_transfer_screen.dart';
import 'receipt_screen.dart';
import '../widgets/cash_payment_dialog.dart';
import '../db/restaurant_repository.dart';
import '../models/restaurant.dart';
import '../widgets/charge_summary.dart';
import '../widgets/quantity_dialog.dart';
import '../widgets/cart_line_tile.dart';
import '../models/cart_item.dart';
import '../utils/field_rules.dart';

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
                    if (_isDineIn) ...[
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
                      ),
                      const SizedBox(height: 12),
                      // Namanya opsional di Dine In, dan sengaja begitu.
                      //
                      // Yang mengantarkan makanannya sudah tahu ke meja
                      // mana — nomor mejanya di atas sudah cukup. Nama di
                      // sini gunanya untuk yang datang sesudahnya:
                      // struk yang dicari, pesanan yang ditanyakan
                      // ulang, atau meja yang isinya dua rombongan.
                      // Mewajibkannya cuma menambah satu ketikan di
                      // tiap transaksi untuk sesuatu yang tidak selalu
                      // ditanyakan kasirnya.
                      TextField(
                        controller: _customerNameCtrl,
                        inputFormatters: nameFormatters,
                        textCapitalization: TextCapitalization.words,
                        maxLength: kNameMaxLength,
                        decoration: const InputDecoration(
                          labelText: 'Nama Customer (opsional)',
                          prefixIcon: Icon(Icons.person_outline),
                          border: OutlineInputBorder(),
                          helperText: 'Muncul di struk dan layar dapur',
                          counterText: '',
                        ),
                        onChanged: (_) => setState(() {}),
                      ),
                    ] else
                      TextField(
                        controller: _customerNameCtrl,
                        inputFormatters: nameFormatters,
                        textCapitalization: TextCapitalization.words,
                        maxLength: kNameMaxLength,
                        decoration: const InputDecoration(
                          labelText: 'Nama Customer',
                          prefixIcon: Icon(Icons.person_outline),
                          border: OutlineInputBorder(),
                          helperText: 'Wajib diisi — dipanggil saat pesanan siap diambil',
                          counterText: '',
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
        builder: (_) => CashPaymentDialog(total: cart.total),
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
      customerName: _customerName.isEmpty ? null : _customerName,
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
