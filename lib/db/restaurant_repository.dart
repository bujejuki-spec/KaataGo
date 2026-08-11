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

  /// Creates or replaces a restaurant. Insert is super_admin-only under
  /// RLS, so an Admin editing their own resto must use [update] instead:
  /// an upsert is an INSERT ... ON CONFLICT, and Postgres checks the
  /// insert policy first — which rejects them before the update policy
  /// is ever consulted.
  Future<void> save(Restaurant restaurant) async {
    await _client.from('restaurants').upsert({
      'id': restaurant.id,
      ...restaurant.toMap(),
    });
  }

  /// Edits an existing restaurant. Allowed for that resto's Admin as
  /// well as super_admin.
  Future<void> update(Restaurant restaurant) async {
    await _client
        .from('restaurants')
        .update(restaurant.toMap())
        .eq('id', restaurant.id);
  }

  /// Sets the PPN and service rates. Goes through an RPC rather than a
  /// plain update so Finance can change these two columns without being
  /// granted write access to the rest of the restaurant row.
  Future<void> setTaxRates(
    String restoId, {
    required double ppnPercent,
    required double servicePercent,
  }) async {
    await _client.rpc('set_tax_rates', params: {
      'p_resto_id': restoId,
      'p_ppn_percent': ppnPercent,
      'p_service_percent': servicePercent,
    });
  }
}
