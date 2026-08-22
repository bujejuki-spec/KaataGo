import '../db/discount_repository.dart';
import '../db/product_review_repository.dart';
import '../models/discount.dart';
import '../models/product_review.dart';

/// Dua hal yang menempel pada menu tapi tidak tersimpan di menunya:
/// promo yang sedang berlaku, dan bintang berikut angka terjualnya.
///
/// Dikumpulkan di satu tempat karena dua layar yang berbeda — kasir dan
/// HP pelanggan — menampilkan kartu menu yang sama persis. Menyalin cara
/// memuatnya ke keduanya berarti dua tempat yang harus selalu sepakat,
/// dan yang satu akan tertinggal saat yang lain diperbaiki.
class MenuMeta {
  final Set<String> diskonProductIds;
  final Map<String, ProductStats> stats;

  const MenuMeta({this.diskonProductIds = const {}, this.stats = const {}});

  static const kosong = MenuMeta();
}

/// Memuat keduanya. Gagal berarti kosong, bukan galat yang dilempar ke
/// layar: label dan bintang adalah tambahan, dan menu yang menolak
/// tampil karena angka terjualnya tidak bisa dihitung jauh lebih buruk
/// daripada menu tanpa angka.
Future<MenuMeta> muatMenuMeta(String restoId) async {
  final hasil = await Future.wait([
    _diskon(restoId),
    _stats(restoId),
  ]);
  return MenuMeta(
    diskonProductIds: hasil[0] as Set<String>,
    stats: hasil[1] as Map<String, ProductStats>,
  );
}

Future<Set<String>> _diskon(String restoId) async {
  try {
    final live = await DiscountRepository().liveForResto(restoId);
    return {
      for (final d in live)
        if (d.basis == DiscountBasis.products)
          for (final i in d.items) i.productId,
    };
  } catch (_) {
    return const {};
  }
}

Future<Map<String, ProductStats>> _stats(String restoId) async {
  try {
    return await ProductReviewRepository().statistik(restoId);
  } catch (_) {
    return const {};
  }
}
