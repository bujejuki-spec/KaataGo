import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../db/firestore_product_repository.dart';
import '../db/product_repository.dart';
import '../models/product.dart';

class ProductProvider extends ChangeNotifier {
  final _repo = ProductRepository();
  final _firestoreRepo = FirestoreProductRepository();
  final _uuid = const Uuid();

  /// Which restaurant this device's employee belongs to — set once by the
  /// POS screen from [AuthProvider.restoId] before any Firestore sync
  /// happens. Every product mirrored to/pulled from Firestore is scoped
  /// to this id so multiple restaurants sharing the app never see each
  /// other's catalogs.
  String? restoId;

  List<Product> _products = [];
  List<Product> get products => _products;

  Future<void> load() async {
    _products = await _repo.getAll();
    notifyListeners();
  }

  /// One-time (per app open) backfill: pushes every locally-known product
  /// to Firestore. Needed because products created before the customer
  /// self-order feature existed were never mirrored — without this the
  /// customer app's catalog stays empty even though the cashier has a
  /// full product list locally.
  Future<void> syncAllToFirestore() async {
    if (restoId == null) return;
    for (final product in _products) {
      _mirrorToFirestore(product);
    }
  }

  /// Best-effort mirror to Firestore so the customer app sees the same
  /// catalog. Never blocks or throws on the caller — if there's no
  /// internet right now, the local (source-of-truth-for-cashier) write
  /// already succeeded, and this sync is simply skipped.
  void _mirrorToFirestore(Product product) {
    if (restoId == null) return;
    _firestoreRepo.upsert(product, restoId!).catchError((_) {});
  }

  /// Pulls current stock numbers down from Firestore into the local
  /// database. Needed because customer self-orders decrement stock
  /// directly in Firestore — without this, the cashier's local copy would
  /// drift and keep showing stale (higher) stock for items customers
  /// already bought.
  Future<void> pullStockFromFirestore() async {
    if (restoId == null) return;
    try {
      final remoteProducts = await _firestoreRepo.getAllOnce(restoId!);
      final localIds = _products.map((p) => p.id).toSet();
      for (final remote in remoteProducts) {
        if (localIds.contains(remote.id)) {
          await _repo.setStock(remote.id, remote.stock);
        }
      }
      await load();
    } catch (_) {
      // Offline or Firestore unreachable — keep using local numbers.
    }
  }

  /// Pulls down any products that exist in Firestore but not yet in this
  /// device's local database — e.g. ones seeded directly via SQL/another
  /// device — so the cashier's product list picks them up automatically.
  Future<void> pullNewProductsFromFirestore() async {
    if (restoId == null) return;
    try {
      final remoteProducts = await _firestoreRepo.getAllOnce(restoId!);
      final localIds = _products.map((p) => p.id).toSet();
      for (final remote in remoteProducts) {
        if (!localIds.contains(remote.id)) {
          await _repo.insert(remote);
        }
      }
      await load();
    } catch (_) {
      // Offline or Firestore unreachable — nothing new to pull in.
    }
  }

  Future<void> addProduct({
    required String name,
    required String category,
    required int price,
    required int stock,
    String? description,
    String? photoBase64,
    List<String> levelGroups = const [],
    Map<String, Map<String, int>> levelPrices = const {},
  }) async {
    final product = Product(
      id: _uuid.v4(),
      name: name,
      category: category,
      price: price,
      stock: stock,
      description: description,
      photoBase64: photoBase64,
      levelGroups: levelGroups,
      levelPrices: levelPrices,
    );
    await _repo.insert(product);
    _mirrorToFirestore(product);
    await load();
  }

  Future<void> updateProduct(Product product) async {
    await _repo.update(product);
    _mirrorToFirestore(product);
    await load();
  }

  Future<void> deleteProduct(String id) async {
    await _repo.delete(id);
    _firestoreRepo.delete(id).catchError((_) {});
    await load();
  }
}
