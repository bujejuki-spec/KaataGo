import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/product.dart';
import '../providers/auth_provider.dart';
import '../providers/cart_provider.dart';
import '../providers/product_provider.dart';
import '../widgets/product_category_list.dart';
import '../widgets/quantity_dialog.dart';
import 'checkout_screen.dart';
import 'employee_orders_screen.dart';
import 'product_list_screen.dart';
import 'settings_menu_screen.dart';
import 'transaction_history_screen.dart';

/// Main cashier screen: tap products to add to cart, then go to checkout.
/// Used by both Admin (full access) and Kasir (input pesanan + riwayat
/// only) — [isAdmin] toggles the extra management icons in the app bar.
class PosHomeScreen extends StatefulWidget {
  final bool isAdmin;

  const PosHomeScreen({super.key, this.isAdmin = true});

  @override
  State<PosHomeScreen> createState() => _PosHomeScreenState();
}

class _PosHomeScreenState extends State<PosHomeScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final provider = context.read<ProductProvider>();
      provider.restoId = context.read<AuthProvider>().restoId;
      await provider.load();
      // Pull first so any stock customers already bought (or any product
      // seeded directly in Supabase) is reflected, then push so any
      // product only known locally reaches Firestore too.
      await provider.pullStockFromFirestore();
      await provider.pullNewProductsFromFirestore();
      await provider.syncAllToFirestore();
    });
  }

  Future<void> _openQuantityDialog(BuildContext context, Product product) async {
    final cart = context.read<CartProvider>();
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

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.isAdmin ? 'KaataGo (Admin)' : 'KaataGo (Kasir)'),
        actions: [
          if (widget.isAdmin)
            IconButton(
              icon: const Icon(Icons.inventory_2_outlined),
              tooltip: 'Kelola Produk',
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const ProductListScreen()),
              ),
            ),
          IconButton(
            icon: const Icon(Icons.receipt_long_outlined),
            tooltip: 'Riwayat Transaksi',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(
                  builder: (_) => const TransactionHistoryScreen()),
            ),
          ),
          if (widget.isAdmin)
            IconButton(
              icon: const Icon(Icons.list_alt_outlined),
              tooltip: 'Pesanan Masuk',
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const EmployeeOrdersScreen()),
              ),
            ),
          if (widget.isAdmin)
            IconButton(
              icon: const Icon(Icons.settings_outlined),
              tooltip: 'Pengaturan',
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const SettingsMenuScreen()),
              ),
            ),
          if (!widget.isAdmin)
            IconButton(
              icon: const Icon(Icons.logout),
              tooltip: 'Keluar',
              onPressed: () async {
                await context.read<AuthProvider>().signOut();
                if (!context.mounted) return;
                Navigator.of(context).popUntil((r) => r.isFirst);
              },
            ),
        ],
      ),
      body: Consumer2<ProductProvider, CartProvider>(
        builder: (context, provider, cart, _) {
          final products = provider.products;
          if (products.isEmpty) {
            return const Center(
              child: Text('Belum ada produk.\nTambah dulu lewat ikon rak di atas.',
                  textAlign: TextAlign.center),
            );
          }
          return ProductCategoryList(
            products: products,
            quantityOf: cart.quantityOf,
            onTapProduct: (p) => _openQuantityDialog(context, p),
          );
        },
      ),
      bottomNavigationBar: Consumer<CartProvider>(
        builder: (context, cart, _) {
          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: FilledButton(
                onPressed: cart.items.isEmpty
                    ? null
                    : () => Navigator.of(context).push(
                          MaterialPageRoute(builder: (_) => const CheckoutScreen()),
                        ),
                child: Text(
                  cart.items.isEmpty
                      ? 'Keranjang kosong'
                      : 'Bayar (${cart.itemCount}) • ${currency.format(cart.total)}',
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
