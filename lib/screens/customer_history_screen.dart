import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../db/guest_order_store.dart';
import '../db/order_repository.dart';
import '../db/restaurant_repository.dart';
import '../models/customer_order.dart';
import '../providers/auth_provider.dart';
import '../providers/table_session_provider.dart';
import '../theme.dart';
import '../widgets/app_toast.dart';
import '../widgets/dialog_actions.dart';
import '../utils/id_time.dart';
import 'customer_receipt_screen.dart';

/// Cross-restaurant order history, in two flavours:
///
///  - **Logged in**: streamed live by email, so it follows the account to
///    any device and updates as the kitchen progresses.
///  - **Guest**: fetched by the order ids this device saved locally (see
///    [GuestOrderStore]). The orders themselves still come from the
///    server, so status stays accurate — but the *list of which orders
///    were mine* only exists on this phone.
///
/// Unlike "Pesanan Saya" (which only covers the current table session),
/// this spans every resto and session.
class CustomerHistoryScreen extends StatefulWidget {
  const CustomerHistoryScreen({super.key});

  @override
  State<CustomerHistoryScreen> createState() => _CustomerHistoryScreenState();
}

class _CustomerHistoryScreenState extends State<CustomerHistoryScreen> {
  final _restoRepo = RestaurantRepository();
  final _orderRepo = OrderRepository();
  final Map<String, String> _restoNameCache = {};

  // Guest mode only — recreated on pull-to-refresh to re-run the fetch.
  Future<List<CustomerOrder>>? _guestFuture;

  Future<String> _restoName(String restoId) async {
    if (_restoNameCache.containsKey(restoId)) return _restoNameCache[restoId]!;
    final resto = await _restoRepo.getOnce(restoId);
    final name = resto?.name ?? restoId;
    _restoNameCache[restoId] = name;
    return name;
  }

  Future<List<CustomerOrder>> _loadGuestOrders() async {
    final ids = await GuestOrderStore().ids();
    return _orderRepo.getByIds(ids);
  }

  static const _kitchenLabels = {
    KitchenStatus.waiting: 'Menunggu Diproses',
    KitchenStatus.onProgress: 'Sedang Dimasak',
    KitchenStatus.done: 'Selesai',
  };
  static const _kitchenColors = {
    KitchenStatus.waiting: Colors.grey,
    KitchenStatus.onProgress: Colors.orange,
    KitchenStatus.done: Colors.green,
  };

  /// Pesanan yang sedang dibatalkan. Tombolnya dimatikan selama itu
  /// supaya dua ketukan beruntun tidak mengirim dua permintaan.
  String? _cancelling;

