import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Local-first database shared by the Windows and Android applications.
class AppDatabase {
  AppDatabase._();

  static final AppDatabase instance = AppDatabase._();
  static const int _databaseVersion = 16;
  String? _databasePath;
  String? _activeBusinessId;
  Database? _database;

  /// Opens a separate offline database for a selected business UUID.
  Future<void> openBusinessDatabase(String businessId) async {
    final id = businessId.trim().toLowerCase();
    final validUuid = RegExp(
      r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
    ).hasMatch(id);
    if (!validUuid) {
      throw const FormatException('Invalid business identifier.');
    }
    if (_activeBusinessId == id && _database != null) return;
    await close();
    _activeBusinessId = id;
    await database;
  }

  /// Reopens the original device-local database without deleting it.
  Future<void> useLocalDatabase() async {
    if (_activeBusinessId == null && _database != null) return;
    await close();
    _activeBusinessId = null;
    await database;
  }

  String? get activeBusinessId => _activeBusinessId;

  Future<Database> get database async {
    if (_database != null) return _database!;

    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    }

    final documents = await getApplicationDocumentsDirectory();
    final databasePath = _activeBusinessId == null
        ? p.join(
            documents.path,
            'SRK Business Manager',
            'srk_business_manager.db',
          )
        : p.join(
            documents.path,
            'SRK Business Manager',
            'Businesses',
            _activeBusinessId!,
            'srk_business_manager.db',
          );

