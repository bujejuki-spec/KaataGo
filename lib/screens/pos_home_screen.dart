import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../db/restaurant_repository.dart';
import '../models/cart_item.dart';
import '../models/product.dart';
import '../providers/auth_provider.dart';
import '../providers/cart_provider.dart';
import '../providers/product_provider.dart';
import '../widgets/cart_bottom_bar.dart';
import '../widgets/product_category_list.dart';
import '../widgets/product_lines_sheet.dart';
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

  /// Menu yang belum ada di keranjang langsung membuka popup jumlah.
  /// Yang sudah ada membuka daftar barisnya, supaya jumlahnya bisa
  /// dikurangi atau dihapus tanpa harus maju dulu ke keranjang — di
  /// depan menu inilah orang berubah pikiran.
  Future<void> _onTapProduct(BuildContext context, Product product) async {
    final cart = context.read<CartProvider>();
    if (cart.linesOf(product.id).isEmpty) {
      await _addLine(context, product);
      return;
    }
    await _openLinesSheet(context, product);
  }

  Future<void> _addLine(BuildContext context, Product product) async {
    final cart = context.read<CartProvider>();
    final result = await showDialog<QuantityDialogResult>(
      context: context,
      builder: (_) => QuantityDialog(product: product, ppnPercent: cart.ppnPercent),
    );
    if (result == null) return;
    cart.addLine(
      product,
      quantity: result.quantity,
      selectedLevels: result.selectedLevels,
      notes: result.notes,
    );
  }

  Future<void> _editLine(BuildContext context, CartItem line) async {
    final cart = context.read<CartProvider>();
    final result = await showDialog<QuantityDialogResult>(
      context: context,
      builder: (_) => QuantityDialog(
        product: line.product,
        initialQuantity: line.quantity,
        initialLevels: line.selectedLevels,
        initialNotes: line.notes,
        ppnPercent: cart.ppnPercent,
        editing: true,
      ),
    );
    if (result == null) return;
    cart.updateLine(
      line.lineId,
      quantity: result.quantity,
      selectedLevels: result.selectedLevels,
      notes: result.notes,
    );
  }

  Future<void> _openLinesSheet(BuildContext context, Product product) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (sheetContext) => Consumer<CartProvider>(
        builder: (_, cart, __) {
          final lines = cart.linesOf(product.id);
          // Baris terakhir dihapus berarti tidak ada lagi yang bisa
          // diatur — menutup sendiri lebih baik daripada menyisakan
          // panel kosong yang harus ditutup manual.
          if (lines.isEmpty) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (Navigator.of(sheetContext).canPop()) Navigator.of(sheetContext).pop();
            });
            return const SizedBox.shrink();
          }
          return ProductLinesSheet(
            product: product,
            lines: lines,
            unitPriceOf: (l) => cart.menuSubtotalOf(l) ~/ l.quantity,
            lineTotalOf: cart.menuSubtotalOf,
            onIncrement: cart.incrementLine,
            onDecrement: cart.decrementLine,
            onDelete: cart.removeLine,
            onEdit: (line) => _editLine(sheetContext, line),
            onAddVariant: () {
              Navigator.pop(sheetContext);
              _addLine(context, product);
            },
          );
        },
      ),
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
            onTapProduct: (p) => _onTapProduct(context, p),
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
