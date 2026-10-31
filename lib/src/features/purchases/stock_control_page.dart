import 'package:flutter/material.dart';

import '../../data/local/app_database.dart';
import '../../data/local/accounting_service.dart';
import '../../data/local/inventory_cost_service.dart';
import '../../data/sync/business_sync_service.dart';
import '../invoices/invoice_pdf_service.dart';


class _ReturnLine {
  _ReturnLine({required this.item, required this.available});
  final Map<String, Object?> item;
  final double available;
  bool selected = false;
  final TextEditingController quantity = TextEditingController(text: '1');

  void dispose() => quantity.dispose();
}

class StockControlPage extends StatefulWidget {
  const StockControlPage({super.key});

  @override
  State<StockControlPage> createState() => _StockControlPageState();
}

class _StockControlPageState extends State<StockControlPage> {
  List<Map<String, Object?>> _movements = [];
  List<Map<String, Object?>> _returns = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadMovements();
  }

  Future<void> _syncIfConfigured() async {
    final businessId = AppDatabase.instance.activeBusinessId;
    if (businessId == null) return;
    try {
      await BusinessSyncService(businessId: businessId).syncNow();
    } catch (error) {
      _message('Cloud sync unavailable; stock changes remain saved locally. $error');
    }
  }

  Future<void> _loadMovements() async {
    final db = await AppDatabase.instance.database;
    final rows = await db.rawQuery('''
      SELECT m.*, p.name AS product_name, p.unit
      FROM stock_movements m
      JOIN products p ON p.id = m.product_id
      ORDER BY m.id DESC
      LIMIT 100
    ''');
    final returns = await db.rawQuery('''
      SELECT r.*, p.name AS party_name, original.invoice_number AS original_invoice_number
      FROM invoices r
      LEFT JOIN parties p ON p.id = r.party_id
      LEFT JOIN invoices original ON original.id = r.parent_invoice_id
      WHERE r.invoice_type = 'purchase_return'
      ORDER BY r.id DESC
    ''');
    if (!mounted) return;
    setState(() {
      _movements = rows;
      _returns = returns;
      _loading = false;
    });
  }


  Future<void> _purchaseReturn() async {
    final db = await AppDatabase.instance.database;
    final purchases = await db.rawQuery('''
      SELECT i.*, p.name AS supplier_name
      FROM invoices i
      LEFT JOIN parties p ON p.id = i.party_id
      WHERE i.invoice_type = 'purchase'
      ORDER BY i.id DESC
    ''');
    if (!mounted) return;
    if (purchases.isEmpty) {
      _message('Record a purchase before creating a purchase return.');
      return;
    }

    int? invoiceId;
    List<_ReturnLine> lines = [];
    final notes = TextEditingController();
    final formKey = GlobalKey<FormState>();

    Future<void> loadItems(int? selectedInvoiceId) async {
      for (final line in lines) {
        line.dispose();
      }
      lines = [];
      if (selectedInvoiceId == null) return;
      final items = await db.query(
        'invoice_items',
        where: 'invoice_id = ?',
        whereArgs: [selectedInvoiceId],
        orderBy: 'id',
      );
      final returnedRows = await db.rawQuery('''
        SELECT ri.product_id, COALESCE(SUM(ri.quantity), 0) AS returned
        FROM invoices r
        JOIN invoice_items ri ON ri.invoice_id = r.id
        WHERE r.invoice_type = 'purchase_return'
          AND r.parent_invoice_id = ?
        GROUP BY ri.product_id
      ''', [selectedInvoiceId]);
      final returned = <int, double>{
        for (final row in returnedRows)
          row['product_id'] as int: (row['returned'] as num).toDouble(),
      };
      final purchased = <int, double>{};
      for (final item in items) {
        final id = item['product_id'] as int?;
        if (id != null) {
          purchased[id] = (purchased[id] ?? 0) +
              (item['quantity'] as num).toDouble();
        }
      }
      final remaining = <int, double>{
        for (final entry in purchased.entries)
          entry.key: entry.value - (returned[entry.key] ?? 0),
      };
      for (final item in items) {
        final id = item['product_id'] as int?;
        final lineRemaining = id == null ? 0.0 : (remaining[id] ?? 0);
        final available = lineRemaining.clamp(
          0.0,
          (item['quantity'] as num).toDouble(),
        ).toDouble();
        if (id != null) remaining[id] = lineRemaining - available;
        lines.add(_ReturnLine(item: item, available: available));
      }
    }

    final saved = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, refresh) => AlertDialog(
          title: const Text('Purchase return'),
          content: SizedBox(
            width: 560,
            child: Form(
              key: formKey,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    DropdownButtonFormField<int>(
                      initialValue: invoiceId,
                      decoration: const InputDecoration(
                        labelText: 'Original purchase invoice *',
                      ),
                      items: purchases.map((row) => DropdownMenuItem<int>(
                        value: row['id'] as int,
                        child: Text(
                          '${row['invoice_number']} • ${row['supplier_name'] ?? 'Supplier not selected'}',
                          overflow: TextOverflow.ellipsis,
                        ),
                      )).toList(),
                      validator: (value) =>
                          value == null ? 'Select the original purchase' : null,
                      onChanged: (value) async {
                        invoiceId = value;
                        await loadItems(value);
                        refresh(() {});
                      },
                    ),
                    const SizedBox(height: 12),
                    if (invoiceId != null && lines.isEmpty)
                      const Text('No items found in this purchase.'),
                    for (final line in lines)
                      Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        child: Padding(
                          padding: const EdgeInsets.all(10),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              CheckboxListTile(
                                contentPadding: EdgeInsets.zero,
                                value: line.selected,
                                title: Text(
                                  line.item['description']?.toString() ?? 'Product',
                                ),
                                subtitle: Text(
                                  'Purchased: ${line.item['quantity']} • Returnable: ${line.available.toStringAsFixed(3)}',
                                ),
                                onChanged: line.available <= 0
                                    ? null
                                    : (value) => refresh(
                                          () => line.selected = value ?? false,
                                        ),
                              ),
                              if (line.selected)
                                TextFormField(
                                  controller: line.quantity,
                                  decoration: const InputDecoration(
                                    labelText: 'Return quantity *',
                                  ),
                                  keyboardType: const TextInputType.numberWithOptions(
                                    decimal: true,
                                  ),
                                  validator: (value) {
                                    final parsed = double.tryParse(value ?? '');
                                    if (parsed == null ||
                                        !parsed.isFinite ||
                                        parsed <= 0) {
                                      return 'Enter a quantity greater than zero';
                                    }
                                    if (parsed > line.available) {
                                      return 'Exceeds remaining quantity';
                                    }
                                    return null;
                                  },
                                ),
                            ],
                          ),
                        ),
                      ),
                    TextFormField(
                      controller: notes,
                      decoration: const InputDecoration(labelText: 'Reason / notes'),
                      maxLines: 2,
                    ),
                  ],
                ),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                if (!(formKey.currentState?.validate() ?? false)) return;
                if (!lines.any((line) => line.selected)) {
                  _message('Select at least one item to return.');
                  return;
                }
                Navigator.pop(dialogContext, true);
              },
              child: const Text('Save return'),
            ),
          ],
        ),
      ),
    );

    if (saved == true && invoiceId != null) {
      try {
        await db.transaction((txn) async {
          final original = purchases.firstWhere((row) => row['id'] == invoiceId);
          final selectedLines = lines.where((line) => line.selected).toList();
          final returnItems = <Map<String, Object?>>[];
          final totalsByProduct = <int, double>{};
          double subtotal = 0;
          double taxTotal = 0;
          double cgstTotal = 0;
          double sgstTotal = 0;
          double igstTotal = 0;

          for (final line in selectedLines) {
            final item = line.item;
            final productId = item['product_id'] as int;
            final qty = double.parse(line.quantity.text.trim());
            final originalQty = (item['quantity'] as num).toDouble();
            final rate = (item['rate'] as num).toDouble();
            final gst = (item['gst_rate'] as num).toDouble();
            final discount = originalQty > 0
                ? ((item['discount'] as num?)?.toDouble() ?? 0) * qty / originalQty
                : 0.0;
            final base = qty * rate;
            final taxable = (base - discount).clamp(0.0, double.infinity).toDouble();
            final tax = originalQty > 0
                ? ((item['tax_amount'] as num?)?.toDouble() ?? 0) * qty / originalQty
                : 0.0;
            final cgst = originalQty > 0
                ? ((item['cgst_amount'] as num?)?.toDouble() ?? 0) * qty / originalQty
                : 0.0;
            final sgst = originalQty > 0
                ? ((item['sgst_amount'] as num?)?.toDouble() ?? 0) * qty / originalQty
                : 0.0;
            final igst = originalQty > 0
                ? ((item['igst_amount'] as num?)?.toDouble() ?? 0) * qty / originalQty
                : 0.0;
            if (!qty.isFinite || qty <= 0 || !taxable.isFinite ||
                !tax.isFinite || !cgst.isFinite || !sgst.isFinite || !igst.isFinite) {
              throw StateError('One or more return item values are invalid.');
            }
            totalsByProduct[productId] = (totalsByProduct[productId] ?? 0) + qty;
            subtotal += taxable;
            taxTotal += tax;
            cgstTotal += cgst;
            sgstTotal += sgst;
            igstTotal += igst;
            returnItems.add({
              'product_id': productId,
              'original_invoice_item_id': item['id'],
              'description': item['description'],
              'quantity': qty,
              'unit': item['unit'],
              'rate': rate,
              'discount': discount,
              'gst_rate': gst,
              'tax_amount': tax,
              'cgst_amount': cgst,
              'sgst_amount': sgst,
              'igst_amount': igst,
              'line_total': taxable + tax,
            });
          }

          for (final entry in totalsByProduct.entries) {
            final purchasedRows = await txn.rawQuery('''
              SELECT COALESCE(SUM(quantity), 0) AS total
              FROM invoice_items
              WHERE invoice_id = ? AND product_id = ?
            ''', [invoiceId, entry.key]);
            final returnedRows = await txn.rawQuery('''
              SELECT COALESCE(SUM(ri.quantity), 0) AS total
              FROM invoices r
              JOIN invoice_items ri ON ri.invoice_id = r.id
              WHERE r.invoice_type = 'purchase_return'
                AND r.parent_invoice_id = ? AND ri.product_id = ?
            ''', [invoiceId, entry.key]);
            final bought = (purchasedRows.first['total'] as num).toDouble();
            final already = (returnedRows.first['total'] as num).toDouble();
            if (entry.value <= 0 || already + entry.value > bought) {
              throw StateError('Return quantity exceeds the remaining purchase quantity.');
            }
            final stock = await txn.query(
              'products',
              columns: ['current_stock'],
              where: 'id = ?',
              whereArgs: [entry.key],
            );
            if (stock.isEmpty ||
                (stock.first['current_stock'] as num).toDouble() < entry.value) {
              throw StateError('Insufficient current stock for a returned item.');
            }
          }

          final now = DateTime.now();
          final returnNumber = 'PR-${now.microsecondsSinceEpoch}';
          final returnSyncId = AppDatabase.instance.createSyncId();
          final parentRows = await txn.query('invoices', columns: ['sync_id'], where: 'id = ?', whereArgs: [invoiceId], limit: 1);
          final parentSyncId = parentRows.isEmpty ? null : parentRows.first['sync_id'] as String?;
          if (parentSyncId == null || parentSyncId.isEmpty) throw StateError('Original purchase invoice is missing its cloud identifier.');
          final returnId = await txn.insert('invoices', {
            'sync_id': returnSyncId,
            'invoice_number': returnNumber,
            'invoice_type': 'purchase_return',
            'parent_invoice_id': invoiceId,
            'party_id': original['party_id'],
            'invoice_date': now.toIso8601String(),
            'subtotal': subtotal,
            'tax_total': taxTotal,
            'grand_total': subtotal + taxTotal,
            'amount_paid': 0,
            'cgst_total': cgstTotal,
            'sgst_total': sgstTotal,
            'igst_total': igstTotal,
            'status': 'recorded',
            'notes': 'Return against ${original['invoice_number']}. ${notes.text.trim()}'.trim(),
          });

          final syncedReturnItems = <Map<String, dynamic>>[];
          for (final item in returnItems) {
            final productId = item['product_id'] as int;
            final originalRows = await txn.query('invoice_items', columns: ['sync_id'], where: 'id = ?', whereArgs: [item['original_invoice_item_id']], limit: 1);
            final originalItemSyncId = originalRows.isEmpty ? null : originalRows.first['sync_id'] as String?;
            final productRows = await txn.query('products', columns: ['sync_id'], where: 'id = ?', whereArgs: [productId], limit: 1);
            final productSyncId = productRows.isEmpty ? null : productRows.first['sync_id'] as String?;
            if (originalItemSyncId == null || originalItemSyncId.isEmpty || productSyncId == null || productSyncId.isEmpty) {
              throw StateError('Purchase return is missing a linked cloud product or source item.');
            }
            final itemSyncId = AppDatabase.instance.createSyncId();
            final localItem = Map<String, Object?>.from(item)..['sync_id'] = itemSyncId;
            await txn.insert('invoice_items', {'invoice_id': returnId, ...localItem});
            final syncedItem = Map<String, dynamic>.from(localItem)
              ..remove('product_id')
              ..remove('original_invoice_item_id')
              ..['product_sync_id'] = productSyncId
              ..['original_invoice_item_sync_id'] = originalItemSyncId;
            syncedReturnItems.add(syncedItem);
            final qty = (item['quantity'] as num).toDouble();
            await InventoryCostService.removePurchaseReturnAtSource(
              txn,
              productId: productId,
              purchaseInvoiceId: invoiceId!,
              purchaseInvoiceItemId: item['original_invoice_item_id'] as int,
              quantity: qty,
            );
            await txn.rawUpdate(
              'UPDATE products SET current_stock = current_stock - ?, updated_at = ? WHERE id = ?',
              [qty, now.toIso8601String(), productId],
            );
            final movementId = await txn.insert('stock_movements', {
              'sync_id': AppDatabase.instance.createSyncId(),
              'product_id': productId,
              'movement_type': 'purchase_return',
              'quantity_change': -qty,
              'reference': returnNumber,
              'notes': 'Against ${original['invoice_number']}. ${notes.text.trim()}'.trim(),
              'created_at': now.toIso8601String(),
            });
            await AppDatabase.instance.enqueueProductSyncById(txn, productId);
            await AppDatabase.instance.enqueueStockMovementSync(txn, movementId);
          }
          await AccountingService.postPurchaseReturn(
            txn,
            returnId: returnId,
            returnNumber: returnNumber,
            date: now.toIso8601String(),
            subtotal: subtotal,
            tax: taxTotal,
            total: subtotal + taxTotal,
          );
          final returnRows = await txn.query('invoices', where: 'id = ?', whereArgs: [returnId], limit: 1);
          final supplierId = original['party_id'] as int?;
          final supplierRows = supplierId == null ? <Map<String, Object?>>[] : await txn.query('parties', columns: ['sync_id'], where: 'id = ?', whereArgs: [supplierId], limit: 1);
          final supplierSyncId = supplierRows.isEmpty ? null : supplierRows.first['sync_id'] as String?;
          final invoicePayload = Map<String, dynamic>.from(returnRows.single)
            ..remove('id')
            ..remove('party_id')
            ..remove('parent_invoice_id')
            ..['party_sync_id'] = supplierSyncId
            ..['parent_invoice_sync_id'] = parentSyncId
            ..['items'] = syncedReturnItems;
          await AppDatabase.instance.enqueueSyncOperation(
            executor: txn,
            tableName: 'invoices',
            recordId: returnSyncId,
            operation: 'insert',
            payload: invoicePayload,
          );
        });
        await _syncIfConfigured();
        _message('Purchase return saved and stock reduced for all selected items.');
        await _loadMovements();
      } catch (error) {
        _message('Could not save purchase return: $error');
      }
    }

    for (final line in lines) {
      line.dispose();
    }
    notes.dispose();
  }


  Future<void> _showReturnDetails(Map<String, Object?> invoice) async {
    final db = await AppDatabase.instance.database;
    final items = await db.query(
      'invoice_items',
      where: 'invoice_id = ?',
      whereArgs: [invoice['id']],
      orderBy: 'id',
    );
    final settingsRows = await db.query('app_settings');
    final business = <String, String>{
      for (final row in settingsRows)
        row['setting_key'] as String: row['setting_value'] as String,
    };
    if (!mounted) return;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(invoice['invoice_number']?.toString() ?? 'Purchase return'),
        content: SizedBox(
          width: 480,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Supplier: ${invoice['party_name'] ?? 'Supplier not selected'}'),
                Text('Original purchase: ${invoice['original_invoice_number'] ?? 'Not available'}'),
                Text('Date: ${(invoice['invoice_date'] as String).split('T').first}'),
                const Divider(),
                for (final item in items)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(item['description']?.toString() ?? ''),
                    subtitle: Text(
                      '${item['quantity']} ${item['unit']} × ₹${item['rate']}  |  GST ${item['gst_rate']}%',
                    ),
                    trailing: Text(
                      '₹${((item['line_total'] as num?)?.toDouble() ?? 0).toStringAsFixed(2)}',
                    ),
                  ),
                const Divider(),
                _returnTotalRow(
                  'Taxable subtotal',
                  (invoice['subtotal'] as num?)?.toDouble() ?? 0,
                ),
                _returnTotalRow(
                  'GST',
                  (invoice['tax_total'] as num?)?.toDouble() ?? 0,
                ),
                _returnTotalRow(
                  'Return total',
                  (invoice['grand_total'] as num?)?.toDouble() ?? 0,
                  bold: true,
                ),
                if ((invoice['notes']?.toString() ?? '').trim().isNotEmpty)
                  Text('Reason / notes: ${invoice['notes']}'),
              ],
            ),
          ),
        ),
        actions: [
          TextButton.icon(
            onPressed: () async {
              try {
                await InvoicePdfService.printInvoice(
                  invoice: invoice,
                  items: items,
                  business: business,
                  isPurchaseReturn: true,
                );
              } catch (error) {
                _message('Could not create purchase return PDF: $error');
              }
            },
            icon: const Icon(Icons.picture_as_pdf),
            label: const Text('PDF / Print'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Widget _returnTotalRow(String label, double amount, {bool bold = false}) {
    final style = TextStyle(
      fontWeight: bold ? FontWeight.bold : FontWeight.normal,
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: style),
          Text('₹${amount.toStringAsFixed(2)}', style: style),
        ],
      ),
    );
  }

  Future<void> _adjustStock() async {
    final db = await AppDatabase.instance.database;
    final products = await db.query(
      'products',
      where: 'is_service = 0 OR is_service IS NULL',
      orderBy: 'name COLLATE NOCASE',
    );
    if (!mounted) return;
    if (products.isEmpty) {
      _message('Add a stock product before adjusting inventory.');
      return;
    }

    int? productId;
    String direction = 'increase';
    final quantity = TextEditingController();
    final reason = TextEditingController();
    final formKey = GlobalKey<FormState>();

    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, refresh) => AlertDialog(
          title: const Text('Stock adjustment'),
          content: SizedBox(
            width: 440,
            child: Form(
              key: formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButtonFormField<int>(
                    initialValue: productId,
                    decoration: const InputDecoration(labelText: 'Product *'),
                    items: products.map((row) => DropdownMenuItem<int>(
                      value: row['id'] as int,
                      child: Text('${row['name']} • Stock: ${row['current_stock']} ${row['unit']}'),
                    )).toList(),
                    validator: (value) => value == null ? 'Select a product' : null,
                    onChanged: (value) => refresh(() => productId = value),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: direction,
                    decoration: const InputDecoration(labelText: 'Adjustment type'),
                    items: const [
                      DropdownMenuItem(value: 'increase', child: Text('Increase stock')),
                      DropdownMenuItem(value: 'decrease', child: Text('Decrease stock')),
                    ],
                    onChanged: (value) => refresh(() => direction = value ?? 'increase'),
                  ),
                  TextFormField(
                    controller: quantity,
                    decoration: const InputDecoration(labelText: 'Quantity *'),
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    validator: (value) {
                      final parsed = double.tryParse(value ?? '');
                      if (parsed == null || !parsed.isFinite || parsed <= 0) {
                        return 'Enter a quantity greater than zero';
                      }
                      if (direction == 'decrease' && productId != null) {
                        final selectedProduct = products.firstWhere(
                          (row) => row['id'] == productId,
                        );
                        if (parsed > (selectedProduct['current_stock'] as num).toDouble()) {
                          return 'Cannot reduce stock below zero';
                        }
                      }
                      return null;
                    },
                  ),
                  TextFormField(
                    controller: reason,
                    decoration: const InputDecoration(labelText: 'Reason *'),
                    validator: (value) => value == null || value.trim().isEmpty ? 'Enter a reason' : null,
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancel')),
            FilledButton(
              onPressed: () {
                if (formKey.currentState?.validate() ?? false) Navigator.pop(dialogContext, true);
              },
              child: const Text('Save adjustment'),
            ),
          ],
        ),
      ),
    );

    if (saved == true && productId != null) {
      try {
        await db.transaction((txn) async {
          final qty = double.parse(quantity.text.trim());
          final signedQty = direction == 'increase' ? qty : -qty;
          final current = await txn.query(
            'products',
            columns: ['current_stock'],
            where: 'id = ?',
            whereArgs: [productId],
          );
          if (current.isEmpty ||
              (current.first['current_stock'] as num).toDouble() + signedQty < 0) {
            throw StateError('Stock cannot become negative.');
          }
          final now = DateTime.now();
          double adjustmentCost;
          if (signedQty > 0) {
            final selected = products.firstWhere((row) => row['id'] == productId);
            adjustmentCost = qty *
                (selected['purchase_price'] as num).toDouble();
            await InventoryCostService.addAdjustmentLayer(
              txn,
              productId: productId!,
              quantity: signedQty,
              adjustedAt: now.toIso8601String(),
            );
          } else {
            adjustmentCost = await InventoryCostService.removeStockAtFifo(
              txn,
              productId: productId!,
              quantity: -signedQty,
              removedAt: now.toIso8601String(),
            );
          }
          await txn.rawUpdate(
            'UPDATE products SET current_stock = current_stock + ?, updated_at = ? WHERE id = ?',
            [signedQty, now.toIso8601String(), productId],
          );
          final movementId = await txn.insert('stock_movements', {
            'sync_id': AppDatabase.instance.createSyncId(),
            'product_id': productId,
            'movement_type': 'adjustment',
            'quantity_change': signedQty,
            'reference': 'ADJ-${now.microsecondsSinceEpoch}',
            'notes': reason.text.trim(),
            'created_at': now.toIso8601String(),
          });
          await AppDatabase.instance.enqueueProductSyncById(txn, productId!);
          await AppDatabase.instance.enqueueStockMovementSync(txn, movementId);
          await AccountingService.postStockAdjustment(
            txn,
            movementId: movementId,
            date: now.toIso8601String(),
            reason: reason.text.trim(),
            quantityChange: signedQty,
            inventoryCost: adjustmentCost,
          );
        });
        await _syncIfConfigured();
        _message('Stock adjusted successfully.');
        await _loadMovements();
      } catch (error) {
        _message('Could not adjust stock: $error');
      }
    }

    quantity.dispose();
    reason.dispose();
  }

  void _message(String value) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(value)));
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Purchase Returns & Stock Control')),
    body: _loading
        ? const Center(child: CircularProgressIndicator())
        : RefreshIndicator(
            onRefresh: _loadMovements,
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    FilledButton.icon(
                      onPressed: _purchaseReturn,
                      icon: const Icon(Icons.assignment_return),
                      label: const Text('Purchase return'),
                    ),
                    OutlinedButton.icon(
                      onPressed: _adjustStock,
                      icon: const Icon(Icons.tune),
                      label: const Text('Stock adjustment'),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                Text('Purchase return history', style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 8),
                if (_returns.isEmpty)
                  const Card(
                    child: Padding(
                      padding: EdgeInsets.all(16),
                      child: Text('No purchase returns recorded yet.'),
                    ),
                  )
                else
                  for (final invoice in _returns)
                    Card(
                      child: ListTile(
                        leading: const CircleAvatar(
                          child: Icon(Icons.assignment_return),
                        ),
                        title: Text(invoice['invoice_number']?.toString() ?? ''),
                        subtitle: Text(
                          '${invoice['party_name'] ?? 'Supplier not selected'} • Original: ${invoice['original_invoice_number'] ?? 'N/A'} • ${(invoice['invoice_date'] as String).split('T').first}',
                        ),
                        trailing: Text(
                          '₹${((invoice['grand_total'] as num?)?.toDouble() ?? 0).toStringAsFixed(2)}',
                        ),
                        onTap: () => _showReturnDetails(invoice),
                      ),
                    ),
                const SizedBox(height: 20),
                Text('Recent stock movements', style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 8),
                if (_movements.isEmpty)
                  const Card(child: Padding(
                    padding: EdgeInsets.all(16),
                    child: Text('No stock adjustments or purchase returns recorded yet.'),
                  ))
                else
                  for (final row in _movements)
                    Card(
                      child: ListTile(
                        leading: Icon(
                          (row['quantity_change'] as num).toDouble() < 0
                              ? Icons.south_west
                              : Icons.north_east,
                        ),
                        title: Text(row['product_name'] as String),
                        subtitle: Text(
                          '${row['movement_type']} • ${row['reference'] ?? ''} • ${row['notes'] ?? ''}',
                        ),
                        trailing: Text(
                          '${(row['quantity_change'] as num).toDouble() > 0 ? '+' : ''}${row['quantity_change']} ${row['unit']}',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
              ],
            ),
          ),
  );
}
