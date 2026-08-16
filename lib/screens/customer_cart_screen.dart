import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../db/customer_profile_repository.dart';
import '../db/restaurant_repository.dart';
import '../models/restaurant.dart';
import '../db/guest_order_store.dart';
import '../models/order_type.dart';
import '../providers/auth_provider.dart';
import '../providers/customer_cart_provider.dart';
import '../providers/table_session_provider.dart';
import 'customer_cash_pending_screen.dart';
import 'customer_qris_screen.dart';
import '../widgets/charge_summary.dart';
import '../widgets/quantity_dialog.dart';
import '../widgets/cart_line_tile.dart';
import '../models/cart_item.dart';
import '../utils/field_rules.dart';

/// Checkout screen. Lets the customer pick Dine In or Take Away first —
/// for Take Away no table is needed at all, so the table-number field is
/// hidden entirely, but a customer name IS required (there's no table
/// to deliver it to, so the name is what gets called out when it's
/// ready) — pre-filled from their profile if logged in, but editable.
/// For Dine In: if the session came from scanning a table QR code, the
/// table number is already known — shown here read-only/greyed out. If
/// it came from picking a restaurant off the list instead (no QR),
/// there's no table number yet, so this screen makes it a mandatory
/// field before "Pesan & Bayar" can be pressed.
class CustomerCartScreen extends StatefulWidget {
  const CustomerCartScreen({super.key});

  @override
  State<CustomerCartScreen> createState() => _CustomerCartScreenState();
}

