import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// FIFO inventory cost layers. Legacy on-hand stock is explicitly estimated
/// from the product's saved purchase price during the v9 migration.
class InventoryCostService {
  InventoryCostService._();

  static Future<void> receivePurchase(
    Transaction txn, {
    required int productId,
    required int invoiceId,
    required int purchaseItemId,
    required double quantity,
    required double unitCost,
    required String receivedAt,
    String? warehouseSyncId,
  }) async {
    if (!quantity.isFinite || !unitCost.isFinite ||
        quantity <= 0 || unitCost < 0) {
      throw StateError('Purchase quantity and cost must be finite valid numbers.');
    }
    await txn.insert('inventory_cost_layers', {
      'product_id': productId,
      if (warehouseSyncId != null) 'warehouse_sync_id': warehouseSyncId,
      'source_type': 'purchase',
      'source_id': invoiceId,
      'source_item_id': purchaseItemId,
      'received_at': receivedAt,
      'quantity_received': quantity,
      'quantity_remaining': quantity,
      'unit_cost': unitCost,
      'is_estimated': 0,
    });
  }


  /// Records initial stock entered when a product is first created.
  /// The layer is estimated from the product's entered purchase price.
  static Future<void> receiveOpeningStock(
    Transaction txn, {
    required int productId,
    required double quantity,
    required double unitCost,
    required String receivedAt,
    String? warehouseSyncId,
  }) async {
    if (!quantity.isFinite || quantity < 0 ||
        !unitCost.isFinite || unitCost < 0) {
      throw StateError('Opening stock quantity and cost must be finite non-negative numbers.');
    }
    if (quantity == 0) return;
    await txn.insert('inventory_cost_layers', {
      'product_id': productId,
      if (warehouseSyncId != null) 'warehouse_sync_id': warehouseSyncId,
      'source_type': 'opening_stock',
      'source_id': productId,
      'received_at': receivedAt,
      'quantity_received': quantity,
      'quantity_remaining': quantity,
      'unit_cost': unitCost,
      'is_estimated': 1,
    });
  }

  /// Calculates stock cost per unit after applying the purchase ITC decision.
  /// Recoverable or not-yet-reviewed GST stays outside inventory cost;
  /// finally ineligible GST is capitalised into stock cost.
  static double purchaseInventoryUnitCost({
    required double unitRate,
    required double taxAmount,
    required double quantity,
    required bool itcIneligible,
    double discountAmount = 0,
  }) {
    if (!unitRate.isFinite || unitRate < 0 ||
        !taxAmount.isFinite || taxAmount < 0 ||
        !quantity.isFinite || quantity <= 0 ||
        !discountAmount.isFinite || discountAmount < 0) {
      throw StateError(
        'Purchase rate, tax, discount and quantity must be finite valid numbers.',
      );
    }
    final grossValue = unitRate * quantity;
    if (!grossValue.isFinite || discountAmount > grossValue + 0.005) {
      throw StateError('Purchase discount cannot exceed the gross item value.');
    }
    final netTaxableValue = (grossValue - discountAmount).clamp(
      0.0,
      double.infinity,
    ).toDouble();
    final netUnitCost = netTaxableValue / quantity;
    final cost = itcIneligible ? netUnitCost + taxAmount / quantity : netUnitCost;
    if (!cost.isFinite || cost < 0) {
      throw StateError('Calculated purchase inventory unit cost is invalid.');
    }
    return cost;
  }

  /// Ensures a purchase return removes the same inventory value that its
  /// accounting journal reverses. Recoverable and pending-review GST is not
  /// part of inventory cost; explicitly ineligible GST is capitalised.
  static void validatePurchaseReturnInventoryValue({
    required double fifoCostRemoved,
    required double taxableSubtotal,
    required double taxAmount,
    required bool itcIneligible,
    double tolerance = 0.02,
  }) {
    if (!fifoCostRemoved.isFinite || fifoCostRemoved < 0 ||
        !taxableSubtotal.isFinite || taxableSubtotal < 0 ||
        !taxAmount.isFinite || taxAmount < 0 ||
        !tolerance.isFinite || tolerance < 0) {
      throw StateError('Purchase return inventory reconciliation values are invalid.');
    }
    final expectedInventoryCredit =
        taxableSubtotal + (itcIneligible ? taxAmount : 0);
    if ((fifoCostRemoved - expectedInventoryCredit).abs() > tolerance) {
      throw StateError(
        'Purchase return inventory value does not match the accounting reversal. '
        'Check the original purchase discount, GST and FIFO cost layer.',
      );
    }
  }