    _databasePath = databasePath;
    await Directory(p.dirname(databasePath)).create(recursive: true);
    _database = await openDatabase(
      databasePath,
      version: _databaseVersion,
      onConfigure: (db) async {
        await db.execute('PRAGMA foreign_keys = ON');
        await db.execute('PRAGMA journal_mode = WAL');
      },
      onCreate: _createSchema,
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await db.execute('''CREATE TABLE staff_members (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            display_name TEXT NOT NULL,
            role TEXT NOT NULL DEFAULT 'staff',
            phone TEXT,
            is_active INTEGER NOT NULL DEFAULT 1,
            created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
          )''');
        }
        if (oldVersion < 3) {
          await db.execute('ALTER TABLE invoices ADD COLUMN parent_invoice_id INTEGER');
          await db.execute('''CREATE TABLE stock_movements (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            product_id INTEGER NOT NULL,
            movement_type TEXT NOT NULL CHECK (movement_type IN ('purchase_return','sales_return','adjustment')),
            quantity_change REAL NOT NULL,
            reference TEXT,
            notes TEXT,
            created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
            FOREIGN KEY (product_id) REFERENCES products(id) ON DELETE RESTRICT
          )''');
          await db.execute('CREATE INDEX idx_stock_movements_product ON stock_movements(product_id)');
          await db.execute('CREATE INDEX idx_invoices_parent ON invoices(parent_invoice_id)');
        }
        if (oldVersion < 4) {
          await db.execute('ALTER TABLE invoice_items ADD COLUMN hsn_sac TEXT');
        }
        if (oldVersion < 6) {
          await db.execute('ALTER TABLE parties ADD COLUMN state TEXT');
        }
        if (oldVersion < 5) {
          await db.execute('ALTER TABLE invoices ADD COLUMN place_of_supply TEXT');
          await db.execute("ALTER TABLE invoices ADD COLUMN tax_type TEXT NOT NULL DEFAULT 'unclassified'");
          await db.execute('ALTER TABLE invoices ADD COLUMN cgst_total REAL NOT NULL DEFAULT 0');
          await db.execute('ALTER TABLE invoices ADD COLUMN sgst_total REAL NOT NULL DEFAULT 0');
          await db.execute('ALTER TABLE invoices ADD COLUMN igst_total REAL NOT NULL DEFAULT 0');
          await db.execute('ALTER TABLE invoice_items ADD COLUMN cgst_amount REAL NOT NULL DEFAULT 0');
          await db.execute('ALTER TABLE invoice_items ADD COLUMN sgst_amount REAL NOT NULL DEFAULT 0');
          await db.execute('ALTER TABLE invoice_items ADD COLUMN igst_amount REAL NOT NULL DEFAULT 0');
        }
        if (oldVersion < 7) {
          await _createAccountingSchema(db);
          await _seedDefaultAccounts(db);
        }
        if (oldVersion < 8) {
          await _seedDefaultAccounts(db);
        }
        if (oldVersion < 9) {
          await db.execute('ALTER TABLE invoice_items ADD COLUMN cost_of_goods_sold REAL NOT NULL DEFAULT 0');
          await _createInventoryCostSchema(db);
          await _seedLegacyInventoryCostLayers(db);
        }
        if (oldVersion < 10) {
          await db.execute('ALTER TABLE invoice_items ADD COLUMN original_invoice_item_id INTEGER');
          await db.execute('CREATE INDEX idx_invoice_items_original ON invoice_items(original_invoice_item_id)');
        }
        if (oldVersion < 12) {
          await db.execute('ALTER TABLE inventory_cost_layers ADD COLUMN source_item_id INTEGER');
        }
        if (oldVersion < 13) {
          await db.execute('ALTER TABLE parties ADD COLUMN sync_id TEXT');
          await db.execute('ALTER TABLE products ADD COLUMN sync_id TEXT');
          await _backfillSyncIds(db, 'parties');
          await _backfillSyncIds(db, 'products');
          await db.execute('CREATE UNIQUE INDEX idx_parties_sync_id ON parties(sync_id)');
          await db.execute('CREATE UNIQUE INDEX idx_products_sync_id ON products(sync_id)');
        }
        if (oldVersion < 14) {
          await db.execute('ALTER TABLE expenses ADD COLUMN sync_id TEXT');
          await _backfillSyncIds(db, 'expenses');
          await db.execute('CREATE UNIQUE INDEX idx_expenses_sync_id ON expenses(sync_id)');
        }
        if (oldVersion < 15) {
          await db.execute('''CREATE TABLE IF NOT EXISTS sync_metadata (
            entity_type TEXT NOT NULL,
            record_id TEXT NOT NULL,
            remote_updated_at TEXT NOT NULL,
            PRIMARY KEY (entity_type, record_id)
          )''');
        }
        if (oldVersion < 16) {
          await db.execute('ALTER TABLE invoices ADD COLUMN sync_id TEXT');
          await db.execute('ALTER TABLE invoice_items ADD COLUMN sync_id TEXT');
          await _backfillSyncIds(db, 'invoices');
          await _backfillSyncIds(db, 'invoice_items');
          await db.execute('CREATE UNIQUE INDEX idx_invoices_sync_id ON invoices(sync_id)');
          await db.execute('CREATE UNIQUE INDEX idx_invoice_items_sync_id ON invoice_items(sync_id)');
        }
        if (oldVersion < 11) {
          await db.execute('ALTER TABLE stock_movements RENAME TO stock_movements_old');
          await db.execute("""
            CREATE TABLE stock_movements (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              product_id INTEGER NOT NULL,
              movement_type TEXT NOT NULL CHECK (
                movement_type IN ('purchase_return','sales_return','adjustment')
              ),
              quantity_change REAL NOT NULL,
              reference TEXT,
              notes TEXT,
              created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
              FOREIGN KEY (product_id) REFERENCES products(id) ON DELETE RESTRICT
            )
          """);
          await db.execute("""
            INSERT INTO stock_movements
              (id, product_id, movement_type, quantity_change, reference, notes, created_at)
            SELECT id, product_id, movement_type, quantity_change, reference, notes, created_at
            FROM stock_movements_old
          """);
          await db.execute('DROP TABLE stock_movements_old');
          await db.execute('CREATE INDEX idx_stock_movements_product ON stock_movements(product_id)');
        }
      },
    );
    try {
      await _ensureDatabaseScope(_database!);
    } catch (_) {
      await _database?.close();
      _database = null;
      _databasePath = null;
      rethrow;
    }
    return _database!;
  }

  Future<void> _ensureDatabaseScope(Database db) async {
    final expectedScope = _activeBusinessId ?? 'local';
    final rows = await db.query(
      'app_settings',
      columns: ['setting_value'],
      where: 'setting_key = ?',
      whereArgs: ['database_scope'],
      limit: 1,
    );
    if (rows.isEmpty) {
      await db.insert('app_settings', {
        'setting_key': 'database_scope',
        'setting_value': expectedScope,
      });
      return;
    }
    if (rows.first['setting_value'] != expectedScope) {
      throw StateError(
        'This database belongs to a different business. It was not opened.',
      );
    }
  }

  String createSyncId() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    final hex = bytes.map((value) => value.toRadixString(16).padLeft(2, '0')).join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
  }

  Future<void> _backfillSyncIds(DatabaseExecutor db, String tableName) async {
    if (tableName != 'parties' && tableName != 'products' && tableName != 'expenses' &&
        tableName != 'invoices' && tableName != 'invoice_items') {
      throw ArgumentError.value(tableName, 'tableName');
    }
    final rows = await db.query(
      tableName,
      columns: ['id'],
      where: 'sync_id IS NULL',
    );
    for (final row in rows) {
      await db.update(
        tableName,
        {'sync_id': createSyncId()},
        where: 'id = ?',
        whereArgs: [row['id']],
      );
    }
  }

  Future<void> _createSchema(Database db, int version) async {
    await db.execute('''
      CREATE TABLE parties (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        sync_id TEXT UNIQUE,
        name TEXT NOT NULL,
        party_type TEXT NOT NULL CHECK (party_type IN ('customer','supplier','both')),
        phone TEXT,
        email TEXT,
        address TEXT,
        gstin TEXT,
        state TEXT,
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
        sync_id TEXT UNIQUE,
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
        sync_id TEXT UNIQUE,
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
        parent_invoice_id INTEGER,
        place_of_supply TEXT,
        tax_type TEXT NOT NULL DEFAULT 'unclassified',
        cgst_total REAL NOT NULL DEFAULT 0,
        sgst_total REAL NOT NULL DEFAULT 0,
        igst_total REAL NOT NULL DEFAULT 0,
        created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
        FOREIGN KEY (party_id) REFERENCES parties(id) ON DELETE SET NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE invoice_items (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        sync_id TEXT UNIQUE,
        invoice_id INTEGER NOT NULL,
        product_id INTEGER,
        description TEXT NOT NULL,
        quantity REAL NOT NULL CHECK (quantity > 0),
        unit TEXT NOT NULL DEFAULT 'pcs',
        rate REAL NOT NULL CHECK (rate >= 0),
        discount REAL NOT NULL DEFAULT 0,
        gst_rate REAL NOT NULL DEFAULT 0,
        tax_amount REAL NOT NULL DEFAULT 0,
        hsn_sac TEXT,
        cgst_amount REAL NOT NULL DEFAULT 0,
        sgst_amount REAL NOT NULL DEFAULT 0,
        igst_amount REAL NOT NULL DEFAULT 0,
        line_total REAL NOT NULL,
        cost_of_goods_sold REAL NOT NULL DEFAULT 0,
        original_invoice_item_id INTEGER,
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
        sync_id TEXT UNIQUE,
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
      CREATE TABLE sync_metadata (
        entity_type TEXT NOT NULL,
        record_id TEXT NOT NULL,
        remote_updated_at TEXT NOT NULL,
        PRIMARY KEY (entity_type, record_id)
      )
    ''');

    await db.execute('''
      CREATE TABLE app_settings (
        setting_key TEXT PRIMARY KEY,
        setting_value TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE staff_members (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        display_name TEXT NOT NULL,
        role TEXT NOT NULL DEFAULT 'staff',
        phone TEXT,
        is_active INTEGER NOT NULL DEFAULT 1,
        created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
      )
    ''');

    await db.execute('CREATE INDEX idx_parties_name ON parties(name)');
    await db.execute('CREATE INDEX idx_products_name ON products(name)');
    await db.execute('CREATE INDEX idx_products_barcode ON products(barcode)');
    await db.execute('CREATE INDEX idx_invoices_date ON invoices(invoice_date)');
    await db.execute('CREATE INDEX idx_invoices_party ON invoices(party_id)');
    await db.execute('CREATE INDEX idx_payments_date ON payments(payment_date)');
    await db.execute('CREATE INDEX idx_expenses_sync_id ON expenses(sync_id)');
    await db.execute('CREATE INDEX idx_sync_queue_created ON sync_queue(created_at)');
    await db.execute('CREATE INDEX idx_invoices_parent ON invoices(parent_invoice_id)');
    await db.execute('''CREATE TABLE stock_movements (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      product_id INTEGER NOT NULL,
      movement_type TEXT NOT NULL CHECK (movement_type IN ('purchase_return','adjustment')),
      quantity_change REAL NOT NULL,
      reference TEXT,
      notes TEXT,
      created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
      FOREIGN KEY (product_id) REFERENCES products(id) ON DELETE RESTRICT
    )''');
    await db.execute('CREATE INDEX idx_stock_movements_product ON stock_movements(product_id)');
    await _createAccountingSchema(db);
    await _seedDefaultAccounts(db);
    await _createInventoryCostSchema(db);
  }

  Future<void> _createAccountingSchema(Database db) async {
    await db.execute('''
      CREATE TABLE accounts (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        account_code TEXT NOT NULL UNIQUE,
        account_name TEXT NOT NULL,
        account_type TEXT NOT NULL CHECK (
          account_type IN ('asset','liability','equity','income','expense')
        ),
        normal_balance TEXT NOT NULL CHECK (normal_balance IN ('debit','credit')),
        is_system INTEGER NOT NULL DEFAULT 1,
        is_active INTEGER NOT NULL DEFAULT 1,
        created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
      )
    ''');
    await db.execute('''
      CREATE TABLE journal_entries (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        entry_number TEXT NOT NULL UNIQUE,
        entry_date TEXT NOT NULL,
        source_type TEXT NOT NULL,
        source_id INTEGER,
        memo TEXT,
        status TEXT NOT NULL DEFAULT 'draft'
          CHECK (status IN ('draft','posted','void')),
        created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
        UNIQUE(source_type, source_id)
      )
    ''');
    await db.execute('''
      CREATE TABLE journal_lines (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        journal_entry_id INTEGER NOT NULL,
        account_id INTEGER NOT NULL,
        description TEXT,
        debit REAL NOT NULL DEFAULT 0 CHECK (debit >= 0),
        credit REAL NOT NULL DEFAULT 0 CHECK (credit >= 0),
        FOREIGN KEY (journal_entry_id) REFERENCES journal_entries(id) ON DELETE CASCADE,
        FOREIGN KEY (account_id) REFERENCES accounts(id) ON DELETE RESTRICT,
        CHECK (
          (debit > 0 AND credit = 0) OR
          (credit > 0 AND debit = 0)
        )
      )
    ''');
    await db.execute(
      'CREATE INDEX idx_journal_entries_date ON journal_entries(entry_date)',
    );
    await db.execute(
      'CREATE INDEX idx_journal_entries_source ON journal_entries(source_type, source_id)',
    );
    await db.execute(
      'CREATE INDEX idx_journal_lines_account ON journal_lines(account_id)',
    );
    await db.execute(
      'CREATE INDEX idx_journal_lines_entry ON journal_lines(journal_entry_id)',
    );
  }

  Future<void> _createInventoryCostSchema(DatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE inventory_cost_layers (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        product_id INTEGER NOT NULL,
        source_type TEXT NOT NULL,
        source_id INTEGER,
        source_item_id INTEGER,
        received_at TEXT NOT NULL,
        quantity_received REAL NOT NULL CHECK (quantity_received > 0),
        quantity_remaining REAL NOT NULL CHECK (quantity_remaining >= 0),
        unit_cost REAL NOT NULL CHECK (unit_cost >= 0),
        is_estimated INTEGER NOT NULL DEFAULT 0,
        created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
        FOREIGN KEY (product_id) REFERENCES products(id) ON DELETE RESTRICT
      )
    ''');
    await db.execute('''
      CREATE TABLE invoice_item_costs (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        invoice_item_id INTEGER NOT NULL,
        layer_id INTEGER NOT NULL,
        quantity REAL NOT NULL CHECK (quantity > 0),
        unit_cost REAL NOT NULL CHECK (unit_cost >= 0),
        total_cost REAL NOT NULL CHECK (total_cost >= 0),
        is_estimated INTEGER NOT NULL DEFAULT 0,
        FOREIGN KEY (invoice_item_id) REFERENCES invoice_items(id) ON DELETE CASCADE,
        FOREIGN KEY (layer_id) REFERENCES inventory_cost_layers(id) ON DELETE RESTRICT
      )
    ''');
    await db.execute('CREATE INDEX idx_inventory_layers_fifo ON inventory_cost_layers(product_id, received_at, id)');
    await db.execute('CREATE INDEX idx_invoice_item_costs_item ON invoice_item_costs(invoice_item_id)');
  }

  Future<void> _seedLegacyInventoryCostLayers(DatabaseExecutor db) async {
    final rows = await db.rawQuery('''
      SELECT id, current_stock, purchase_price
      FROM products
      WHERE (is_service = 0 OR is_service IS NULL) AND current_stock > 0
    ''');
    for (final row in rows) {
      final quantity = (row['current_stock'] as num).toDouble();
      final unitCost = (row['purchase_price'] as num).toDouble();
      if (quantity <= 0) continue;
      await db.insert('inventory_cost_layers', {
        'product_id': row['id'],
        'source_type': 'migration_estimate',
        'received_at': DateTime.now().toIso8601String(),
        'quantity_received': quantity,
        'quantity_remaining': quantity,
        'unit_cost': unitCost,
        'is_estimated': 1,
      });
    }
  }

  Future<void> _seedDefaultAccounts(Database db) async {
    const accounts = <Map<String, Object>>[
      {'account_code': '1000', 'account_name': 'Cash in Hand', 'account_type': 'asset', 'normal_balance': 'debit'},
      {'account_code': '1010', 'account_name': 'Bank Accounts', 'account_type': 'asset', 'normal_balance': 'debit'},
      {'account_code': '1100', 'account_name': 'Accounts Receivable', 'account_type': 'asset', 'normal_balance': 'debit'},
      {'account_code': '1200', 'account_name': 'Inventory', 'account_type': 'asset', 'normal_balance': 'debit'},
      {'account_code': '1300', 'account_name': 'Input GST', 'account_type': 'asset', 'normal_balance': 'debit'},
      {'account_code': '2000', 'account_name': 'Accounts Payable', 'account_type': 'liability', 'normal_balance': 'credit'},
      {'account_code': '2100', 'account_name': 'Output GST', 'account_type': 'liability', 'normal_balance': 'credit'},
      {'account_code': '3000', 'account_name': 'Owner Capital', 'account_type': 'equity', 'normal_balance': 'credit'},
      {'account_code': '3100', 'account_name': 'Retained Earnings', 'account_type': 'equity', 'normal_balance': 'credit'},
      {'account_code': '3200', 'account_name': 'Opening Balance Equity', 'account_type': 'equity', 'normal_balance': 'credit'},
      {'account_code': '4000', 'account_name': 'Sales Revenue', 'account_type': 'income', 'normal_balance': 'credit'},
      {'account_code': '4100', 'account_name': 'Other Income', 'account_type': 'income', 'normal_balance': 'credit'},
      {'account_code': '5000', 'account_name': 'Cost of Goods Sold', 'account_type': 'expense', 'normal_balance': 'debit'},
      {'account_code': '5100', 'account_name': 'Purchase Expense', 'account_type': 'expense', 'normal_balance': 'debit'},
      {'account_code': '5200', 'account_name': 'Operating Expenses', 'account_type': 'expense', 'normal_balance': 'debit'},
      {'account_code': '5300', 'account_name': 'Bank Charges', 'account_type': 'expense', 'normal_balance': 'debit'},
      {'account_code': '5400', 'account_name': 'Depreciation Expense', 'account_type': 'expense', 'normal_balance': 'debit'},
    ];
    for (final account in accounts) {
      await db.insert(
        'accounts',
        account,
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
    }
  }

  /// Adds a local change to the durable queue for later cloud delivery.
  Future<int> enqueueSyncOperation({
    required String tableName,
    required String recordId,
    required String operation,
    required Map<String, dynamic> payload,
    DatabaseExecutor? executor,
  }) async {
    const allowedOperations = {'insert', 'update', 'delete'};
    if (!allowedOperations.contains(operation)) {
      throw ArgumentError.value(operation, 'operation', 'Unsupported sync operation');
    }
    if (tableName.trim().isEmpty || recordId.trim().isEmpty) {
      throw ArgumentError('Table name and record ID are required.');
    }
    final db = executor ?? await database;
    return db.insert('sync_queue', {
      'table_name': tableName.trim(),
      'record_id': recordId.trim(),
      'operation': operation,
      'payload': jsonEncode(payload),
    });
  }

  /// Reads queued operations in creation order without removing them.
  Future<List<Map<String, dynamic>>> getPendingSyncOperations({
    int limit = 100,
  }) async {
    if (limit < 1 || limit > 1000) {
      throw RangeError.range(limit, 1, 1000, 'limit');
    }
    final db = await database;
    final rows = await db.query(
      'sync_queue',
      orderBy: 'id ASC',
      limit: limit,
    );
    return rows.map((row) {
      final item = Map<String, dynamic>.from(row);
      item['payload'] = Map<String, dynamic>.from(
        jsonDecode(item['payload'] as String) as Map,
      );
      return item;
    }).toList(growable: false);
  }

  /// Removes an operation only after the remote service confirms success.
  Future<int> markSyncOperationCompleted(int id) async {
    final db = await database;
    return db.delete('sync_queue', where: 'id = ?', whereArgs: [id]);
  }

  /// Keeps failed work queued and records its retry information.
  Future<int> markSyncOperationFailed(int id, Object error) async {
    final db = await database;
    final message = error.toString();
    return db.rawUpdate(
      'UPDATE sync_queue SET retry_count = retry_count + 1, last_error = ? WHERE id = ?',
      [message.length > 1000 ? message.substring(0, 1000) : message, id],
    );
  }

  /// Returns the last cloud revision observed for a local record.
  Future<String?> getSyncRevision({
    required String entityType,
    required String recordId,
  }) async {
    final db = await database;
    final rows = await db.query(
      'sync_metadata',
      columns: ['remote_updated_at'],
      where: 'entity_type = ? AND record_id = ?',
      whereArgs: [entityType, recordId],
      limit: 1,
    );
    return rows.isEmpty ? null : rows.first['remote_updated_at'] as String?;
  }

  /// Stores the server revision only after a confirmed upload or pull.
  Future<void> saveSyncRevision({
    required String entityType,
    required String recordId,
    required String remoteUpdatedAt,
  }) async {
    final db = await database;
    await db.insert(
      'sync_metadata',
      {
        'entity_type': entityType,
        'record_id': recordId,
        'remote_updated_at': remoteUpdatedAt,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<String?> getSyncRevision({required String entityType, required String recordId}) async {
    final db = await database;
    final rows = await db.query('sync_metadata', columns: ['remote_updated_at'], where: 'entity_type = ? AND record_id = ?', whereArgs: [entityType, recordId], limit: 1);
    return rows.isEmpty ? null : rows.first['remote_updated_at'] as String?;
  }

  Future<void> saveSyncRevision({required String entityType, required String recordId, required String remoteUpdatedAt}) async {
    final db = await database;
    await db.insert('sync_metadata', {'entity_type': entityType, 'record_id': recordId, 'remote_updated_at': remoteUpdatedAt}, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<int> getPendingSyncCount() async {
    final db = await database;
    final result = await db.rawQuery(
      'SELECT COUNT(*) AS total FROM sync_queue',
    );
    return int.tryParse('${result.first['total']}') ?? 0;
  }

  Future<bool> hasPendingSyncOperation({
    required String tableName,
    required String recordId,
  }) async {
    final db = await database;
    final rows = await db.query(
      'sync_queue',
      columns: ['id'],
      where: 'table_name = ? AND record_id = ?',
      whereArgs: [tableName, recordId],
      limit: 1,
    );
    return rows.isNotEmpty;
  }

  /// Applies a cloud record to the active business database.
  /// Only the first sync-enabled entities are accepted.
  Future<void> applyRemoteSyncRecord({
    required String tableName,
    required String recordId,
    required Map<String, dynamic> payload,
    required bool isDeleted,
  }) async {
    if (tableName != 'parties' && tableName != 'products' &&
        tableName != 'expenses' && tableName != 'invoices') {
      throw ArgumentError.value(tableName, 'tableName');
    }
    final db = await database;
    await db.transaction((txn) async {
      if (isDeleted) {
        await txn.delete(tableName, where: 'sync_id = ?', whereArgs: [recordId]);
        return;
      }

      if (tableName == 'invoices') {
        final partySyncId = payload['party_sync_id'] as String?;
        int? localPartyId;
        if (partySyncId != null && partySyncId.isNotEmpty) {
          final partyRows = await txn.query(
            'parties',
            columns: ['id'],
            where: 'sync_id = ?',
            whereArgs: [partySyncId],
            limit: 1,
          );
          if (partyRows.isEmpty) {
            throw StateError('Invoice customer is not available on this device yet.');
          }
          localPartyId = partyRows.first['id'] as int;
        }

        final values = Map<String, dynamic>.from(payload)
          ..remove('id')
          ..remove('party_sync_id')
          ..remove('items')
          ..['party_id'] = localPartyId
          ..['sync_id'] = recordId;
        final existing = await txn.query(
          'invoices',
          columns: ['id'],
          where: 'sync_id = ?',
          whereArgs: [recordId],
          limit: 1,
        );
        int localInvoiceId;
        if (existing.isEmpty) {
          localInvoiceId = await txn.insert('invoices', values);
        } else {
          localInvoiceId = existing.first['id'] as int;
          await txn.update('invoices', values, where: 'id = ?', whereArgs: [localInvoiceId]);
          await txn.delete('invoice_items', where: 'invoice_id = ?', whereArgs: [localInvoiceId]);
        }

        final rawItems = payload['items'];
        if (rawItems is! List) {
          throw const FormatException('Invoice items are missing from the cloud record.');
        }
        for (final rawItem in rawItems) {
          final item = Map<String, dynamic>.from(rawItem as Map);
          final productSyncId = item.remove('product_sync_id') as String?;
          item.remove('id');
          item.remove('invoice_id');
          int? localProductId;
          if (productSyncId != null && productSyncId.isNotEmpty) {
            final productRows = await txn.query(
              'products',
              columns: ['id'],
              where: 'sync_id = ?',
              whereArgs: [productSyncId],
              limit: 1,
            );
            if (productRows.isEmpty) {
              throw StateError('An invoice product is not available on this device yet.');
            }
            localProductId = productRows.first['id'] as int;
          }
          item['product_id'] = localProductId;
          item['invoice_id'] = localInvoiceId;
          await txn.insert('invoice_items', item);
        }
        return;
      }

      final values = Map<String, dynamic>.from(payload)
        ..remove('id')
        ..['sync_id'] = recordId;
      final existing = await txn.query(
        tableName,
        columns: ['id'],
        where: 'sync_id = ?',
        whereArgs: [recordId],
        limit: 1,
      );
      if (existing.isEmpty) {
        await txn.insert(tableName, values);
      } else {
        await txn.update(tableName, values, where: 'sync_id = ?', whereArgs: [recordId]);
      }
    });
  }

  Future<String> createBackup() async {
    final db = await database;
    await db.rawQuery('PRAGMA wal_checkpoint(FULL)');
    final sourcePath = _databasePath;
    if (sourcePath == null) throw StateError('Database path is unavailable');
    final source = File(sourcePath);
    if (!await source.exists()) throw StateError('Database file does not exist');
    final documents = await getApplicationDocumentsDirectory();
    final backupDir = Directory(
      p.join(
        documents.path,
        'SRK Business Manager',
        'Backups',
        _activeBusinessId ?? 'local',
      ),
    );
    await backupDir.create(recursive: true);
    final stamp = DateTime.now().toIso8601String().replaceAll(':', '-').replaceAll('.', '-');
    final target = File(p.join(backupDir.path, 'srk-backup-$stamp.db'));
    await source.copy(target.path);
    return target.path;
  }

  /// Restores a verified SQLite backup while preserving the current database.
  /// A safety copy is created before replacing the active database.
  Future<String> restoreBackup(String backupPath) async {
    await database; // Initialise the platform-specific database factory.
    final source = File(backupPath);
    if (!await source.exists()) {
      throw StateError('Selected backup file does not exist');
    }

    final activePath = _databasePath;
    if (activePath == null) {
      throw StateError('Active database path is unavailable');
    }
    if (p.equals(p.normalize(p.absolute(backupPath)),
        p.normalize(p.absolute(activePath)))) {
      throw StateError('The selected file is already the active database');
    }

    final handle = await source.open();
    try {
      final header = await handle.read(16);
      const sqliteHeader = <int>[
        83, 81, 76, 105, 116, 101, 32, 102, 111, 114, 109, 97, 116, 32, 51, 0
      ];
      if (header.length != sqliteHeader.length) {
        throw const FormatException('This is not a valid SQLite backup');
      }
      for (var i = 0; i < sqliteHeader.length; i++) {
        if (header[i] != sqliteHeader[i]) {
          throw const FormatException('This is not a valid SQLite backup');
        }
      }
    } finally {
      await handle.close();
    }

    final validationDb = await databaseFactory.openDatabase(
      source.path,
      options: OpenDatabaseOptions(readOnly: true),
    );
    try {
      final integrity = await validationDb.rawQuery('PRAGMA integrity_check');
      if (integrity.isEmpty || integrity.first.values.first != 'ok') {
        throw const FormatException('Backup database failed its integrity check');
      }
      final tables = await validationDb.rawQuery(
        "SELECT name FROM sqlite_master WHERE type = 'table'",
      );
      final names = tables.map((row) => row['name']).whereType<String>().toSet();
      const requiredTables = {
        'parties', 'products', 'invoices', 'invoice_items',
        'payments', 'expenses', 'app_settings'
      };
      if (!names.containsAll(requiredTables)) {
        throw const FormatException('Backup is missing required application tables');
      }
      final scopeRows = await validationDb.query(
        'app_settings',
        columns: ['setting_value'],
        where: 'setting_key = ?',
        whereArgs: ['database_scope'],
        limit: 1,
      );
      final backupScope = scopeRows.isEmpty
          ? null
          : scopeRows.first['setting_value'] as String?;
      final expectedScope = _activeBusinessId ?? 'local';
      if (backupScope != expectedScope &&
          !(backupScope == null && expectedScope == 'local')) {
        throw const FormatException(
          'Backup belongs to a different business or has no verified business identity.',
        );
      }
    } finally {
      await validationDb.close();
    }

    final documents = await getApplicationDocumentsDirectory();
    final safetyDir = Directory(
      p.join(
        documents.path,
        'SRK Business Manager',
        'Backups',
        _activeBusinessId ?? 'local',
      ),
    );
    await safetyDir.create(recursive: true);
    final stamp = DateTime.now().toIso8601String()
        .replaceAll(':', '-').replaceAll('.', '-');
    final safetyCopy = File(p.join(safetyDir.path, 'before-restore-$stamp.db'));

    await _database!.rawQuery('PRAGMA wal_checkpoint(FULL)');
    await File(activePath).copy(safetyCopy.path);
    await close();

    final walFile = File('$activePath-wal');
    final shmFile = File('$activePath-shm');
    if (await walFile.exists()) await walFile.delete();
    if (await shmFile.exists()) await shmFile.delete();

    try {
      await source.copy(activePath);
      await database; // Reopen and apply any required schema migration.
      return safetyCopy.path;
    } catch (_) {
      await close();
      await safetyCopy.copy(activePath);
      await database;
      rethrow;
    }
  }

  Future<void> close() async {
    await _database?.close();
    _database = null;
  }
}
