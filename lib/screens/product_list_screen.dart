import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../providers/auth_provider.dart';
import '../providers/category_provider.dart';
import '../providers/product_provider.dart';
import 'category_management_screen.dart';
import 'product_form_screen.dart';
import '../widgets/dialog_actions.dart';
import '../widgets/responsive.dart';

class ProductListScreen extends StatefulWidget {
  const ProductListScreen({super.key});

  @override
  State<ProductListScreen> createState() => _ProductListScreenState();
}

class _ProductListScreenState extends State<ProductListScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final restoId = context.read<AuthProvider>().restoId;

      final categories = context.read<CategoryProvider>();
      categories.restoId = restoId;
      await categories.load();
      await categories.pullNewFromSupabase();
      await categories.syncAllToSupabase();

      if (!mounted) return;
      // Products used to be synced only by the cashier screen. Now that
      // Kelola Produk is its own menu entry on the Admin hub, it can be
      // opened without ever going there — which left this list showing
      // whatever happened to be in the local database, i.e. nothing at
      // all on a freshly installed device.
      await context.read<ProductProvider>().syncWithResto(restoId);
    });
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Kelola Produk'),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Produk'),
              Tab(text: 'Kategori'),
            ],
          ),
        ),
        body: const TabBarView(
          children: [
            _ProductTab(),
            CategoryManagementScreen(),
          ],
        ),
      ),
    );
  }
}

class _ProductTab extends StatelessWidget {
  const _ProductTab();

  @override
  Widget build(BuildContext context) {
    final currency = NumberFormat.currency(
      locale: 'id_ID',
      symbol: 'Rp ',
      decimalDigits: 0,
    );

    return Scaffold(
      body: Consumer<ProductProvider>(
        builder: (context, provider, _) {
          final products = provider.products;
          if (products.isEmpty) {
            return const Center(child: Text('Belum ada produk. Tambah dulu yuk.'));
          }
          return ListView.builder(
            padding: const EdgeInsets.only(bottom: kFabSafeBottom),
            itemCount: products.length,
            itemBuilder: (context, index) {
              final p = products[index];
              return ListTile(
                title: Text(p.name),
                subtitle: Text('${p.category} • Stok: ${p.stock}'),
                trailing: Text(currency.format(p.price)),
                onTap: () {
                  Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => ProductFormScreen(existing: p),
                  ));
                },
                onLongPress: () async {
                  final confirm = await showDialog<bool>(
                    context: context,
                    builder: (_) => AlertDialog(
                      title: const Text('Hapus produk?'),
                      content: Text('Hapus "${p.name}"?'),
                      actions: [
                        DialogActions(
                          confirmLabel: 'Hapus',
                          destructive: true,
                          onConfirm: () => Navigator.pop(context, true),
                        ),
                      ],
                      actionsAlignment: MainAxisAlignment.center,
                    ),
                  );
                  if (confirm == true) {
                    await provider.deleteProduct(p.id);
                  }
                },
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => const ProductFormScreen(),
          ));
        },
        child: const Icon(Icons.add),
      ),
    );
  }
}
