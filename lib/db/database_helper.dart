import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

/// Handles all local (offline) SQLite storage.
/// This is the core of the "offline-first" design: every read/write in the
/// app goes through this local database first. A sync layer can be added
/// later to push/pull this data to a cloud backend without changing how
/// the rest of the app works.
class DatabaseHelper {
  DatabaseHelper._internal();
  static final DatabaseHelper instance = DatabaseHelper._internal();

  static Database? _db;

  Future<Database> get database async {
    if (_db != null) return _db!;
    _db = await _initDb();
    return _db!;
  }

  Future<Database> _initDb() async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, 'pos_app.db');

    return openDatabase(
      path,
      version: 11,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE products (
            id TEXT PRIMARY KEY,
            name TEXT NOT NULL,
            category TEXT NOT NULL,
            price INTEGER NOT NULL,
            stock INTEGER NOT NULL,
            description TEXT,
            photo_base64 TEXT,
            level_groups TEXT,
            level_prices TEXT,
            ppn_exempt INTEGER NOT NULL DEFAULT 0,
            service_exempt INTEGER NOT NULL DEFAULT 0,
            -- Katalog milik resto mana. Tanpa kolom ini, akun yang
            -- memegang dua cabang akan melihat produk keduanya bercampur
            -- di satu daftar — dan sinkronisasi akan mendorong produk
            -- cabang yang satu ke cabang yang lain.
            resto_id TEXT
          )
        ''');

        await db.execute('''
          CREATE TABLE transactions (
            id TEXT PRIMARY KEY,
            createdAt TEXT NOT NULL,
            paymentMethod TEXT NOT NULL,
            total INTEGER NOT NULL,
            orderType TEXT NOT NULL DEFAULT 'dine_in',
            customerName TEXT,
            cashierName TEXT,
            cashReceived INTEGER,
            baseAmount INTEGER,
            serviceAmount INTEGER,
            ppnAmount INTEGER
          )
        ''');

        await db.execute('''
          CREATE TABLE transaction_items (
            transactionId TEXT NOT NULL,
            productId TEXT NOT NULL,
            productName TEXT NOT NULL,
            price INTEGER NOT NULL,
            quantity INTEGER NOT NULL,
            notes TEXT,
            FOREIGN KEY (transactionId) REFERENCES transactions (id)
          )
        ''');

        await db.execute('''
          CREATE TABLE categories (
            id TEXT PRIMARY KEY,
            name TEXT NOT NULL,
            resto_id TEXT
          )
        ''');
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await db.execute('''
            CREATE TABLE IF NOT EXISTS categories (
              id TEXT PRIMARY KEY,
              name TEXT NOT NULL
            )
          ''');
        }
        if (oldVersion < 3) {
          await db.execute('ALTER TABLE products ADD COLUMN description TEXT');
          await db.execute('ALTER TABLE products ADD COLUMN photo_base64 TEXT');
        }
        if (oldVersion < 4) {
          await db.execute('ALTER TABLE products ADD COLUMN level_groups TEXT');
          await db.execute('ALTER TABLE transaction_items ADD COLUMN notes TEXT');
        }
        if (oldVersion < 5) {
          await db.execute('ALTER TABLE products ADD COLUMN level_prices TEXT');
        }
        if (oldVersion < 6) {
          await db.execute(
              "ALTER TABLE transactions ADD COLUMN orderType TEXT NOT NULL DEFAULT 'dine_in'");
        }
        if (oldVersion < 7) {
          await db.execute('ALTER TABLE transactions ADD COLUMN customerName TEXT');
        }
        if (oldVersion < 8) {
          await db.execute('ALTER TABLE transactions ADD COLUMN cashierName TEXT');
        }
        if (oldVersion < 9) {
          await db.execute('ALTER TABLE transactions ADD COLUMN cashReceived INTEGER');
        }
        if (oldVersion < 10) {
          await db.execute(
              'ALTER TABLE products ADD COLUMN ppn_exempt INTEGER NOT NULL DEFAULT 0');
          await db.execute(
              'ALTER TABLE products ADD COLUMN service_exempt INTEGER NOT NULL DEFAULT 0');
          await db.execute('ALTER TABLE transactions ADD COLUMN baseAmount INTEGER');
          await db.execute('ALTER TABLE transactions ADD COLUMN serviceAmount INTEGER');
          await db.execute('ALTER TABLE transactions ADD COLUMN ppnAmount INTEGER');
        }
        if (oldVersion < 11) {
          // Produk lama tidak tahu miliknya resto mana. Dibiarkan NULL
          // dan diperlakukan sebagai milik resto mana pun yang pertama
          // kali membukanya setelah pembaruan ini — satu-satunya
          // kemungkinan yang benar, karena sampai sekarang memang cuma
          // ada satu resto per perangkat.
          await db.execute('ALTER TABLE products ADD COLUMN resto_id TEXT');
          await db.execute('ALTER TABLE categories ADD COLUMN resto_id TEXT');
        }
      },
    );
  }
}
