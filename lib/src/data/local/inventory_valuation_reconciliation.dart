import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Read-only comparison of live FIFO stock valuation with the Inventory
/// control account. This is a current-state check, not a historical snapshot.
class InventoryValuationReconciliation {
  InventoryValuationReconciliation._();

  static Future<Map<String, Object?>> load(DatabaseExecutor db) async {
    final products = await db.rawQuery('''
      SELECT p.id, p.current_stock,
        COALESCE(SUM(l.quantity_remaining), 0) AS layer_quantity,
        COALESCE(SUM(l.quantity_remaining * l.unit_cost), 0) AS fifo_value,
        COALESCE(SUM(CASE WHEN l.is_estimated = 1
          THEN l.quantity_remaining ELSE 0 END), 0) AS estimated_quantity,
        COALESCE(SUM(CASE WHEN l.source_type = 'migration_estimate'
          THEN l.quantity_remaining ELSE 0 END), 0) AS legacy_migrated_quantity,
        COALESCE(SUM(CASE WHEN l.source_type = 'migration_estimate'
          THEN l.quantity_remaining * l.unit_cost ELSE 0 END), 0) AS legacy_migrated_value
      FROM products p
      LEFT JOIN inventory_cost_layers l
        ON l.product_id = p.id AND l.quantity_remaining > 0
      WHERE (p.is_service = 0 OR p.is_service IS NULL)
      GROUP BY p.id, p.current_stock
    ''');

    var fifoValue = 0.0;
    var estimatedQuantity = 0.0;
    var legacyMigratedQuantity = 0.0;
    var legacyMigratedValue = 0.0;
    var legacyMigratedProductCount = 0;
    var quantityMismatchCount = 0;
    var quantityMismatchTotal = 0.0;
    var unvaluedProductCount = 0;
    for (final row in products) {
      final current = (row['current_stock'] as num).toDouble();
      final layerQuantity = (row['layer_quantity'] as num).toDouble();
      final value = (row['fifo_value'] as num).toDouble();
      final estimated = (row['estimated_quantity'] as num).toDouble();
      final legacyQuantity =
          (row['legacy_migrated_quantity'] as num).toDouble();
      final legacyValue =
          (row['legacy_migrated_value'] as num).toDouble();
      if (![current, layerQuantity, value, estimated, legacyQuantity, legacyValue].every((v) => v.isFinite) ||
          current < 0 || layerQuantity < 0 || value < 0 || estimated < 0) {
        throw StateError('Inventory valuation contains invalid quantities or costs.');
      }
      fifoValue += value;
      estimatedQuantity += estimated;
      legacyMigratedQuantity += legacyQuantity;
      legacyMigratedValue += legacyValue;
      if (legacyQuantity > 0.000001) legacyMigratedProductCount++;
      if ((current - layerQuantity).abs() > 0.000001) {
        quantityMismatchCount++;
        quantityMismatchTotal += (current - layerQuantity).abs();
      }
      if (current > 0 && layerQuantity <= 0.000001) {
        unvaluedProductCount++;
      }
    }
    if (!fifoValue.isFinite || !estimatedQuantity.isFinite ||
        !legacyMigratedQuantity.isFinite || !legacyMigratedValue.isFinite ||
        !quantityMismatchTotal.isFinite) {
      throw StateError('Inventory reconciliation totals are invalid.');
    }

    final controlRows = await db.rawQuery('''
      SELECT COALESCE(SUM(jl.debit - jl.credit), 0) AS balance
      FROM journal_lines jl
      INNER JOIN journal_entries je ON je.id = jl.journal_entry_id
      INNER JOIN accounts a ON a.id = jl.account_id
      WHERE a.account_code = '1200' AND je.status = 'posted'
    ''');
    final controlBalance = (controlRows.first['balance'] as num).toDouble();
    final difference = fifoValue - controlBalance;
    final reconciled = difference.abs() <= 0.01 &&
        quantityMismatchCount == 0 && unvaluedProductCount == 0;

    return {
      'fifo_value': fifoValue,
      'control_account_balance': controlBalance,
      'difference': difference,
      'estimated_quantity': estimatedQuantity,
      'legacy_migrated_quantity': legacyMigratedQuantity,
      'legacy_migrated_value': legacyMigratedValue,
      'legacy_migrated_product_count': legacyMigratedProductCount,
      'quantity_mismatch_count': quantityMismatchCount,
      'quantity_mismatch_total': quantityMismatchTotal,
      'unvalued_product_count': unvaluedProductCount,
      'product_count': products.length,
      'is_reconciled': reconciled,
    };
  }
}
