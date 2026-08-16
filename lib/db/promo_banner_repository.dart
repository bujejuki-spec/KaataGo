import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/promo_banner.dart';

class PromoBannerRepository {
  final _client = Supabase.instance.client;

  /// Semua banner resto, termasuk yang nonaktif — untuk layar admin.
  Future<List<PromoBanner>> getForResto(String restoId) async {
    final rows = await _client
        .from('promo_banners')
        .select()
        .eq('resto_id', restoId)
        .order('sort_order')
        .order('created_at');
    // Masa berlakunya disaring di sini, bukan lewat `where` tanggal:
    // aturan "hari terakhir ikut berlaku penuh" sudah tertulis satu kali
    // di PromoPeriod, dan menulis ulang aturan yang sama sebagai SQL
    // berarti dua tempat yang harus selalu sepakat.
    return rows
        .map((r) => PromoBanner.fromMap(r))
        .where((b) => b.isLive())
        .toList();
  }

  /// Hanya yang aktif — untuk customer.
  Future<List<PromoBanner>> activeForResto(String restoId) async {
    final rows = await _client
        .from('promo_banners')
        .select()
        .eq('resto_id', restoId)
        .eq('active', true)
        .order('sort_order')
        .order('created_at');
    return rows.map((r) => PromoBanner.fromMap(r)).toList();
  }

  Future<void> create(PromoBanner banner) async {
    await _client.from('promo_banners').insert(banner.toMap());
  }

  Future<void> update(PromoBanner banner) async {
    await _client.from('promo_banners').update(banner.toMap()).eq('id', banner.id);
  }

  Future<void> setActive(String id, bool active) async {
    await _client.from('promo_banners').update({'active': active}).eq('id', id);
  }

  /// Menyimpan urutan baru sekaligus, supaya daftar tidak sempat berada
  /// dalam keadaan setengah tersusun kalau salah satu penulisan gagal.
  Future<void> reorder(List<PromoBanner> ordered) async {
    for (var i = 0; i < ordered.length; i++) {
      await _client.from('promo_banners').update({'sort_order': i}).eq('id', ordered[i].id);
    }
  }

  Future<void> delete(String id) async {
    await _client.from('promo_banners').delete().eq('id', id);
  }
}
