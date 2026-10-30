import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// FIFO inventory cost layers. Legacy on-hand stock is explicitly estimated
/// from the product's saved purchase price during the v9 migration.
class InventoryCostService {
  InventoryCostService._();

  static Future<void> receivePurchase(
    Transaction txn, {
    required int productId,
    required int invoiceId,
    required double quantity,
    required double unitCost,
    required String receivedAt,
  }) async {
    if (quantity <= 0 || unitCost < 0) {
      throw StateError('Purchase quantity and cost must be valid.');
    }
    await txn.insert('inventory_cost_layers', {
      'product_id': productId,
      'source_type': 'purchase',
      'source_id': invoiceId,
      'received_at': receivedAt,
      'quantity_received': quantity,
      'quantity_remaining': quantity,
      'unit_cost': unitCost,
      'is_estimated': 0,
    });
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
  }) async {
    if (quantity <= 0) throw StateError('Sale quantity must be positive.');
    var remaining = quantity;
    var totalCost = 0.0;
    final layers = await txn.query(
      'inventory_cost_layers',
      where: 'product_id = ? AND quantity_remaining > 0',
      whereArgs: [productId],
      orderBy: 'received_at ASC, id ASC',
    );
    for (final layer in layers) {
      if (remaining <= 0.0000001) break;
      final available = (layer['quantity_remaining'] as num).toDouble();
      final used = available < remaining ? available : remaining;
      final unitCost = (layer['unit_cost'] as num).toDouble();
      final cost = used * unitCost;
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
      final layerId = await txn.insert('inventory_cost_layers', {
        'product_id': productId,
        'source_type': 'legacy_fallback',
        'source_id': null,
        'received_at': soldAt,
        'quantity_received': remaining,
        'quantity_remaining': 0,
        'unit_cost': fallbackCost,
        'is_estimated': 1,
      });
      final cost = remaining * fallbackCost;
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
}
