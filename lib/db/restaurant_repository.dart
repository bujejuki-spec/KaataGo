import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/restaurant.dart';

class RestaurantRepository {
  final _client = Supabase.instance.client;

  Future<Restaurant?> getOnce(String id) async {
    final rows = await _client.from('restaurants').select().eq('id', id).limit(1);
    if (rows.isEmpty) return null;
    return Restaurant.fromMap(id, rows.first);
  }

  /// All restaurants (active or not) — used by Super Admin screens
  /// (resto picker when adding an employee, restaurant list).
  Future<List<Restaurant>> getAll() async {
    final rows = await _client.from('restaurants').select().order('name');
    return rows.map((r) => Restaurant.fromMap(r['id'] as String, r)).toList();
  }

  /// Only active restaurants — used by the customer's "Pilih Resto" list,
  /// so a deactivated resto can't be picked to order from.
  Future<List<Restaurant>> getAllActive() async {
    final rows = await _client.from('restaurants').select().eq('active', true).order('name');
    return rows.map((r) => Restaurant.fromMap(r['id'] as String, r)).toList();
  }

  Future<void> setActive(String id, bool active) async {
    await _client.from('restaurants').update({'active': active}).eq('id', id);
  }

  Stream<Restaurant?> watch(String id) {
    return _client
        .from('restaurants')
        .stream(primaryKey: ['id'])
        .eq('id', id)
        .map((rows) => rows.isEmpty ? null : Restaurant.fromMap(id, rows.first));
  }

  Future<void> save(Restaurant restaurant) async {
    await _client.from('restaurants').upsert({
      'id': restaurant.id,
      ...restaurant.toMap(),
    });
  }
}
