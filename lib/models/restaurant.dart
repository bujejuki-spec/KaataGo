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

  Restaurant({
    required this.id,
    required this.name,
    required this.address,
    this.category,
  });

  Map<String, dynamic> toMap() => {
        'name': name,
        'address': address,
        if (category != null) 'category': category,
      };

  factory Restaurant.fromMap(String id, Map<String, dynamic> map) {
    return Restaurant(
      id: id,
      name: map['name'] as String? ?? 'Resto',
      address: map['address'] as String? ?? '',
      category: map['category'] as String?,
    );
  }
}