class _CustomerCartScreenState extends State<CustomerCartScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _tableCtrl;
  final _nameCtrl = TextEditingController();
  OrderType _orderType = OrderType.dineIn;

  /// Cara bayar yang dipilih, memakai kunci yang sama dengan
  /// `gl_accounts` — 'qris' atau 'cash'.
  ///
  /// QRIS tetap yang terpilih di awal: itu yang menyelesaikan pesanan
  /// tanpa siapa pun harus beranjak, dan justru itulah gunanya memesan
  /// dari HP sendiri.
  String _paymentMethod = 'qris';

  bool get _payAtCashier => _paymentMethod == 'cash';

  bool _placing = false;
  Restaurant? _resto;

  double get _ppnPercent => _resto?.ppnPercent ?? 0;
  double get _servicePercent => _resto?.servicePercent ?? 0;

  Future<void> _loadResto() async {
    final restoId = context.read<TableSessionProvider>().restoId;
    if (restoId == null) return;
    try {
      final resto = await RestaurantRepository().getOnce(restoId);
      if (!mounted) return;
      setState(() => _resto = resto);
      context.read<CustomerCartProvider>().setRates(
            ppn: resto?.ppnPercent ?? 0,
            service: resto?.servicePercent ?? 0,
          );
    } catch (_) {
      // Offline — fall back to no charges rather than guessing a rate.
    }
  }

  @override
  void initState() {
    super.initState();
    final known = context.read<TableSessionProvider>().tableNumber;
    _tableCtrl = TextEditingController(text: known ?? '');
    _prefillNameFromProfile();
    _loadResto();
  }

  /// If logged in, use their saved profile name as a starting point —
  /// still freely editable (e.g. ordering for someone else).
  Future<void> _prefillNameFromProfile() async {
    final email = context.read<AuthProvider>().user?.email;
    if (email == null) return;
    final profile = await CustomerProfileRepository().getOnce(email);
    if (!mounted || profile == null || profile.name.isEmpty) return;
    if (_nameCtrl.text.isEmpty) {
      setState(() => _nameCtrl.text = profile.name);
    }
  }

  @override
  void dispose() {
    _tableCtrl.dispose();
    _nameCtrl.dispose();
    super.dispose();
  }

  Future<void> _checkout() async {
    if (!_formKey.currentState!.validate()) return;

    final session = context.read<TableSessionProvider>();
    final cart = context.read<CustomerCartProvider>();
    final auth = context.read<AuthProvider>();
    final isDineIn = _orderType == OrderType.dineIn;

    String? tableNumber;
    if (isDineIn) {
      // Table came in via QR scan already — nothing new to save.
      // Otherwise this is the first time it's known, so persist it.
      tableNumber = session.tableNumber ?? _tableCtrl.text.trim();
      if (session.tableNumber == null) {
        await session.setTableNumber(tableNumber);
      }
    }

    setState(() => _placing = true);
    final label = auth.user?.email ?? 'Tamu';
    // Total yang benar-benar ditagihkan, bukan subtotal menunya.
    //
    // `cart.total` adalah jumlah harga menu — harga bersih + PPN, tanpa
    // biaya service. Angka itu benar untuk daftar belanja, tapi salah
    // untuk dibayar: pesanan Dine In menyimpan total yang sudah termasuk
    // service, dan pelanggan akan melihat nominal yang lebih kecil
    // daripada yang ditagih QR-nya. Pada Take Away keduanya kebetulan
    // sama persis, dan justru itu yang membuat selisihnya lolos begitu
    // lama.
    final amount = cart.chargesFor(_orderType).total;
    final orderId = await cart.placeOrder(
      label,
      tableNumber: tableNumber,
      sessionId: session.sessionId!,
      restoId: session.restoId!,
      orderType: _orderType,
      // Dipakai juga untuk Dine In sekarang: nomor meja memberi tahu
      // dapur ke mana mengantar, tapi tidak memberi tahu siapa yang
      // dipanggil kalau mejanya berisi beberapa orang yang memesan
      // sendiri-sendiri.
      customerName: _nameCtrl.text.trim(),
      paymentMethod: _paymentMethod,
    );
    // A logged-in customer's history comes from their email, so this is
    // only needed for guests — it's the only record they'd otherwise have.
    if (auth.user?.email == null) {
      await GuestOrderStore().add(orderId);
    }
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => _payAtCashier
            // Tidak ada layar bayar untuk tunai: yang menerima uangnya
            // kasir, dan pesanannya sudah tercatat lengkap sejak baris
            // di atas. Yang tersisa cuma memberi tahu ke mana harus
            // melangkah.
            ? CustomerCashPendingScreen(orderId: orderId, amount: amount)
            : CustomerQrisScreen(
                orderId: orderId,
                amount: amount,
                restoId: session.restoId!,
              ),
      ),
    );
  }

  /// Reopens the options popup on an existing line, so a wrong spice
  /// level or a mistaken add can be fixed without clearing the cart.
  Future<void> _editLine(BuildContext context, CustomerCartProvider cart, CartItem item) async {
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
    final tableKnown = context.watch<TableSessionProvider>().tableNumber != null;
    final isDineIn = _orderType == OrderType.dineIn;

    return Scaffold(
      appBar: AppBar(title: const Text('Keranjang')),
      body: Consumer<CustomerCartProvider>(
        builder: (context, cart, _) {
          if (cart.items.isEmpty) {
            return const Center(child: Text('Keranjang kosong.'));
          }
          return Form(
            key: _formKey,
            child: Column(
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
                const Divider(height: 1),
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
                      const SizedBox(height: 16),
                      if (isDineIn) ...[
                        TextFormField(
                          controller: _tableCtrl,
                          enabled: !tableKnown,
                          textCapitalization: TextCapitalization.characters,
                          decoration: InputDecoration(
                            labelText: 'Nomor Meja',
                            helperText: tableKnown
                                ? 'Terisi otomatis dari QR yang kamu scan'
                                : 'Wajib diisi — nomor meja tempat kamu duduk',
                            filled: tableKnown,
                            fillColor: tableKnown ? Colors.grey.shade200 : null,
                          ),
                          validator: (v) {
                            if (tableKnown) return null;
                            if (v == null || v.trim().isEmpty) return 'Wajib diisi';
                            return null;
                          },
                        ),
                        const SizedBox(height: 12),
                      ],
                      TextFormField(
                        controller: _nameCtrl,
                        textCapitalization: TextCapitalization.words,
                        inputFormatters: nameFormatters,
                        decoration: InputDecoration(
                          labelText: 'Nama Customer',
                          helperText: isDineIn
                              ? 'Wajib diisi — supaya pesananmu tidak tertukar dengan teman semeja'
                              : 'Wajib diisi — nama yang akan dipanggil saat pesanan siap',
                        ),
                        validator: (v) => validateName(v, label: 'Nama customer'),
                      ),
                      const SizedBox(height: 16),
                      ChargeSummary(
                        charges: cart.chargesFor(_orderType),
                        menuSubtotal: cart.total,
                        ppnPercent: _ppnPercent,
                        servicePercent: _servicePercent,
                        serviceApplies: isDineIn,
                        currency: currency,
                      ),
                      const SizedBox(height: 14),
                      const Align(
                        alignment: Alignment.centerLeft,
                        child: Text('Cara Bayar',
                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                      ),
                      const SizedBox(height: 8),
                      SegmentedButton<String>(
                        segments: const [
                          ButtonSegment(
                            value: 'qris',
                            label: Text('QRIS'),
                            icon: Icon(Icons.qr_code_2),
                          ),
                          ButtonSegment(
                            value: 'cash',
                            label: Text('Tunai'),
                            icon: Icon(Icons.payments_outlined),
                          ),
                        ],
                        selected: {_paymentMethod},
                        onSelectionChanged: _placing
                            ? null
                            : (v) => setState(() => _paymentMethod = v.first),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _payAtCashier
                            ? 'Pesanan langsung masuk ke dapur. Pembayaran '
                                'diselesaikan di kasir — statusnya menunggu '
                                'pembayaran sampai kasir menerima uangnya.'
                            : 'Bayar sekarang lewat QRIS, tanpa perlu ke kasir.',
                        style: const TextStyle(color: Colors.grey, fontSize: 12),
                      ),
                      const SizedBox(height: 16),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton(
                          onPressed: _placing ? null : _checkout,
                          child: _placing
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(strokeWidth: 2))
                              : Text(_payAtCashier
                                  ? 'Pesan & Bayar di Kasir'
                                  : 'Pesan & Bayar dengan QRIS'),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
