import '../models/product.dart';
import 'database_helper.dart';

class ProductRepository {
  final _dbHelper = DatabaseHelper.instance;

  Future<List<Product>> getAll() async {
    final db = await _dbHelper.database;
    final maps = await db.query('products', orderBy: 'name ASC');
    return maps.map((m) => Product.fromMap(m)).toList();
  }

  Future<void> insert(Product product) async {
    final db = await _dbHelper.database;
    await db.insert('products', product.toMap());
  }

  Future<void> update(Product product) async {
    final db = await _dbHelper.database;
    await db.update(
      'products',
      product.toMap(),
      where: 'id = ?',
      whereArgs: [product.id],
    );
  }

  Future<void> delete(String id) async {
    final db = await _dbHelper.database;
    await db.delete('products', where: 'id = ?', whereArgs: [id]);
  }

  Future<void> adjustStock(String id, int delta) async {
    final db = await _dbHelper.database;
    await db.rawUpdate(
      'UPDATE products SET stock = stock + ? WHERE id = ?',
      [delta, id],
    );
  }

  Future<void> setStock(String id, int stock) async {
    final db = await _dbHelper.database;
    await db.update('products', {'stock': stock},
        where: 'id = ?', whereArgs: [id]);
  }
}
