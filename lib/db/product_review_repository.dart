import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/product_review.dart';

class ProductReviewRepository {
  final _client = Supabase.instance.client;

  Future<List<ProductReview>> forProduct(String productId) async {
    final rows = await _client
        .from('product_reviews')
        .select()
        .eq('product_id', productId)
        .order('created_at', ascending: false);
    return rows.map((r) => ProductReview.fromMap(r)).toList();
  }

  /// Seluruh penilaian menu di satu merchant.
  ///
  /// Dipakai layar Info Merchant — tempat pegawai membaca keluhannya,
  /// dan calon pelanggan membaca pujiannya. Komentar yang tersimpan tapi
  /// tidak punya satu pun layar yang menampilkannya sama saja dengan
  /// meminta orang menulis ke tempat sampah.
  Future<List<ProductReview>> forResto(String restoId) async {
    final rows = await _client
        .from('product_reviews')
        .select()
        .eq('resto_id', restoId)
        .order('created_at', ascending: false);
    return rows.map((r) => ProductReview.fromMap(r)).toList();
  }

  /// Penilaian yang sudah pernah ditulis orang ini untuk menu itu.
  Future<ProductReview?> mine(String productId) async {
    final email = _client.auth.currentUser?.email;
    if (email == null) return null;
    final rows = await _client
        .from('product_reviews')
        .select()
        .eq('product_id', productId)
        .eq('customer_email', email)
        .limit(1);
    return rows.isEmpty ? null : ProductReview.fromMap(rows.first);
  }

  /// Menyimpan penilaian, menimpa punyanya sendiri kalau sudah ada.
  ///
  /// Yang memesan nasi goreng sepuluh kali tetap punya satu suara.
  Future<void> simpan({
    required String restoId,
    required String productId,
    required String customerName,
    required int rating,
    String? comment,
  }) async {
    final email = _client.auth.currentUser?.email;
    if (email == null) return;
    await _client.from('product_reviews').upsert({
      'resto_id': restoId,
      'product_id': productId,
      'customer_email': email,
      'customer_name': customerName,
      'rating': rating,
      'comment': (comment ?? '').trim().isEmpty ? null : comment!.trim(),
      'updated_at': DateTime.now().toIso8601String(),
    }, onConflict: 'product_id,customer_email');
  }

  /// Bintang dan angka terjual seluruh menu satu merchant sekaligus.
  ///
  /// Dihitung server dalam satu panggilan. Layar menu menampilkan
  /// puluhan kartu; satu panggilan per kartu berarti puluhan permintaan
  /// tiap kali satu kategori dibuka.
  Future<Map<String, ProductStats>> statistik(String restoId) async {
    final rows =
        await _client.rpc('product_stats', params: {'p_resto_id': restoId});
    final hasil = <String, ProductStats>{};
    for (final r in (rows as List? ?? const [])) {
      final m = Map<String, dynamic>.from(r as Map);
      hasil[m['product_id'].toString()] = ProductStats(
        rata: (m['rata'] as num?)?.toDouble() ?? 0,
        jumlah: (m['jumlah'] as num?)?.toInt() ?? 0,
        terjual: (m['terjual'] as num?)?.toInt() ?? 0,
      );
    }
    return hasil;
  }
}
