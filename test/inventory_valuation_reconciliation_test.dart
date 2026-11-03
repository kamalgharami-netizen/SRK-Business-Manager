import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:srk_business_manager/src/data/local/inventory_valuation_reconciliation.dart';

Future<Database> _openDb() async {
  sqfliteFfiInit();
  final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
  await db.execute('CREATE TABLE products (id INTEGER PRIMARY KEY, current_stock REAL NOT NULL, is_service INTEGER)');
  await db.execute('''CREATE TABLE inventory_cost_layers (
    id INTEGER PRIMARY KEY, product_id INTEGER NOT NULL, source_type TEXT,
    quantity_remaining REAL NOT NULL, unit_cost REAL NOT NULL,
    is_estimated INTEGER NOT NULL DEFAULT 0
  )''');
  await db.execute('CREATE TABLE accounts (id INTEGER PRIMARY KEY, account_code TEXT NOT NULL)');
  await db.execute('''CREATE TABLE journal_entries (
    id INTEGER PRIMARY KEY, status TEXT NOT NULL
  )''');
  await db.execute('''CREATE TABLE journal_lines (
    id INTEGER PRIMARY KEY, journal_entry_id INTEGER NOT NULL,
    account_id INTEGER NOT NULL, debit REAL NOT NULL, credit REAL NOT NULL
  )''');
  return db;
}

void main() {
  group('Inventory valuation reconciliation', () {
    test('matches FIFO layers with posted Inventory control balance', () async {
      final db = await _openDb();
      addTearDown(db.close);
      await db.insert('products', {'id': 1, 'current_stock': 5, 'is_service': 0});
      await db.insert('inventory_cost_layers', {
        'product_id': 1, 'quantity_remaining': 5, 'unit_cost': 20, 'is_estimated': 0,
      });
      await db.insert('accounts', {'id': 1, 'account_code': '1200'});
      await db.insert('journal_entries', {'id': 1, 'status': 'posted'});
      await db.insert('journal_lines', {
        'journal_entry_id': 1, 'account_id': 1, 'debit': 100, 'credit': 0,
      });

      final result = await InventoryValuationReconciliation.load(db);
      expect(result['fifo_value'], 100);
      expect(result['control_account_balance'], 100);
      expect(result['difference'], 0);
      expect(result['is_reconciled'], isTrue);
    });

    test('flags quantity mismatch, estimated stock and valuation difference', () async {
      final db = await _openDb();
      addTearDown(db.close);
      await db.insert('products', {'id': 1, 'current_stock': 5, 'is_service': 0});
      await db.insert('products', {'id': 2, 'current_stock': 3, 'is_service': 0});
      await db.insert('inventory_cost_layers', {
        'product_id': 1, 'quantity_remaining': 4, 'unit_cost': 20, 'is_estimated': 1,
      });
      await db.insert('accounts', {'id': 1, 'account_code': '1200'});
      await db.insert('journal_entries', {'id': 1, 'status': 'posted'});
      await db.insert('journal_lines', {
        'journal_entry_id': 1, 'account_id': 1, 'debit': 50, 'credit': 0,
      });

      final result = await InventoryValuationReconciliation.load(db);
      expect(result['fifo_value'], 80);
      expect(result['difference'], 30);
      expect(result['estimated_quantity'], 4);
      expect(result['quantity_mismatch_count'], 2);
      expect(result['unvalued_product_count'], 1);
      expect(result['is_reconciled'], isFalse);
    });

    test('identifies legacy migration estimates for opening-balance review', () async {
      final db = await _openDb();
      addTearDown(db.close);
      await db.insert('products', {'id': 1, 'current_stock': 4, 'is_service': 0});
      await db.insert('inventory_cost_layers', {
        'product_id': 1, 'source_type': 'migration_estimate',
        'quantity_remaining': 4, 'unit_cost': 15, 'is_estimated': 1,
      });
      await db.insert('inventory_cost_layers', {
        'product_id': 1, 'source_type': 'opening_stock',
        'quantity_remaining': 2, 'unit_cost': 10, 'is_estimated': 1,
      });

      final result = await InventoryValuationReconciliation.load(db);
      expect(result['legacy_migrated_quantity'], 4);
      expect(result['legacy_migrated_value'], 60);
      expect(result['legacy_migrated_product_count'], 1);
      expect(result['estimated_quantity'], 6);
    });

    test('ignores draft journals and service products', () async {
      final db = await _openDb();
      addTearDown(db.close);
      await db.insert('products', {'id': 1, 'current_stock': 2, 'is_service': 1});
      await db.insert('accounts', {'id': 1, 'account_code': '1200'});
      await db.insert('journal_entries', {'id': 1, 'status': 'draft'});
      await db.insert('journal_lines', {
        'journal_entry_id': 1, 'account_id': 1, 'debit': 500, 'credit': 0,
      });

      final result = await InventoryValuationReconciliation.load(db);
      expect(result['fifo_value'], 0);
      expect(result['control_account_balance'], 0);
      expect(result['product_count'], 0);
      expect(result['is_reconciled'], isTrue);
    });
  });
}
