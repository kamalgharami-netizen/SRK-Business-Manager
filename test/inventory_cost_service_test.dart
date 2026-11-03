import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:srk_business_manager/src/data/local/inventory_cost_service.dart';

void main() {
  group('Opening stock FIFO valuation', () {
    test('records opening stock as an estimated FIFO layer', () async {
      sqfliteFfiInit();
      final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
      addTearDown(db.close);
      await db.execute('''
        CREATE TABLE inventory_cost_layers (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          product_id INTEGER NOT NULL,
          source_type TEXT NOT NULL,
          source_id INTEGER,
          received_at TEXT NOT NULL,
          quantity_received REAL NOT NULL,
          quantity_remaining REAL NOT NULL,
          unit_cost REAL NOT NULL,
          is_estimated INTEGER NOT NULL DEFAULT 0
        )
      ''');

      await db.transaction((txn) => InventoryCostService.receiveOpeningStock(
            txn,
            productId: 9,
            quantity: 4,
            unitCost: 75,
            receivedAt: '2026-11-03T09:00:00',
          ));

      final rows = await db.query('inventory_cost_layers');
      expect(rows, hasLength(1));
      expect(rows.single['source_type'], 'opening_stock');
      expect(rows.single['source_id'], 9);
      expect(rows.single['quantity_received'], 4);
      expect(rows.single['quantity_remaining'], 4);
      expect(rows.single['unit_cost'], 75);
      expect(rows.single['is_estimated'], 1);
    });

    test('does not create a layer for zero opening stock', () async {
      sqfliteFfiInit();
      final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
      addTearDown(db.close);
      await db.execute('''
        CREATE TABLE inventory_cost_layers (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          product_id INTEGER NOT NULL,
          source_type TEXT NOT NULL,
          source_id INTEGER,
          received_at TEXT NOT NULL,
          quantity_received REAL NOT NULL,
          quantity_remaining REAL NOT NULL,
          unit_cost REAL NOT NULL,
          is_estimated INTEGER NOT NULL DEFAULT 0
        )
      ''');

      await db.transaction((txn) => InventoryCostService.receiveOpeningStock(
            txn,
            productId: 9,
            quantity: 0,
            unitCost: 75,
            receivedAt: '2026-11-03T09:00:00',
          ));
      expect(await db.query('inventory_cost_layers'), isEmpty);
    });
  });

  group('Warehouse-aware FIFO receiving', () {
    test('stores a stable warehouse sync ID on a purchase cost layer', () async {
      sqfliteFfiInit();
      final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
      addTearDown(db.close);
      await db.execute('''
        CREATE TABLE inventory_cost_layers (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          product_id INTEGER NOT NULL,
          warehouse_sync_id TEXT,
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
      await db.transaction((txn) => InventoryCostService.receivePurchase(
            txn,
            productId: 9,
            invoiceId: 101,
            purchaseItemId: 1001,
            quantity: 3,
            unitCost: 125,
            receivedAt: '2026-11-03T10:00:00',
            warehouseSyncId: 'warehouse-main-sync-id',
          ));
      final rows = await db.query('inventory_cost_layers');
      expect(rows, hasLength(1));
      expect(rows.single['warehouse_sync_id'], 'warehouse-main-sync-id');
      expect(rows.single['quantity_remaining'], 3);
    });
  });

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

  group('Purchase return inventory and ledger reconciliation', () {
    test('matches FIFO cost to taxable value when GST is recoverable', () {
      expect(
        () => InventoryCostService.validatePurchaseReturnInventoryValue(
          fifoCostRemoved: 180,
          taxableSubtotal: 180,
          taxAmount: 32.4,
          itcIneligible: false,
        ),
        returnsNormally,
      );
    });

    test('includes GST in inventory value only when ITC is ineligible', () {
      expect(
        () => InventoryCostService.validatePurchaseReturnInventoryValue(
          fifoCostRemoved: 212.4,
          taxableSubtotal: 180,
          taxAmount: 32.4,
          itcIneligible: true,
        ),
        returnsNormally,
      );
    });

    test('rejects mismatch between FIFO stock value and ledger reversal', () {
      expect(
        () => InventoryCostService.validatePurchaseReturnInventoryValue(
          fifoCostRemoved: 180,
          taxableSubtotal: 180,
          taxAmount: 32.4,
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



  group('Warehouse FIFO stock transfers', () {
    Future<Database> openTransferDatabase() async {
      sqfliteFfiInit();
      final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
      await db.execute('''
        CREATE TABLE products (
          id INTEGER PRIMARY KEY,
          purchase_price REAL NOT NULL
        )
      ''');
      await db.execute('''
        CREATE TABLE warehouses (
          id INTEGER PRIMARY KEY,
          sync_id TEXT NOT NULL UNIQUE,
          is_active INTEGER NOT NULL DEFAULT 1
        )
      ''');
      await db.execute('''
        CREATE TABLE inventory_cost_layers (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          product_id INTEGER NOT NULL,
          warehouse_sync_id TEXT,
          source_type TEXT NOT NULL,
          source_id INTEGER,
          received_at TEXT NOT NULL,
          quantity_received REAL NOT NULL,
          quantity_remaining REAL NOT NULL,
          unit_cost REAL NOT NULL,
          is_estimated INTEGER NOT NULL DEFAULT 0
        )
      ''');
      await db.insert('products', {'id': 1, 'purchase_price': 50});
      await db.insert('warehouses', {'sync_id': 'warehouse-A'});
      await db.insert('warehouses', {'sync_id': 'warehouse-B'});
      return db;
    }

    test('moves FIFO quantities and preserves each source layer cost', () async {
      final db = await openTransferDatabase();
      addTearDown(db.close);
      await db.insert('inventory_cost_layers', {
        'product_id': 1, 'warehouse_sync_id': 'warehouse-A',
        'source_type': 'purchase', 'received_at': '2026-11-01',
        'quantity_received': 2, 'quantity_remaining': 2,
        'unit_cost': 100, 'is_estimated': 0,
      });
      await db.insert('inventory_cost_layers', {
        'product_id': 1, 'warehouse_sync_id': 'warehouse-A',
        'source_type': 'purchase', 'received_at': '2026-11-02',
        'quantity_received': 5, 'quantity_remaining': 5,
        'unit_cost': 125, 'is_estimated': 1,
      });
      final cost = await db.transaction((txn) =>
          InventoryCostService.transferBetweenWarehouses(
            txn,
            productId: 1,
            sourceWarehouseSyncId: 'warehouse-A',
            destinationWarehouseSyncId: 'warehouse-B',
            quantity: 4,
            transferredAt: '2026-11-03T12:00:00',
          ));
      final rows = await db.query('inventory_cost_layers', orderBy: 'id');
      expect(cost, 450);
      expect(rows[0]['quantity_remaining'], 0);
      expect(rows[1]['quantity_remaining'], 3);
      expect(rows[2]['warehouse_sync_id'], 'warehouse-B');
      expect(rows[2]['quantity_remaining'], 2);
      expect(rows[2]['unit_cost'], 100);
      expect(rows[2]['is_estimated'], 0);
      expect(rows[3]['warehouse_sync_id'], 'warehouse-B');
      expect(rows[3]['quantity_remaining'], 2);
      expect(rows[3]['unit_cost'], 125);
      expect(rows[3]['is_estimated'], 1);
    });

    test('rejects same warehouse and inactive warehouse transfers', () async {
      final db = await openTransferDatabase();
      addTearDown(db.close);
      await expectLater(
        db.transaction((txn) => InventoryCostService.transferBetweenWarehouses(
          txn,
          productId: 1,
          sourceWarehouseSyncId: 'warehouse-A',
          destinationWarehouseSyncId: 'warehouse-A',
          quantity: 1,
          transferredAt: '2026-11-03T12:00:00',
        )),
        throwsA(isA<StateError>()),
      );
      await db.update('warehouses', {'is_active': 0},
          where: 'sync_id = ?', whereArgs: ['warehouse-B']);
      await expectLater(
        db.transaction((txn) => InventoryCostService.transferBetweenWarehouses(
          txn,
          productId: 1,
          sourceWarehouseSyncId: 'warehouse-A',
          destinationWarehouseSyncId: 'warehouse-B',
          quantity: 1,
          transferredAt: '2026-11-03T12:00:00',
        )),
        throwsA(isA<StateError>()),
      );
    });

    test('replays a cloud transfer against matching source FIFO layers', () async {
      final db = await openTransferDatabase();
      addTearDown(db.close);
      await db.insert('inventory_cost_layers', {
        'product_id': 1, 'warehouse_sync_id': 'warehouse-A',
        'source_type': 'purchase', 'received_at': '2026-11-01',
        'quantity_received': 3, 'quantity_remaining': 3,
        'unit_cost': 100, 'is_estimated': 0,
      });
      final cost = await db.transaction((txn) =>
          InventoryCostService.applyRemoteWarehouseTransferLayers(
            txn,
            productId: 1,
            sourceWarehouseSyncId: 'warehouse-A',
            destinationWarehouseSyncId: 'warehouse-B',
            layers: [
              {'quantity': 2, 'unit_cost': 100, 'is_estimated': 0},
            ],
            transferredAt: '2026-11-03T12:00:00',
            expectedTotalCost: 200,
          ));
      final rows = await db.query('inventory_cost_layers', orderBy: 'id');
      expect(cost, 200);
      expect(rows[0]['quantity_remaining'], 1);
      expect(rows[1]['warehouse_sync_id'], 'warehouse-B');
      expect(rows[1]['quantity_remaining'], 2);
      expect(rows[1]['unit_cost'], 100);
    });

    test('rejects a cloud transfer when source FIFO cost differs', () async {
      final db = await openTransferDatabase();
      addTearDown(db.close);
      await db.insert('inventory_cost_layers', {
        'product_id': 1, 'warehouse_sync_id': 'warehouse-A',
        'source_type': 'purchase', 'received_at': '2026-11-01',
        'quantity_received': 3, 'quantity_remaining': 3,
        'unit_cost': 125, 'is_estimated': 0,
      });
      await expectLater(
        db.transaction((txn) =>
            InventoryCostService.applyRemoteWarehouseTransferLayers(
              txn,
              productId: 1,
              sourceWarehouseSyncId: 'warehouse-A',
              destinationWarehouseSyncId: 'warehouse-B',
              layers: [
                {'quantity': 2, 'unit_cost': 100, 'is_estimated': 0},
              ],
              transferredAt: '2026-11-03T12:00:00',
              expectedTotalCost: 200,
            )),
        throwsA(isA<StateError>()),
      );
      final rows = await db.query('inventory_cost_layers', orderBy: 'id');
      expect(rows.length, 1);
      expect(rows.single['quantity_remaining'], 3);
    });

    test('rejects source shortage without changing any FIFO layer', () async {
      final db = await openTransferDatabase();
      addTearDown(db.close);
      await db.insert('inventory_cost_layers', {
        'product_id': 1, 'warehouse_sync_id': 'warehouse-A',
        'source_type': 'purchase', 'received_at': '2026-11-01',
        'quantity_received': 2, 'quantity_remaining': 2,
        'unit_cost': 100, 'is_estimated': 0,
      });
      await db.insert('inventory_cost_layers', {
        'product_id': 1, 'warehouse_sync_id': null,
        'source_type': 'legacy', 'received_at': '2026-11-01',
        'quantity_received': 8, 'quantity_remaining': 8,
        'unit_cost': 80, 'is_estimated': 1,
      });
      await expectLater(
        db.transaction((txn) => InventoryCostService.transferBetweenWarehouses(
          txn,
          productId: 1,
          sourceWarehouseSyncId: 'warehouse-A',
          destinationWarehouseSyncId: 'warehouse-B',
          quantity: 3,
          transferredAt: '2026-11-03T12:00:00',
        )),
        throwsA(isA<StateError>()),
      );
      final rows = await db.query('inventory_cost_layers', orderBy: 'id');
      expect(rows.length, 2);
      expect(rows[0]['quantity_remaining'], 2);
      expect(rows[1]['quantity_remaining'], 8);
    });
  });


  group('Warehouse-scoped stock adjustments', () {
    Future<Database> openWarehouseDatabase() async {
      sqfliteFfiInit();
      final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
      await db.execute('''
        CREATE TABLE products (
          id INTEGER PRIMARY KEY,
          purchase_price REAL NOT NULL
        )
      ''');
      await db.execute('''
        CREATE TABLE inventory_cost_layers (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          product_id INTEGER NOT NULL,
          warehouse_sync_id TEXT,
          source_type TEXT NOT NULL,
          source_id INTEGER,
          received_at TEXT NOT NULL,
          quantity_received REAL NOT NULL,
          quantity_remaining REAL NOT NULL,
          unit_cost REAL NOT NULL,
          is_estimated INTEGER NOT NULL DEFAULT 0
        )
      ''');
      await db.insert('products', {'id': 1, 'purchase_price': 50});
      return db;
    }

    test('adds an adjustment layer to the selected warehouse', () async {
      final db = await openWarehouseDatabase();
      addTearDown(db.close);
      await db.transaction((txn) => InventoryCostService.addAdjustmentLayer(
            txn,
            productId: 1,
            quantity: 4,
            adjustedAt: '2026-11-03T12:00:00',
            warehouseSyncId: 'warehouse-A',
          ));
      final rows = await db.query('inventory_cost_layers');
      expect(rows.single['warehouse_sync_id'], 'warehouse-A');
      expect(rows.single['quantity_remaining'], 4);
      expect(rows.single['unit_cost'], 50);
    });

    test('removes FIFO quantity only from the selected warehouse', () async {
      final db = await openWarehouseDatabase();
      addTearDown(db.close);
      await db.insert('inventory_cost_layers', {
        'product_id': 1, 'warehouse_sync_id': 'warehouse-A',
        'source_type': 'purchase', 'received_at': '2026-11-01',
        'quantity_received': 5, 'quantity_remaining': 5, 'unit_cost': 100,
      });
      await db.insert('inventory_cost_layers', {
        'product_id': 1, 'warehouse_sync_id': 'warehouse-B',
        'source_type': 'purchase', 'received_at': '2026-11-01',
        'quantity_received': 7, 'quantity_remaining': 7, 'unit_cost': 200,
      });
      final cost = await db.transaction((txn) =>
          InventoryCostService.removeStockAtFifo(
            txn,
            productId: 1,
            quantity: 3,
            removedAt: '2026-11-03T12:00:00',
            warehouseSyncId: 'warehouse-A',
          ));
      final rows = await db.query('inventory_cost_layers', orderBy: 'id');
      expect(cost, 300);
      expect(rows[0]['quantity_remaining'], 2);
      expect(rows[1]['quantity_remaining'], 7);
    });

    test('does not consume another warehouse or unassigned stock on shortage', () async {
      final db = await openWarehouseDatabase();
      addTearDown(db.close);
      await db.insert('inventory_cost_layers', {
        'product_id': 1, 'warehouse_sync_id': 'warehouse-B',
        'source_type': 'purchase', 'received_at': '2026-11-01',
        'quantity_received': 7, 'quantity_remaining': 7, 'unit_cost': 200,
      });
      await db.insert('inventory_cost_layers', {
        'product_id': 1, 'warehouse_sync_id': null,
        'source_type': 'legacy', 'received_at': '2026-11-01',
        'quantity_received': 6, 'quantity_remaining': 6, 'unit_cost': 80,
      });
      await expectLater(
        db.transaction((txn) => InventoryCostService.removeStockAtFifo(
              txn,
              productId: 1,
              quantity: 2,
              removedAt: '2026-11-03T12:00:00',
              warehouseSyncId: 'warehouse-A',
            )),
        throwsA(isA<StateError>()),
      );
      final rows = await db.query('inventory_cost_layers', orderBy: 'id');
      expect(rows[0]['quantity_remaining'], 7);
      expect(rows[1]['quantity_remaining'], 6);
    });
  });
}
