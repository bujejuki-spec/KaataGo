import 'package:flutter/material.dart';

import '../models/product.dart';
import '../theme.dart';
import 'product_grid_card.dart';

/// Groups products by category into collapsible sections — used by
/// Kasir/Admin and Customer's ordering screens alike so both share the
/// exact same grouping/expand behavior and card look.
///
/// Cards are portrait-shaped so the photo gets real room, and the column
/// count follows the available width rather than being pinned at 2 — on a
/// tablet (a likely Kasir setup) two stretched columns looked wrong.
class ProductCategoryList extends StatelessWidget {
  final List<Product> products;
  final int Function(String productId) quantityOf;
  final void Function(Product product) onTapProduct;
  final double ppnPercent;

  const ProductCategoryList({
    super.key,
    required this.products,
    required this.quantityOf,
    required this.onTapProduct,
    this.ppnPercent = 0,
  });

  @override
  Widget build(BuildContext context) {
    final byCategory = <String, List<Product>>{};
    for (final p in products) {
      byCategory.putIfAbsent(p.category, () => []).add(p);
    }
    final categoryNames = byCategory.keys.toList()..sort();

    return LayoutBuilder(
      builder: (context, constraints) {
        // ~170px per card keeps the photo legible; clamped so a phone
        // always gets 2 and a wide tablet never goes past 5.
        final columns = (constraints.maxWidth / 190).floor().clamp(2, 5);

        return ListView.builder(
          padding: const EdgeInsets.only(top: 4, bottom: 12),
          itemCount: categoryNames.length,
          itemBuilder: (context, index) {
            final category = categoryNames[index];
            final items = byCategory[category]!;

            return Theme(
              // Removes the default divider lines ExpansionTile draws
              // above/below.
              data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
              child: ExpansionTile(
                initiallyExpanded: false,
                tilePadding: const EdgeInsets.symmetric(horizontal: 16),
                title: Row(
                  children: [
                    Container(
                      width: 4,
                      height: 18,
                      decoration: BoxDecoration(
                        color: KaataTheme.brand,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Flexible(
                      child: Text(
                        category,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                          color: KaataTheme.brandDark,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: KaataTheme.brand.withOpacity(0.10),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        '${items.length}',
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: KaataTheme.brand,
                        ),
                      ),
                    ),
                  ],
                ),
                childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 16),
                children: [
                  GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: columns,
                      // Portrait: photo on top, name/price beneath. Wider
                      // than this and the photo flattens into a strip.
                      childAspectRatio: 0.78,
                      crossAxisSpacing: 12,
                      mainAxisSpacing: 12,
                    ),
                    itemCount: items.length,
                    itemBuilder: (context, i) {
                      final product = items[i];
                      return ProductGridCard(
                        product: product,
                        quantityInCart: quantityOf(product.id),
                        ppnPercent: ppnPercent,
                        onTap: () => onTapProduct(product),
                      );
                    },
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}
