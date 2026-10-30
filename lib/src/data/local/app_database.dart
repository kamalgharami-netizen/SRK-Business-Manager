import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Local-first database shared by the Windows and Android applications.
class AppDatabase {
  AppDatabase._();

  static final AppDatabase instance = AppDatabase._();
  static const int _databaseVersion = 1;
  Database? _database;

  Future<Database> get database async {
    if (_database != null) return _database!;

    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    }

    final documents = await getApplicationDocumentsDirectory();
    final databasePath = p.join(
      documents.path,
      'SRK Business Manager',
      'srk_business_manager.db',
    );

    _database = await openDatabase(
      databasePath,
      version: _databaseVersion,
      onConfigure: (db) async {
        await db.execute('PRAGMA foreign_keys = ON');
        await db.execute('PRAGMA journal_mode = WAL');
      },
      onCreate: _createSchema,
    );
    return _database!;
  }

  Future<void> _createSchema(Database db, int version) async {
    await db.execute('''
      CREATE TABLE parties (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        party_type TEXT NOT NULL CHECK (party_type IN ('customer','supplier','both')),
        phone TEXT,
        email TEXT,
        address TEXT,
        gstin TEXT,
        opening_balance REAL NOT NULL DEFAULT 0,
        balance_type TEXT NOT NULL DEFAULT 'receivable'
          CHECK (balance_type IN ('receivable','payable')),
        created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
        updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
      )
    ''');

    await db.execute('''
      CREATE TABLE products (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        sku TEXT,
        barcode TEXT,
        category TEXT,
        unit TEXT NOT NULL DEFAULT 'pcs',
        purchase_price REAL NOT NULL DEFAULT 0 CHECK (purchase_price >= 0),
        sale_price REAL NOT NULL DEFAULT 0 CHECK (sale_price >= 0),
        opening_stock REAL NOT NULL DEFAULT 0,
        current_stock REAL NOT NULL DEFAULT 0,
        low_stock_alert REAL NOT NULL DEFAULT 0,
        hsn_sac TEXT,
        gst_rate REAL NOT NULL DEFAULT 0,
        is_service INTEGER NOT NULL DEFAULT 0,
        created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
        updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
      )
    ''');

    await db.execute('''
      CREATE TABLE invoices (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        invoice_number TEXT NOT NULL UNIQUE,
        invoice_type TEXT NOT NULL DEFAULT 'sale'
          CHECK (invoice_type IN ('sale','estimate','purchase','sales_return','purchase_return')),
        party_id INTEGER,
        invoice_date TEXT NOT NULL,
        due_date TEXT,
        subtotal REAL NOT NULL DEFAULT 0,
        discount_total REAL NOT NULL DEFAULT 0,
        tax_total REAL NOT NULL DEFAULT 0,
        grand_total REAL NOT NULL DEFAULT 0,
        amount_paid REAL NOT NULL DEFAULT 0,
        status TEXT NOT NULL DEFAULT 'draft',
        notes TEXT,
        created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
        FOREIGN KEY (party_id) REFERENCES parties(id) ON DELETE SET NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE invoice_items (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        invoice_id INTEGER NOT NULL,
        product_id INTEGER,
        description TEXT NOT NULL,
        quantity REAL NOT NULL CHECK (quantity > 0),
        unit TEXT NOT NULL DEFAULT 'pcs',
        rate REAL NOT NULL CHECK (rate >= 0),
        discount REAL NOT NULL DEFAULT 0,
        gst_rate REAL NOT NULL DEFAULT 0,
        tax_amount REAL NOT NULL DEFAULT 0,
        line_total REAL NOT NULL,
        FOREIGN KEY (invoice_id) REFERENCES invoices(id) ON DELETE CASCADE,
        FOREIGN KEY (product_id) REFERENCES products(id) ON DELETE SET NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE payments (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        party_id INTEGER,
        invoice_id INTEGER,
        payment_type TEXT NOT NULL CHECK (payment_type IN ('receipt','payment')),
        payment_date TEXT NOT NULL,
        amount REAL NOT NULL CHECK (amount > 0),
        mode TEXT NOT NULL DEFAULT 'cash',
        reference TEXT,
        notes TEXT,
        created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
        FOREIGN KEY (party_id) REFERENCES parties(id) ON DELETE SET NULL,
        FOREIGN KEY (invoice_id) REFERENCES invoices(id) ON DELETE SET NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE expenses (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        expense_date TEXT NOT NULL,
        category TEXT NOT NULL,
        description TEXT NOT NULL,
        amount REAL NOT NULL CHECK (amount > 0),
        payment_mode TEXT NOT NULL DEFAULT 'cash',
        reference TEXT,
        created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
      )
    ''');

    await db.execute('''
      CREATE TABLE sync_queue (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        table_name TEXT NOT NULL,
        record_id TEXT NOT NULL,
        operation TEXT NOT NULL CHECK (operation IN ('insert','update','delete')),
        payload TEXT NOT NULL,
        created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
        retry_count INTEGER NOT NULL DEFAULT 0,
        last_error TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE app_settings (
        setting_key TEXT PRIMARY KEY,
        setting_value TEXT NOT NULL
      )
    ''');

    await db.execute('CREATE INDEX idx_parties_name ON parties(name)');
    await db.execute('CREATE INDEX idx_products_name ON products(name)');
    await db.execute('CREATE INDEX idx_products_barcode ON products(barcode)');
    await db.execute('CREATE INDEX idx_invoices_date ON invoices(invoice_date)');
    await db.execute('CREATE INDEX idx_invoices_party ON invoices(party_id)');
    await db.execute('CREATE INDEX idx_payments_date ON payments(payment_date)');
    await db.execute('CREATE INDEX idx_sync_queue_created ON sync_queue(created_at)');
  }

  Future<void> close() async {
    await _database?.close();
    _database = null;
  }
}