  /// Consumes oldest available cost layers and returns the FIFO cost.
  /// If historical stock has no cost layer, it is valued at the saved product
  /// purchase price and recorded as an estimate rather than silently omitted.
  static Future<double> consumeForSale(
    Transaction txn, {
    required int invoiceItemId,
    required int productId,
    required double quantity,
    required String soldAt,
    String? warehouseSyncId,
  }) async {
    if (!quantity.isFinite || quantity <= 0) {
      throw StateError('Sale quantity must be a finite positive number.');
    }
    var remaining = quantity;
    var totalCost = 0.0;
    final layers = await txn.query(
      'inventory_cost_layers',
      where: warehouseSyncId == null
          ? 'product_id = ? AND quantity_remaining > 0'
          : 'product_id = ? AND warehouse_sync_id = ? AND quantity_remaining > 0',
      whereArgs: warehouseSyncId == null ? [productId] : [productId, warehouseSyncId],
      orderBy: 'received_at ASC, id ASC',
    );
    for (final layer in layers) {
      if (remaining <= 0.0000001) break;
      final available = (layer['quantity_remaining'] as num).toDouble();
      final unitCost = (layer['unit_cost'] as num).toDouble();
      if (!available.isFinite || available <= 0 ||
          !unitCost.isFinite || unitCost < 0) {
        throw StateError('An inventory cost layer contains invalid values.');
      }
      final used = available < remaining ? available : remaining;
      final cost = used * unitCost;
      if (!cost.isFinite) throw StateError('Calculated inventory cost is invalid.');
      await txn.rawUpdate(
        'UPDATE inventory_cost_layers SET quantity_remaining = quantity_remaining - ? WHERE id = ?',
        [used, layer['id']],
      );
      await txn.insert('invoice_item_costs', {
        'invoice_item_id': invoiceItemId,
        'layer_id': layer['id'],
        'quantity': used,
        'unit_cost': unitCost,
        'total_cost': cost,
        'is_estimated': layer['is_estimated'],
      });
      totalCost += cost;
      remaining -= used;
    }

    if (remaining > 0.0000001) {
      final products = await txn.query(
        'products',
        columns: ['purchase_price'],
        where: 'id = ?',
        whereArgs: [productId],
        limit: 1,
      );
      if (products.isEmpty) throw StateError('Product cost information is missing.');
      final fallbackCost = (products.first['purchase_price'] as num).toDouble();
      if (!fallbackCost.isFinite || fallbackCost < 0) {
        throw StateError('Product purchase price is invalid.');
      }
      final layerId = await txn.insert('inventory_cost_layers', {
        'product_id': productId,
        if (warehouseSyncId != null) 'warehouse_sync_id': warehouseSyncId,
        'source_type': 'legacy_fallback',
        'source_id': null,
        'received_at': soldAt,
        'quantity_received': remaining,
        'quantity_remaining': 0,
        'unit_cost': fallbackCost,
        'is_estimated': 1,
      });
      final cost = remaining * fallbackCost;
      if (!cost.isFinite) throw StateError('Calculated inventory cost is invalid.');
      await txn.insert('invoice_item_costs', {
        'invoice_item_id': invoiceItemId,
        'layer_id': layerId,
        'quantity': remaining,
        'unit_cost': fallbackCost,
        'total_cost': cost,
        'is_estimated': 1,
      });
      totalCost += cost;
    }

    await txn.update(
      'invoice_items',
      {'cost_of_goods_sold': totalCost},
      where: 'id = ?',
      whereArgs: [invoiceItemId],
    );
    return totalCost;
  }
  /// Adds manually received stock at an estimated purchase-price cost.
  static Future<void> addAdjustmentLayer(
    Transaction txn, {
    required int productId,
    required double quantity,
    required String adjustedAt,
    String? warehouseSyncId,
  }) async {
    if (quantity <= 0 || !quantity.isFinite) {
      throw StateError('Adjustment quantity must be positive.');
    }
    final rows = await txn.query(
      'products',
      columns: ['purchase_price'],
      where: 'id = ?',
      whereArgs: [productId],
      limit: 1,
    );
    if (rows.isEmpty) throw StateError('Product cost information is missing.');
    final cost = (rows.first['purchase_price'] as num).toDouble();
    if (!cost.isFinite || cost < 0) throw StateError('Product purchase price is invalid.');
    await txn.insert('inventory_cost_layers', {
      'product_id': productId,
      if (warehouseSyncId != null) 'warehouse_sync_id': warehouseSyncId,
      'source_type': 'stock_adjustment',
      'source_id': null,
      'received_at': adjustedAt,
      'quantity_received': quantity,
      'quantity_remaining': quantity,
      'unit_cost': cost,
      'is_estimated': 1,
    });
  }

