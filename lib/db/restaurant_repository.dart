import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/restaurant.dart';

class RestaurantRepository {
  final _client = Supabase.instance.client;

  Future<Restaurant?> getOnce(String id) async {
    final rows = await _client.from('restaurants').select().eq('id', id).limit(1);
    if (rows.isEmpty) return null;
    return Restaurant.fromMap(id, rows.first);
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
