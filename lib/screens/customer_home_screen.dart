import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../db/firestore_product_repository.dart';
import '../db/order_repository.dart';
import '../db/restaurant_repository.dart';
import '../db/session_repository.dart';
import '../models/customer_order.dart';
import '../models/product.dart';
import '../models/restaurant.dart';
import '../providers/auth_provider.dart';
import '../providers/customer_cart_provider.dart';
import '../providers/table_session_provider.dart';
import '../utils/customer_login_flow.dart';
import '../widgets/product_category_list.dart';
import '../widgets/quantity_dialog.dart';
import 'customer_cart_screen.dart';
import 'customer_history_screen.dart';
import 'customer_order_status_screen.dart';
import 'customer_profile_screen.dart';
import 'scan_table_screen.dart';

/// Self-order browsing screen for customers. Reads the product catalog
/// live from Firestore (mirrored by the employee app), so stock/prices
/// stay in sync without needing a local database on the customer's
/// device.
///
/// Ordering requires having scanned a table's QR code first — this
/// screen gates on [TableSessionProvider.hasActiveTable] and shows the
/// scan screen otherwise.
///
/// While a session is active, this screen also watches the session's
/// orders in the background: once every order is "done" and 5 minutes
/// pass without a new one, the session auto-ends — same as tapping
/// "Selesai" on the order-status screen.
class CustomerHomeScreen extends StatefulWidget {
  const CustomerHomeScreen({super.key});

  @override
  State<CustomerHomeScreen> createState() => _CustomerHomeScreenState();
}

class _CustomerHomeScreenState extends State<CustomerHomeScreen> {
  static const _autoEndDelay = Duration(minutes: 5);

