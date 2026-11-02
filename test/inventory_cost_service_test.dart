import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:srk_business_manager/src/data/local/inventory_cost_service.dart';

void main() {
  group('Purchase inventory cost and ITC treatment', () {
    test('keeps eligible GST outside FIFO inventory unit cost', () {
      expect(
        InventoryCostService.purchaseInventoryUnitCost(
          unitRate: 100,
          taxAmount: 18,
          quantity: 2,
          itcIneligible: false,
        ),
        100,
      );
    });

    test('capitalises ineligible GST into FIFO inventory unit cost', () {
      expect(
        InventoryCostService.purchaseInventoryUnitCost(
          unitRate: 100,
          taxAmount: 36,
          quantity: 2,
          itcIneligible: true,
        ),
        118,
      );
    });

    test('deducts purchase discount from eligible inventory cost', () {
      expect(
        InventoryCostService.purchaseInventoryUnitCost(
          unitRate: 100,
          taxAmount: 18,
          quantity: 2,
          discountAmount: 20,
          itcIneligible: false,
        ),
        90,
      );
    });

    test('deducts discount before capitalising ineligible GST', () {
      expect(
        InventoryCostService.purchaseInventoryUnitCost(
          unitRate: 100,
          taxAmount: 32.4,
          quantity: 2,
          discountAmount: 20,
          itcIneligible: true,
        ),
        106.2,
      );
    });

    test('rejects a discount greater than gross purchase value', () {
      expect(
        () => InventoryCostService.purchaseInventoryUnitCost(
          unitRate: 100,
          taxAmount: 18,
          quantity: 2,
          discountAmount: 201,
          itcIneligible: false,
        ),
        throwsA(isA<StateError>()),
      );
    });

    test('rejects invalid purchase cost inputs', () {
      expect(
        () => InventoryCostService.purchaseInventoryUnitCost(
          unitRate: 100,
          taxAmount: 18,
          quantity: 0,
          itcIneligible: true,
        ),
        throwsA(isA<StateError>()),
      );
      expect(
        () => InventoryCostService.purchaseInventoryUnitCost(
          unitRate: double.infinity,
          taxAmount: 18,
          quantity: 1,
          itcIneligible: true,
        ),
        throwsA(isA<StateError>()),
      );
    });
  });

  group('Purchase return FIFO source protection', () {
    Future<Database> openDatabaseForReturn() async {
      sqfliteFfiInit();
      final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
      await db.execute('''
        CREATE TABLE products (
          id INTEGER PRIMARY KEY,
          purchase_price REAL NOT NULL
        )
      ''');
      await db.execute('''
        CREATE TABLE invoice_items (
          id INTEGER PRIMARY KEY,
          invoice_id INTEGER NOT NULL,
          product_id INTEGER
        )
      ''');
      await db.execute('''
        CREATE TABLE inventory_cost_layers (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          product_id INTEGER NOT NULL,
          source_type TEXT NOT NULL,
          source_id INTEGER,
          source_item_id INTEGER,
          received_at TEXT NOT NULL,
          quantity_received REAL NOT NULL,
          quantity_remaining REAL NOT NULL,
          unit_cost REAL NOT NULL,
          is_estimated INTEGER NOT NULL DEFAULT 0
        )
      ''');
      return db;
    }

    test('removes returned quantity only from the original purchase layer', () async {
      final db = await openDatabaseForReturn();
      addTearDown(db.close);
      await db.insert('invoice_items', {'id': 101, 'invoice_id': 10, 'product_id': 1});
      final originalLayer = await db.insert('inventory_cost_layers', {
        'product_id': 1, 'source_type': 'purchase', 'source_id': 10,
        'source_item_id': 101, 'received_at': '2026-10-01',
        'quantity_received': 5, 'quantity_remaining': 5, 'unit_cost': 100,
      });
      final otherLayer = await db.insert('inventory_cost_layers', {
        'product_id': 1, 'source_type': 'purchase', 'source_id': 11,
        'source_item_id': 111, 'received_at': '2026-10-02',
        'quantity_received': 8, 'quantity_remaining': 8, 'unit_cost': 120,
      });

      final cost = await db.transaction((txn) =>
          InventoryCostService.removePurchaseReturnAtSource(
            txn,
            productId: 1,
            purchaseInvoiceId: 10,
            purchaseInvoiceItemId: 101,
            quantity: 2,
          ));

      expect(cost, 200);
      final original = await db.query('inventory_cost_layers', where: 'id = ?', whereArgs: [originalLayer]);
      final other = await db.query('inventory_cost_layers', where: 'id = ?', whereArgs: [otherLayer]);
      expect(original.single['quantity_remaining'], 3);
      expect(other.single['quantity_remaining'], 8);
    });

    test('rejects return quantity beyond unconsumed stock from that purchase', () async {
      final db = await openDatabaseForReturn();
      addTearDown(db.close);
      await db.insert('invoice_items', {'id': 201, 'invoice_id': 20, 'product_id': 2});
      await db.insert('products', {'id': 2, 'purchase_price': 99});
      await db.insert('inventory_cost_layers', {
        'product_id': 2, 'source_type': 'purchase', 'source_id': 20,
        'source_item_id': 201, 'received_at': '2026-10-01',
        'quantity_received': 5, 'quantity_remaining': 1, 'unit_cost': 100,
      });
      await db.insert('inventory_cost_layers', {
        'product_id': 2, 'source_type': 'purchase', 'source_id': 21,
        'source_item_id': 211, 'received_at': '2026-10-02',
        'quantity_received': 10, 'quantity_remaining': 10, 'unit_cost': 110,
      });

      await expectLater(
        db.transaction((txn) =>
            InventoryCostService.removePurchaseReturnAtSource(
              txn,
              productId: 2,
              purchaseInvoiceId: 20,
              purchaseInvoiceItemId: 201,
              quantity: 2,
            )),
        throwsA(isA<StateError>()),
      );
      final layers = await db.query('inventory_cost_layers', orderBy: 'id');
      expect(layers[0]['quantity_remaining'], 1);
      expect(layers[1]['quantity_remaining'], 10);
    });
  });
}
