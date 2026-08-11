import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../db/restaurant_repository.dart';
import '../models/product.dart';
import '../providers/auth_provider.dart';
import '../providers/cart_provider.dart';
import '../providers/product_provider.dart';
import '../widgets/cart_bottom_bar.dart';
import '../widgets/product_category_list.dart';
import '../widgets/quantity_dialog.dart';
import 'checkout_screen.dart';

/// The actual ordering screen: tap products to add to cart, then go to
/// checkout. Reached via a menu tile on [AdminHomeScreen] or
/// [KasirHomeScreen] — both hub screens are where Riwayat Transaksi,
/// other menus, and Logout live instead, keeping this screen's app bar
/// uncluttered. The back button returns to whichever hub opened it.
class PosHomeScreen extends StatefulWidget {
  const PosHomeScreen({super.key});

  @override
  State<PosHomeScreen> createState() => _PosHomeScreenState();
}

class _PosHomeScreenState extends State<PosHomeScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final restoId = context.read<AuthProvider>().restoId;
      await context.read<ProductProvider>().syncWithResto(restoId);
      await _loadRates(restoId);
    });
  }

  /// Menu prices are shown inclusive of the resto's PPN, so the cart has
  /// to know the rates before it can price anything.
  Future<void> _loadRates(String? restoId) async {
    if (restoId == null) return;
    try {
      final resto = await RestaurantRepository().getOnce(restoId);
      if (!mounted || resto == null) return;
      context.read<CartProvider>()
          .setRates(ppn: resto.ppnPercent, service: resto.servicePercent);
    } catch (_) {
      // Offline — prices fall back to the stored originals.
    }
  }

  /// Always adds a *new* line rather than editing whatever's already in
  /// the cart: one nasi goreng pedas and one tidak pedas are two
  /// different things, and the old behaviour overwrote the first with
  /// the second. Editing an existing line happens from the cart itself.
  Future<void> _openQuantityDialog(BuildContext context, Product product) async {
    final cart = context.read<CartProvider>();
    final result = await showDialog<QuantityDialogResult>(
      context: context,
      builder: (_) => QuantityDialog(
        product: product,
        ppnPercent: cart.ppnPercent,
      ),
    );
    if (result == null) return;
    cart.addLine(
      product,
      quantity: result.quantity,
      selectedLevels: result.selectedLevels,
      notes: result.notes,
    );
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final employeeName = auth.employeeName?.isNotEmpty == true ? auth.employeeName! : 'Kasir';

    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 60,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(employeeName, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            Text(
              '${auth.roleLabel ?? 'Kasir'} • ${auth.user?.email ?? ''}',
              style: const TextStyle(fontSize: 11, color: Colors.white70),
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
      body: Consumer2<ProductProvider, CartProvider>(
        builder: (context, provider, cart, _) {
          final products = provider.products;
          if (products.isEmpty) {
            return const Center(
              child: Text('Belum ada produk.\nTambah dulu lewat menu Kelola Produk.',
                  textAlign: TextAlign.center),
            );
          }
          return ProductCategoryList(
            products: products,
            quantityOf: cart.quantityOf,
            ppnPercent: cart.ppnPercent,
            onTapProduct: (p) => _openQuantityDialog(context, p),
          );
        },
      ),
      bottomNavigationBar: Consumer<CartProvider>(
        builder: (context, cart, _) {
          return CartBottomBar(
            itemCount: cart.itemCount,
            total: cart.total,
            actionLabel: 'Bayar',
            actionIcon: Icons.point_of_sale_outlined,
            onPressed: cart.items.isEmpty
                ? null
                : () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const CheckoutScreen()),
                    ),
          );
        },
      ),
    );
  }
}
