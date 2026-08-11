/// Hardcoded restaurant category options, roughly matching the
/// taxonomy used by GoFood/GrabFood/ShopeeFood-style apps in Indonesia.
const kRestaurantCategories = [
  'Makanan Berat',
  'Cepat Saji',
  'Kopi & Kafe',
  'Teh & Minuman',
  'Dessert & Kue',
  'Bakery & Roti',
  'Snack & Cemilan',
  'Seafood',
  'Ayam & Bebek',
  'Mie & Bakmi',
  'Sate & Bakar-bakaran',
  'Bubur & Soto',
  'Masakan Padang',
  'Masakan Sunda',
  'Masakan Jawa',
  'Chinese Food',
  'Japanese Food',
  'Korean Food',
  'Western Food',
  'Vegetarian & Vegan',
  'Warung/Kaki Lima',
  'Restoran Keluarga',
  'Fine Dining',
];

class Restaurant {
  final String id;
  final String name;
  final String address;
  final String? category;
  final bool active;

  /// Contact number printed on the receipt. Optional.
  final String? phone;

  /// Tax and service rates as percentages — 11 means 11%. Menu prices
  /// are shown tax-inclusive, so these are what the receipt unwinds the
  /// displayed price with. Zero means the charge doesn't apply.
  final double ppnPercent;
  final double servicePercent;

  /// Optional store logo, base64-encoded. Shared between Super Admin and
  /// Admin — whoever uploads it, either can replace or clear it.
  final String? logoBase64;

  Restaurant({
    required this.id,
    required this.name,
    required this.address,
    this.category,
    this.active = true,
    this.logoBase64,
    this.phone,
    this.ppnPercent = 0,
    this.servicePercent = 0,
  });

  Map<String, dynamic> toMap() => {
        'name': name,
        'address': address,
        if (category != null) 'category': category,
        'active': active,
        // Always sent, even when null — an omitted key leaves the old
        // logo in place, making removal impossible.
        'logo_base64': logoBase64,
        // Always sent so clearing it actually clears it.
        'phone': phone,
        'ppn_percent': ppnPercent,
        'service_percent': servicePercent,
      };

  factory Restaurant.fromMap(String id, Map<String, dynamic> map) {
    return Restaurant(
      id: id,
      name: map['name'] as String? ?? 'Resto',
      address: map['address'] as String? ?? '',
      category: map['category'] as String?,
      active: map['active'] as bool? ?? true,
      logoBase64: map['logo_base64'] as String?,
      phone: map['phone'] as String?,
      ppnPercent: (map['ppn_percent'] as num?)?.toDouble() ?? 0,
      servicePercent: (map['service_percent'] as num?)?.toDouble() ?? 0,
    );
  }
}
