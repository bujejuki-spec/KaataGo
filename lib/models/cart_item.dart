import 'product.dart';

class CartItem {
  final Product product;
  int quantity;

  /// Chosen option per level group (e.g. {"Level Pedas": "Pedas"}) — one
  /// entry per group in [Product.levelGroups].
  Map<String, String> selectedLevels;

  /// Free-text note from whoever is ordering (customer/kasir/admin), e.g.
  /// "tanpa bawang" — always optional, on top of the level selections.
  String? notes;

  CartItem({
    required this.product,
    this.quantity = 1,
    Map<String, String>? selectedLevels,
    this.notes,
  }) : selectedLevels = selectedLevels ?? {};

  /// Unit price after adding any per-level price deltas (e.g. "Ukuran:
  /// Large" adding Rp 5.000 on top of the base price).
  int get effectiveUnitPrice =>
      product.price +
      selectedLevels.entries
          .fold(0, (sum, e) => sum + product.priceDeltaFor(e.key, e.value));

  int get subtotal => effectiveUnitPrice * quantity;

  /// Combined human-readable line for receipts/kitchen tickets, e.g.
  /// "Level Pedas: Pedas, Level Gula: Kurang Manis • tanpa bawang".
  String? get noteSummary {
    final parts = <String>[
      for (final entry in selectedLevels.entries) '${entry.key}: ${entry.value}',
    ];
    final combined = parts.join(', ');
    final trimmedNotes = notes?.trim() ?? '';
    if (combined.isEmpty && trimmedNotes.isEmpty) return null;
    if (combined.isEmpty) return trimmedNotes;
    if (trimmedNotes.isEmpty) return combined;
    return '$combined • $trimmedNotes';
  }
}
