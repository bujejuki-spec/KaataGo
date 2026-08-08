/// Common variant/"level" groups used by Indonesian F&B outlets (spice
/// level, sugar level, ice level, etc.) — hardcoded like
/// [kRestaurantCategories] since these are a well-known fixed set rather
/// than something each restaurant needs to type in from scratch.
///
/// A product can be tagged with any subset of these group names (see
/// [Product.levelGroups]); at order time the customer/kasir/admin then
/// picks one option per tagged group.
const Map<String, List<String>> kLevelGroups = {
  'Level Pedas': ['Tidak Pedas', 'Sedang', 'Pedas', 'Extra Pedas'],
  'Level Gula': ['Normal', 'Kurang Manis', 'Setengah Manis', 'Tanpa Gula'],
  'Level Es': ['Normal', 'Less Ice', 'No Ice'],
  'Suhu': ['Panas', 'Dingin'],
  'Ukuran': ['Regular', 'Large'],
};
