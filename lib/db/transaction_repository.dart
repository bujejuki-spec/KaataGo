import '../models/transaction.dart';
import 'database_helper.dart';

class TransactionRepository {
  final _dbHelper = DatabaseHelper.instance;

  Future<void> insert(PosTransaction tx) async {
    final db = await _dbHelper.database;
    await db.transaction((txn) async {
      await txn.insert('transactions', tx.toMap());
      for (final item in tx.items) {
        await txn.insert('transaction_items', item.toMap(tx.id));
      }
    });
  }

  Future<List<PosTransaction>> getAll() async {
    final db = await _dbHelper.database;
    final txMaps = await db.query('transactions', orderBy: 'createdAt DESC');

    final result = <PosTransaction>[];
    for (final txMap in txMaps) {
      final itemMaps = await db.query(
        'transaction_items',
        where: 'transactionId = ?',
        whereArgs: [txMap['id']],
      );
      final items = itemMaps.map((m) => TransactionItem.fromMap(m)).toList();
      result.add(PosTransaction.fromMap(txMap, items));
    }
    return result;
  }

  /// Total sales for a given day (used by the daily report screen).
  Future<int> getTotalForDate(DateTime date) async {
    final db = await _dbHelper.database;
    final start = DateTime(date.year, date.month, date.day);
    final end = start.add(const Duration(days: 1));

    final result = await db.rawQuery(
      'SELECT SUM(total) as sum FROM transactions WHERE createdAt >= ? AND createdAt < ?',
      [start.toIso8601String(), end.toIso8601String()],
    );
    return (result.first['sum'] as int?) ?? 0;
  }
}
