import 'package:flutter/material.dart';

import '../models/product.dart';
import '../theme.dart';
import 'product_grid_card.dart';

/// Groups products by category into collapsible sections — used by
/// Kasir/Admin and Customer's ordering screens alike so both share the
/// exact same grouping/expand behavior and card look.
class ProductCategoryList extends StatelessWidget {
  final List<Product> products;
  final int Function(String productId) quantityOf;
  final void Function(Product product) onTapProduct;

  const ProductCategoryList({
    super.key,
    required this.products,
    required this.quantityOf,
    required this.onTapProduct,
  });

  @override
  Widget build(BuildContext context) {
    final byCategory = <String, List<Product>>{};
    for (final p in products) {
      byCategory.putIfAbsent(p.category, () => []).add(p);
    }
    final categoryNames = byCategory.keys.toList()..sort();

    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: categoryNames.length,
      itemBuilder: (context, index) {
        final category = categoryNames[index];
        final items = byCategory[category]!;

        return Theme(
          // Removes the default divider lines ExpansionTile draws above/below.
          data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            initiallyExpanded: true,
            title: Text(
              '$category (${items.length})',
              style: const TextStyle(fontWeight: FontWeight.bold, color: KaataTheme.brandDark),
            ),
            childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            children: [
              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  childAspectRatio: 1.3,
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                ),
                itemCount: items.length,
                itemBuilder: (context, i) {
                  final product = items[i];
                  return ProductGridCard(
                    product: product,
                    quantityInCart: quantityOf(product.id),
                    onTap: () => onTapProduct(product),
                  );
                },
              ),
            ],
          ),
        );
      },
    );
  }
}
