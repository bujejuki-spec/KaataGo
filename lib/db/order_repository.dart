import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/customer_order.dart';

/// Supabase-backed repository for orders. This is the bridge between
/// Kasir/Customer (who place orders) and Chef (who tracks kitchen status)
/// — an order written here shows up live everywhere it's watched, via
/// Postgres realtime subscriptions.
class OrderRepository {
  final _client = Supabase.instance.client;

  Future<String> create(CustomerOrder order) async {
    final row = await _client.from('orders').insert(order.toMap()).select().single();
    return row['id'] as String;
  }

  /// Confirms the customer's (dummy) QRIS payment. Goes through the
  /// `mark_order_paid` RPC (SECURITY DEFINER) instead of a direct table
  /// UPDATE — a guest customer has no employee RLS privileges to update
  /// `orders` directly, and the RPC's own guardrails (source='customer',
  /// pending→paid only) keep this safe without reopening that up.
  Future<void> markPaid(String orderId) async {
    await _client.rpc('mark_order_paid', params: {'p_order_id': orderId});
  }

  Future<void> updateKitchenStatus(String orderId, KitchenStatus status) async {
    await _client.from('orders').update({'kitchen_status': status.name}).eq('id', orderId);
  }

  /// Live stream of all orders for one restaurant, newest first. Used by
  /// the Admin/Chef "Pesanan Masuk" screens.
  Stream<List<CustomerOrder>> watchAll(String restoId) {
    return _client
        .from('orders')
        .stream(primaryKey: ['id'])
        .eq('resto_id', restoId)
        .order('created_at', ascending: false)
        .map((rows) => rows.map((r) => CustomerOrder.fromMap(r)).toList());
  }

  /// Live stream of orders belonging to one customer session (the "parent"
  /// id assigned right after scanning a table QR) — used by the customer's
  /// own order-status screen so they can track progress without an account.
  Stream<List<CustomerOrder>> watchBySession(String sessionId) {
    return _client
        .from('orders')
        .stream(primaryKey: ['id'])
        .eq('session_id', sessionId)
        .order('created_at', ascending: false)
        .map((rows) => rows.map((r) => CustomerOrder.fromMap(r)).toList());
  }

  /// Live stream of every order ever placed under this email — across
  /// every restaurant/table/session. Used by a logged-in customer's
  /// "Riwayat Saya" screen, since login (not device-local storage) is
  /// what lets their history follow them anywhere.
  Stream<List<CustomerOrder>> watchByCustomerEmail(String email) {
    return _client
        .from('orders')
        .stream(primaryKey: ['id'])
        .eq('customer_label', email)
        .order('created_at', ascending: false)
        .map((rows) => rows.map((r) => CustomerOrder.fromMap(r)).toList());
  }
}
