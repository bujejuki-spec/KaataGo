import 'dart:convert';

class Product {
  final String id;
  final String name;
  final String category;
  final int price; // stored in Rupiah, no decimals
  final int stock;
  final String? description;

  /// Base64-encoded JPEG, stored directly in the row/doc — same
  /// no-separate-storage-service pattern used for customer profile
  /// photos. Kept small via resize/compress before encoding (see
  /// ProductFormScreen).
  final String? photoBase64;

  /// Names of the [kLevelGroups] this product offers (e.g. "Level Pedas",
  /// "Level Gula") — empty if it has no variant options. Shown as
  /// required dropdowns in the quantity/order dialog for whoever is
  /// ordering (customer, kasir, or admin).
  final List<String> levelGroups;

  /// Extra price (can be negative) added on top of [price] when a given
  /// option is picked, keyed by group then option — e.g.
  /// {"Ukuran": {"Regular": 0, "Large": 5000}}. Groups/options with no
  /// entry here are treated as 0 (no price change). Mainly used for
  /// "Ukuran" (size), but works for any level group.
  final Map<String, Map<String, int>> levelPrices;

  Product({
    required this.id,
    required this.name,
    required this.category,
    required this.price,
    required this.stock,
    this.description,
    this.photoBase64,
    this.levelGroups = const [],
    this.levelPrices = const {},
  });

  /// Extra price for the chosen [option] within [group], or 0 if unset.
  int priceDeltaFor(String group, String option) =>
      levelPrices[group]?[option] ?? 0;

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'category': category,
      'price': price,
      'stock': stock,
      'description': description,
      'photo_base64': photoBase64,
      'level_groups': levelGroups.isEmpty ? null : levelGroups.join(','),
      'level_prices': levelPrices.isEmpty ? null : jsonEncode(levelPrices),
    };
  }

  factory Product.fromMap(Map<String, dynamic> map) {
    final rawLevels = map['level_groups'] as String?;
    final rawPrices = map['level_prices'] as String?;
    return Product(
      id: map['id'] as String,
      name: map['name'] as String,
      category: map['category'] as String,
      price: (map['price'] as num).toInt(),
      stock: (map['stock'] as num).toInt(),
      description: map['description'] as String?,
      photoBase64: map['photo_base64'] as String?,
      levelGroups: (rawLevels == null || rawLevels.isEmpty)
          ? const []
          : rawLevels.split(','),
      levelPrices: (rawPrices == null || rawPrices.isEmpty)
          ? const {}
          : (jsonDecode(rawPrices) as Map<String, dynamic>).map(
              (group, options) => MapEntry(
                group,
                (options as Map<String, dynamic>)
                    .map((opt, delta) => MapEntry(opt, (delta as num).toInt())),
              ),
            ),
    );
  }

  /// Sentinel used so `copyWith` can tell "not passed" apart from
  /// "explicitly set to null" (e.g. clearing a photo/description).
  static const _unset = Object();

  Product copyWith({
    String? name,
    String? category,
    int? price,
    int? stock,
    Object? description = _unset,
    Object? photoBase64 = _unset,
    List<String>? levelGroups,
    Map<String, Map<String, int>>? levelPrices,
  }) {
    return Product(
      id: id,
      name: name ?? this.name,
      category: category ?? this.category,
      price: price ?? this.price,
      stock: stock ?? this.stock,
      description:
          identical(description, _unset) ? this.description : description as String?,
      photoBase64:
          identical(photoBase64, _unset) ? this.photoBase64 : photoBase64 as String?,
      levelGroups: levelGroups ?? this.levelGroups,
      levelPrices: levelPrices ?? this.levelPrices,
    );
  }
}
