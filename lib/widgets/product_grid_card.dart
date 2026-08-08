import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/product.dart';
import '../theme.dart';

/// One product tile in the ordering grid — used by Kasir/Admin and
/// Customer alike. Always has a visible light-grey outline (so it
/// doesn't look washed-out/transparent against the page background),
/// and switches to a solid brand-colored outline + tint + quantity badge
/// once it's selected in the cart. Shows the product photo on top when
/// one's been uploaded.
class ProductGridCard extends StatelessWidget {
  final Product product;
  final int quantityInCart;
  final VoidCallback? onTap;

  const ProductGridCard({
    super.key,
    required this.product,
    required this.quantityInCart,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final currency = NumberFormat.currency(
      locale: 'id_ID',
      symbol: 'Rp ',
      decimalDigits: 0,
    );
    final selected = quantityInCart > 0;
    final inStock = product.stock > 0;
    final hasPhoto = product.photoBase64 != null;

    return Card(
      color: selected ? KaataTheme.brand.withOpacity(0.06) : Colors.white,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color: selected ? KaataTheme.brand : Colors.grey.shade300,
          width: selected ? 2 : 1,
        ),
      ),
      child: Stack(
        children: [
          InkWell(
            onTap: inStock ? onTap : null,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // The photo takes whatever space is left over — the text
                // block below is sized to its own content (mainAxisSize.min)
                // instead of a fixed flex share, so it can never overflow
                // regardless of how tall the grid cell ends up being.
                if (hasPhoto)
                  Expanded(
                    child: Image.memory(
                      base64Decode(product.photoBase64!),
                      width: double.infinity,
                      fit: BoxFit.cover,
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.all(10),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        product.name,
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        currency.format(product.price),
                        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        inStock ? 'Stok: ${product.stock}' : 'Stok habis',
                        style: TextStyle(
                          color: inStock ? Colors.grey.shade600 : Colors.red,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (selected)
            Positioned(
              top: 6,
              right: 6,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: const BoxDecoration(
                  color: KaataTheme.brand,
                  shape: BoxShape.circle,
                ),
                constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
                child: Text(
                  '$quantityInCart',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