  /// Removes stock from oldest FIFO layers; missing legacy cost is estimated.
  static Future<double> removeStockAtFifo(
    Transaction txn, {
    required int productId,
    required double quantity,
    required String removedAt,
    String? warehouseSyncId,
  }) async {
    if (quantity <= 0 || !quantity.isFinite) {
      throw StateError('Removal quantity must be positive.');
    }
    var remaining = quantity;
    var totalCost = 0.0;
    final layers = await txn.query(
      'inventory_cost_layers',
      where: warehouseSyncId == null
          ? 'product_id = ? AND quantity_remaining > 0'
          : 'product_id = ? AND warehouse_sync_id = ? AND quantity_remaining > 0',
      whereArgs: warehouseSyncId == null
          ? [productId]
          : [productId, warehouseSyncId],
      orderBy: 'received_at ASC, id ASC',
    );
    for (final layer in layers) {
      if (remaining <= 0.0000001) break;
      final available = (layer['quantity_remaining'] as num).toDouble();
      final unitCost = (layer['unit_cost'] as num).toDouble();
      if (!available.isFinite || available <= 0 ||
          !unitCost.isFinite || unitCost < 0) {
        throw StateError('An inventory cost layer contains invalid values.');
      }
      final used = available < remaining ? available : remaining;
      if (!(used * unitCost).isFinite) {
        throw StateError('Calculated inventory cost is invalid.');
      }
      await txn.rawUpdate(
        'UPDATE inventory_cost_layers SET quantity_remaining = quantity_remaining - ? WHERE id = ?',
        [used, layer['id']],
      );
      totalCost += used * unitCost;
      remaining -= used;
    }
    if (remaining > 0.0000001 && warehouseSyncId != null) {
      throw StateError(
        'Insufficient stock in the selected warehouse. Unassigned or other-warehouse stock cannot be used for this adjustment.',
      );
    }
    if (remaining > 0.0000001) {
      final rows = await txn.query(
        'products',
        columns: ['purchase_price'],
        where: 'id = ?',
        whereArgs: [productId],
        limit: 1,
      );
      if (rows.isEmpty) throw StateError('Product cost information is missing.');
      final cost = (rows.first['purchase_price'] as num).toDouble();
      if (!cost.isFinite || cost < 0) throw StateError('Product purchase price is invalid.');
      await txn.insert('inventory_cost_layers', {
        'product_id': productId,
        'source_type': 'legacy_fallback',
        'source_id': null,
        'received_at': removedAt,
        'quantity_received': remaining,
        'quantity_remaining': 0,
        'unit_cost': cost,
        'is_estimated': 1,
      });
      totalCost += remaining * cost;
    }
    return totalCost;
  }


  /// Removes only the unconsumed FIFO stock received on the purchase
  /// invoice being returned. It never substitutes stock from another purchase.
  static Future<double> removePurchaseReturnAtSource(
    Transaction txn, {
    required int productId,
    required int purchaseInvoiceId,
    required int purchaseInvoiceItemId,
    required double quantity,
  }) async {
    if (!quantity.isFinite || quantity <= 0) {
      throw StateError('Purchase return quantity must be a finite positive number.');
    }
    var remaining = quantity;
    var totalCost = 0.0;
    final sourceItems = await txn.rawQuery(
      'SELECT COUNT(*) AS item_count FROM invoice_items WHERE invoice_id = ? AND product_id = ?',
      [purchaseInvoiceId, productId],
    );
    final hasSingleProductLine =
        ((sourceItems.first['item_count'] as num?)?.toInt() ?? 0) == 1;
    final layers = await txn.query(
      'inventory_cost_layers',
      where: "product_id = ? AND source_type = 'purchase' AND source_id = ? AND quantity_remaining > 0 AND (source_item_id = ? OR (source_item_id IS NULL AND ? = 1))",
      whereArgs: [
        productId,
        purchaseInvoiceId,
        purchaseInvoiceItemId,
        hasSingleProductLine ? 1 : 0,
      ],
      orderBy: 'received_at ASC, id ASC',
    );
    for (final layer in layers) {
      if (remaining <= 0.0000001) break;
      final available = (layer['quantity_remaining'] as num).toDouble();
      final unitCost = (layer['unit_cost'] as num).toDouble();
      if (!available.isFinite || available <= 0 ||
          !unitCost.isFinite || unitCost < 0) {
        throw StateError('The original purchase FIFO layer contains invalid values.');
      }
      final used = available < remaining ? available : remaining;
      final cost = used * unitCost;
      if (!cost.isFinite) throw StateError('Purchase return inventory cost is invalid.');
      await txn.rawUpdate(
        'UPDATE inventory_cost_layers SET quantity_remaining = quantity_remaining - ? WHERE id = ?',
        [used, layer['id']],
      );
      totalCost += cost;
      remaining -= used;
    }
    if (remaining > 0.0000001) {
      throw StateError(
        'The selected purchase does not have enough unconsumed stock remaining to return. Stock from another purchase was not used.',
      );
    }
    return totalCost;
  }


