import '../models/category.dart';
import 'database_helper.dart';

/// Local (offline-first) storage for product categories — same pattern
/// as ProductRepository. Categories are managed once (Kelola Produk >
/// Kategori tab) and picked from a dropdown when adding/editing a
/// product, instead of being free-typed each time.
class CategoryRepository {
  final _dbHelper = DatabaseHelper.instance;

  Future<List<ProductCategory>> getAll() async {
    final db = await _dbHelper.database;
    final maps = await db.query('categories', orderBy: 'name ASC');
    return maps.map((m) => ProductCategory.fromMap(m)).toList();
  }

  Future<void> insert(ProductCategory category) async {
    final db = await _dbHelper.database;
    await db.insert('categories', category.toMap());
  }

  Future<void> delete(String id) async {
    final db = await _dbHelper.database;
    await db.delete('categories', where: 'id = ?', whereArgs: [id]);
  }
}