  StreamSubscription<List<CustomerOrder>>? _orderWatch;
  StreamSubscription<bool>? _remoteActiveWatch;
  String? _watchedSessionId;
  Timer? _autoEndTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final session = context.read<TableSessionProvider>();
      if (!session.loaded) await session.load();
      _syncOrderWatch();
    });
  }

  /// (Re)subscribes to this session's orders so the auto-end timer stays
  /// accurate — called after load and whenever the session changes (e.g.
  /// right after scanning/resuming a table).
  void _syncOrderWatch() {
    final session = context.read<TableSessionProvider>();
    if (!session.hasActiveTable) {
      _orderWatch?.cancel();
      _orderWatch = null;
      _remoteActiveWatch?.cancel();
      _remoteActiveWatch = null;
      _watchedSessionId = null;
      _autoEndTimer?.cancel();
      return;
    }
    if (_watchedSessionId == session.sessionId) {
      return; // already watching this one
    }

    _orderWatch?.cancel();
    _remoteActiveWatch?.cancel();
    _watchedSessionId = session.sessionId;

    // Local fallback: while this screen is open, end the session 5 minutes
    // after everything's done — instant, no round trip needed.
    _orderWatch =
        OrderRepository().watchBySession(session.sessionId!).listen((orders) {
      final allDone = orders.isNotEmpty &&
          orders.every((o) => o.kitchenStatus == KitchenStatus.done);
      _autoEndTimer?.cancel();
      if (allDone) {
        _autoEndTimer = Timer(_autoEndDelay, () {
          if (mounted) context.read<TableSessionProvider>().endSession();
        });
      }
    });

    // Backend backstop: the Cloud Function can end this session even if
    // the app was closed the whole time — this listener just makes sure
    // the UI catches up once we're back online/foregrounded.
    _remoteActiveWatch =
        SessionRepository().watchActive(session.sessionId!).listen((active) {
      if (!active && mounted) {
        context.read<TableSessionProvider>().applyRemoteEnded();
      }
    });
  }

  @override
  void dispose() {
    _orderWatch?.cancel();
    _remoteActiveWatch?.cancel();
    _autoEndTimer?.cancel();
    super.dispose();
  }

  bool _loggingIn = false;

  Future<void> _loginWithEmail() async {
    final auth = context.read<AuthProvider>();
    setState(() => _loggingIn = true);
    await auth.signInWithGoogle();
    if (!mounted) return;
    setState(() => _loggingIn = false);
    if (auth.lastError != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(auth.lastError!)),
      );
    } else if (auth.isLoggedIn && !auth.isEmployee) {
      await ensureCustomerProfile(context, auth.user!.email!);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Login sebagai ${auth.user?.email}')),
      );
    }
    // If it turns out this email IS a registered employee, RootScreen
    // will notice the role change and switch to the staff screens on its
    // own — nothing else to do here.
  }

  /// Icons shown on both the "scan first" screen and the main ordering
  /// screen: a customer login (so their order history follows their
  /// email across restaurants/devices) plus the existing staff entry
  /// point. Registering as staff isn't required anywhere here — anyone
  /// who signs in and isn't found in the `employees` collection is just
  /// treated as a normal logged-in customer.
  List<Widget> _customerAppBarActions(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final loggedInAsCustomer = auth.isLoggedIn && !auth.isEmployee;

    return [
      if (loggedInAsCustomer)
        IconButton(
          icon: const Icon(Icons.account_circle_outlined),
          tooltip: 'Profil Saya',
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => CustomerProfileScreen(email: auth.user!.email!),
            ),
          ),
        ),
      if (loggedInAsCustomer)
        IconButton(
          icon: const Icon(Icons.history),
          tooltip: 'Riwayat Saya',
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const CustomerHistoryScreen()),
          ),
        )
      else
        IconButton(
          icon: _loggingIn
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.login),
          tooltip: 'Login dengan Email',
          onPressed: _loggingIn ? null : _loginWithEmail,
        ),
      if (loggedInAsCustomer)
        IconButton(
          icon: const Icon(Icons.logout),
          tooltip: 'Logout (${auth.user?.email})',
          onPressed: () async {
            await auth.signOut();
            if (!context.mounted) return;
            // Logging out also ends the table session — resuming after
            // this always requires scanning the table QR again.
            await context.read<TableSessionProvider>().clear();
            if (!context.mounted) return;
            Navigator.of(context).popUntil((r) => r.isFirst);
          },
        ),
    ];
  }

  Future<void> _openQuantityDialog(
      BuildContext context, CustomerCartProvider cart, Product product) async {
    final currentQty = cart.quantityOf(product.id);
    final result = await showDialog<QuantityDialogResult>(
      context: context,
      builder: (_) => QuantityDialog(
        product: product,
        initialQuantity: currentQty > 0 ? currentQty : 1,
        initialLevels: cart.selectedLevelsOf(product.id),
        initialNotes: cart.notesOf(product.id),
      ),
    );
    if (result == null) return;
    cart.setQuantity(
      product,
      result.quantity,
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
    final repo = FirestoreProductRepository();
    final restoRepo = RestaurantRepository();
    final session = context.watch<TableSessionProvider>();
    final auth = context.watch<AuthProvider>();
    // Once logged in, this screen is the customer's "home" — back
    // navigation is blocked so they can't fall back to the role-choice
    // page by accident; logging out is the only way there.
    final loggedInAsCustomer = auth.isLoggedIn && !auth.isEmployee;

    if (!session.loaded) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    // Keep the auto-end watcher in sync with whichever session is active
    // right now (a no-op if it's already watching this sessionId).
    WidgetsBinding.instance.addPostFrameCallback((_) => _syncOrderWatch());

    if (!session.hasActiveTable) {
      return PopScope(
        canPop: !loggedInAsCustomer,
        child: Scaffold(
          appBar: AppBar(
            automaticallyImplyLeading: !loggedInAsCustomer,
            title: const Text('KaataGo (Customer)'),
            actions: _customerAppBarActions(context),
          ),
          body: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.qr_code_scanner,
                    size: 72, color: Colors.indigo),
                const SizedBox(height: 16),
                const Text(
                  'Scan QR code di meja kamu dulu untuk mulai pesan.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 16),
                ),
                const SizedBox(height: 24),
                FilledButton.icon(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const ScanTableScreen()),
                  ),
                  icon: const Icon(Icons.qr_code_scanner),
                  label: const Text('Scan QR Meja'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return PopScope(
      canPop: !loggedInAsCustomer,
      child: Scaffold(
        appBar: AppBar(
          automaticallyImplyLeading: !loggedInAsCustomer,
          title: Text('Meja ${session.tableNumber}'),
          actions: [
            IconButton(
              icon: const Icon(Icons.receipt_long_outlined),
              tooltip: 'Pesanan Saya',
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(
                    builder: (_) => const CustomerOrderStatusScreen()),
              ),
            ),
            ..._customerAppBarActions(context),
          ],
        ),
        body: Column(
          children: [
            StreamBuilder<Restaurant?>(
              stream: restoRepo.watch(session.restoId!),
              builder: (context, snapshot) {
                final resto = snapshot.data;
                if (resto == null) return const SizedBox.shrink();
                return Container(
                  width: double.infinity,
                  color: Colors.indigo.shade50,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(resto.name,
                          style: const TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 15)),
                      if (resto.address.isNotEmpty)
                        Text(resto.address,
                            style: const TextStyle(
                                fontSize: 12, color: Colors.grey)),
                    ],
                  ),
                );
              },
            ),
            Expanded(
              child: StreamBuilder<List<Product>>(
                stream: repo.watchAll(session.restoId!),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (snapshot.hasError) {
                    return Center(
                      child: Text('Gagal memuat produk.\n${snapshot.error}',
                          textAlign: TextAlign.center),
                    );
                  }
                  final products = snapshot.data ?? [];
                  if (products.isEmpty) {
                    return const Center(
                        child: Text('Belum ada produk tersedia.'));
                  }
                  return Consumer<CustomerCartProvider>(
                    builder: (context, cart, _) {
                      return ProductCategoryList(
                        products: products,
                        quantityOf: cart.quantityOf,
                        onTapProduct: (p) => _openQuantityDialog(context, cart, p),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
        bottomNavigationBar: Consumer<CustomerCartProvider>(
          builder: (context, cart, _) {
            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: FilledButton(
                  onPressed: cart.items.isEmpty
                      ? null
                      : () => Navigator.of(context).push(
                            MaterialPageRoute(
                                builder: (_) => const CustomerCartScreen()),
                          ),
                  child: Text(
                    cart.items.isEmpty
                        ? 'Keranjang kosong'
                        : 'Lihat Keranjang (${cart.itemCount}) • ${currency.format(cart.total)}',
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