  /// Transfers FIFO stock between two warehouses without changing the
  /// business-wide product quantity. Each destination layer preserves the
  /// exact source-layer unit cost and estimated-cost flag.
  static Future<double> transferBetweenWarehouses(
    Transaction txn, {
    required int productId,
    required String sourceWarehouseSyncId,
    required String destinationWarehouseSyncId,
    required double quantity,
    required String transferredAt,
  }) async {
    if (sourceWarehouseSyncId.trim().isEmpty ||
        destinationWarehouseSyncId.trim().isEmpty ||
        sourceWarehouseSyncId == destinationWarehouseSyncId) {
      throw StateError('Select two different valid warehouses.');
    }
    if (!quantity.isFinite || quantity <= 0) {
      throw StateError('Transfer quantity must be finite and greater than zero.');
    }

    final sourceWarehouse = await txn.query(
      'warehouses',
      columns: ['sync_id'],
      where: 'sync_id = ? AND is_active = 1',
      whereArgs: [sourceWarehouseSyncId],
      limit: 1,
    );
    final destinationWarehouse = await txn.query(
      'warehouses',
      columns: ['sync_id'],
      where: 'sync_id = ? AND is_active = 1',
      whereArgs: [destinationWarehouseSyncId],
      limit: 1,
    );
    if (sourceWarehouse.isEmpty || destinationWarehouse.isEmpty) {
      throw StateError('Both source and destination warehouses must be active.');
    }

    final layers = await txn.query(
      'inventory_cost_layers',
      where: 'product_id = ? AND warehouse_sync_id = ? AND quantity_remaining > 0',
      whereArgs: [productId, sourceWarehouseSyncId],
      orderBy: 'received_at ASC, id ASC',
    );
    final available = layers.fold<double>(
      0,
      (sum, row) => sum + (row['quantity_remaining'] as num).toDouble(),
    );
    if (!available.isFinite || available + 0.0000001 < quantity) {
      throw StateError(
        'Insufficient stock in the source warehouse. Other-warehouse and unassigned stock cannot be transferred.',
      );
    }

    var remaining = quantity;
    var totalCost = 0.0;
    for (final layer in layers) {
      if (remaining <= 0.0000001) break;
      final layerQuantity = (layer['quantity_remaining'] as num).toDouble();
      final unitCost = (layer['unit_cost'] as num).toDouble();
      if (!layerQuantity.isFinite || layerQuantity <= 0 ||
          !unitCost.isFinite || unitCost < 0) {
        throw StateError('A source FIFO layer contains invalid values.');
      }
      final moved = layerQuantity < remaining ? layerQuantity : remaining;
      final layerCost = moved * unitCost;
      if (!layerCost.isFinite) {
        throw StateError('Calculated transfer inventory value is invalid.');
      }
      await txn.rawUpdate(
        'UPDATE inventory_cost_layers SET quantity_remaining = quantity_remaining - ? WHERE id = ?',
        [moved, layer['id']],
      );
      await txn.insert('inventory_cost_layers', {
        'product_id': productId,
        'warehouse_sync_id': destinationWarehouseSyncId,
        'source_type': 'warehouse_transfer',
        'source_id': null,
        'received_at': transferredAt,
        'quantity_received': moved,
        'quantity_remaining': moved,
        'unit_cost': unitCost,
        'is_estimated': layer['is_estimated'] ?? 1,
      });
      totalCost += layerCost;
      remaining -= moved;
    }
    if (remaining > 0.0000001) {
      throw StateError('The source warehouse FIFO stock changed during transfer.');
    }
    return totalCost;
  }