  Future<void> _cancel(CustomerOrder order) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        icon: const Icon(Icons.cancel_outlined, size: 38, color: Colors.red),
        title: const Text('Batalkan pesanan ini?'),
        content: const Text(
          'Pesanan akan ditarik dan tidak perlu dibayar. Kalau mau pesan '
          'lagi, tinggal buat pesanan baru.',
          textAlign: TextAlign.center,
        ),
        actionsAlignment: MainAxisAlignment.center,
        actions: [
          DialogActions(
            cancelLabel: 'Tidak Jadi',
            confirmLabel: 'Batalkan',
            destructive: true,
            onConfirm: () => Navigator.pop(dialogContext, true),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;

    setState(() => _cancelling = order.id);
    final session = context.read<TableSessionProvider>();
    final email = context.read<AuthProvider>().user?.email;
    try {
      final error = await _orderRepo.cancelMyOrder(
        order.id,
        sessionId: order.sessionId ?? session.sessionId,
        email: email,
      );
      if (!mounted) return;
      if (error != null) {
        // Ditolak database — biasanya karena dapur mulai memasak tepat
        // di sela ketukan tadi. Alasannya disampaikan apa adanya; yang
        // membacanya sedang berdiri di resto dan butuh tahu langkah
        // berikutnya, bukan sekadar tahu bahwa gagal.
        showAppToast(context, error, isError: true);
      } else {
        showAppToast(context, 'Pesanan dibatalkan.');
      }
      _refresh();
    } catch (e) {
      if (!mounted) return;
      showAppToast(context, 'Gagal membatalkan: $e', isError: true);
    } finally {
      if (mounted) setState(() => _cancelling = null);
    }
  }

  void _refresh() {
    // Yang login memakai aliran realtime — barisnya berubah sendiri.
    // Yang tamu memakai sekali ambil, jadi harus diminta ulang.
    if (context.read<AuthProvider>().user?.email == null) {
      setState(() => _guestFuture = _loadGuestOrders());
    }
  }

  @override
  Widget build(BuildContext context) {
    final email = context.watch<AuthProvider>().user?.email;

    return Scaffold(
      appBar: AppBar(title: const Text('Riwayat Saya')),
      body: email != null ? _loggedInBody(email) : _guestBody(),
    );
  }

  Widget _loggedInBody(String email) {
    return StreamBuilder<List<CustomerOrder>>(
      stream: _orderRepo.watchByCustomerEmail(email),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(
            child: Text('Gagal memuat riwayat.\n${snapshot.error}',
                textAlign: TextAlign.center),
          );
        }
        return _orderList(snapshot.data ?? []);
      },
    );
  }

  Widget _guestBody() {
    _guestFuture ??= _loadGuestOrders();

    return FutureBuilder<List<CustomerOrder>>(
      future: _guestFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(
            child: Text('Gagal memuat riwayat.\n${snapshot.error}',
                textAlign: TextAlign.center),
          );
        }
        return RefreshIndicator(
          // One-shot fetch, so status only moves on an explicit refresh —
          // unlike the logged-in stream, which updates on its own.
          onRefresh: () async {
            setState(() => _guestFuture = _loadGuestOrders());
            await _guestFuture;
          },
          child: _orderList(snapshot.data ?? [], guestNotice: true),
        );
      },
    );
  }

  Widget _orderList(List<CustomerOrder> orders, {bool guestNotice = false}) {
    final currency = NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0);
    final dateFmt = DateFormat('dd MMM yyyy, HH:mm', 'id_ID');

    if (orders.isEmpty) {
      // Still a scrollable, so pull-to-refresh keeps working when empty.
      return ListView(
        children: [
          if (guestNotice) const _GuestNotice(),
          const Padding(
            padding: EdgeInsets.only(top: 60),
            child: Center(child: Text('Belum ada riwayat pesanan.')),
          ),
        ],
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: orders.length + (guestNotice ? 1 : 0),
      itemBuilder: (context, index) {
        if (guestNotice && index == 0) return const _GuestNotice();
        final order = orders[index - (guestNotice ? 1 : 0)];
        return Card(
          margin: const EdgeInsets.only(bottom: 10),
          child: Column(
            children: [
              ListTile(
            title: FutureBuilder<String>(
              future: _restoName(order.restoId),
              builder: (context, snap) => Text(
                snap.data ?? order.restoId,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${order.tableNumber != null ? 'Meja ${order.tableNumber} • ' : ''}'
                  '${dateFmt.format(order.createdAt.toWib())}',
                  style: const TextStyle(fontSize: 12),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Icon(Icons.circle, size: 8, color: _kitchenColors[order.kitchenStatus]),
                    const SizedBox(width: 4),
                    Text(
                      _kitchenLabels[order.kitchenStatus]!,
                      style: TextStyle(
                        fontSize: 11,
                        color: _kitchenColors[order.kitchenStatus],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      switch (order.paymentStatus) {
                        OrderPaymentStatus.paid => 'Sudah Dibayar',
                        OrderPaymentStatus.cancelled => 'Dibatalkan',
                        OrderPaymentStatus.expired => 'Hangus, tidak dibayar',
                        OrderPaymentStatus.pending => 'Menunggu Pembayaran',
                      },
                      style: TextStyle(
                        fontSize: 11,
                        color: switch (order.paymentStatus) {
                          OrderPaymentStatus.paid => Colors.green,
                          OrderPaymentStatus.pending => Colors.orange,
                          _ => KaataTheme.mutedOf(context),
                        },
                      ),
                    ),
                  ],
                ),
              ],
            ),
            trailing: Text(
              currency.format(order.total),
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                      builder: (_) => CustomerReceiptScreen(order: order)),
                ),
              ),
              // Tombolnya hanya muncul selagi benar-benar bisa dipakai.
              // Tombol yang selalu ada lalu menolak saat ditekan membuat
              // orang mengira aplikasinya rusak — padahal yang terjadi
              // cuma dapur sudah mulai memasak.
              if (order.canBeCancelledByCustomer)
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
                  child: SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      icon: _cancelling == order.id
                          ? const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.cancel_outlined, size: 16),
                      label: const Text('Batalkan Pesanan'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.red,
                        side: const BorderSide(color: Colors.red),
                        minimumSize: const Size.fromHeight(38),
                      ),
                      onPressed:
                          _cancelling == null ? () => _cancel(order) : null,
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

/// Sets expectations about what a guest's history actually is, so nobody
/// assumes it'll survive a reinstall or follow them to a new phone.
class _GuestNotice extends StatelessWidget {
  const _GuestNotice();

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 12, 12, 4),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.orange.withOpacity(0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.orange.withOpacity(0.25)),
      ),
      child: Row(
        children: [
          Icon(Icons.phone_android, size: 18, color: Colors.orange.shade800),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Riwayat ini tersimpan di HP ini saja. Login dengan Gmail '
              'supaya riwayatmu tetap ada walau ganti HP.',
              style: TextStyle(fontSize: 12, color: Colors.orange.shade900),
            ),
          ),
        ],
      ),
    );
  }
}