  /// Restores returned sale quantities into FIFO inventory using the exact
  /// cost allocations recorded against the original sale item.
  static Future<double> restoreSalesReturn(
    Transaction txn, {
    required int returnItemId,
    required int originalInvoiceItemId,
    required int productId,
    required double quantity,
    required String returnedAt,
    String? warehouseSyncId,
  }) async {
    if (quantity <= 0 || !quantity.isFinite) {
      throw StateError('Sales return quantity must be positive.');
    }
    final priorRows = await txn.rawQuery(
      'SELECT COALESCE(SUM(quantity), 0) AS qty FROM invoice_items WHERE original_invoice_item_id = ? AND id != ?',
      [originalInvoiceItemId, returnItemId],
    );
    var alreadyReturned = (priorRows.first['qty'] as num?)?.toDouble() ?? 0;
    var remaining = quantity;
    var totalCost = 0.0;
    final allocations = await txn.query(
      'invoice_item_costs',
      where: 'invoice_item_id = ?',
      whereArgs: [originalInvoiceItemId],
      orderBy: 'id ASC',
    );
    for (final allocation in allocations) {
      final allocatedQty = (allocation['quantity'] as num).toDouble();
      if (alreadyReturned >= allocatedQty - 0.0000001) {
        alreadyReturned -= allocatedQty;
        continue;
      }
      final available = allocatedQty - alreadyReturned;
      alreadyReturned = 0;
      if (remaining <= 0.0000001) break;
      final usedQty = available < remaining ? available : remaining;
      final unitCost = (allocation['unit_cost'] as num).toDouble();
      if (!unitCost.isFinite || unitCost < 0) {
        throw StateError('An original sale cost allocation contains invalid values.');
      }
      final cost = usedQty * unitCost;
      if (!cost.isFinite) throw StateError('Calculated return cost is invalid.');
      final layerId = await txn.insert('inventory_cost_layers', {
        'product_id': productId,
        if (warehouseSyncId != null) 'warehouse_sync_id': warehouseSyncId,
        'source_type': 'sales_return',
        'source_id': returnItemId,
        'received_at': returnedAt,
        'quantity_received': usedQty,
        'quantity_remaining': usedQty,
        'unit_cost': unitCost,
        'is_estimated': allocation['is_estimated'] ?? 1,
      });
      await txn.insert('invoice_item_costs', {
        'invoice_item_id': returnItemId,
        'layer_id': layerId,
        'quantity': usedQty,
        'unit_cost': unitCost,
        'total_cost': cost,
        'is_estimated': allocation['is_estimated'] ?? 1,
      });
      totalCost += cost;
      remaining -= usedQty;
    }
    if (remaining > 0.0000001) {
      final rows = await txn.query(
        'products',
        columns: ['purchase_price'],
        where: 'id = ?',
        whereArgs: [productId],
        limit: 1,
      );
      if (rows.isEmpty) throw StateError('Product cost information is missing.');
      final unitCost = (rows.first['purchase_price'] as num).toDouble();
      if (!unitCost.isFinite || unitCost < 0) {
        throw StateError('Product purchase price is invalid.');
      }
      final cost = remaining * unitCost;
      if (!cost.isFinite) throw StateError('Calculated return cost is invalid.');
      final layerId = await txn.insert('inventory_cost_layers', {
        'product_id': productId,
        if (warehouseSyncId != null) 'warehouse_sync_id': warehouseSyncId,
        'source_type': 'sales_return_estimate',
        'source_id': returnItemId,
        'received_at': returnedAt,
        'quantity_received': remaining,
        'quantity_remaining': remaining,
        'unit_cost': unitCost,
        'is_estimated': 1,
      });
      await txn.insert('invoice_item_costs', {
        'invoice_item_id': returnItemId,
        'layer_id': layerId,
        'quantity': remaining,
        'unit_cost': unitCost,
        'total_cost': cost,
        'is_estimated': 1,
      });
      totalCost += cost;
    }
    await txn.update(
      'invoice_items',
      {'cost_of_goods_sold': totalCost},
      where: 'id = ?',
      whereArgs: [returnItemId],
    );
    return totalCost;
  }

}
