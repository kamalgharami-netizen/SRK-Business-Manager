import 'package:flutter/material.dart';

import '../../data/local/accounting_service.dart';
import '../../data/local/app_database.dart';
import '../../data/local/inventory_cost_service.dart';
import '../../data/sync/business_sync_service.dart';

class SalesReturnsPage extends StatefulWidget {
  const SalesReturnsPage({super.key});

  @override
  State<SalesReturnsPage> createState() => _SalesReturnsPageState();
}

class _SalesReturnsPageState extends State<SalesReturnsPage> {
  List<Map<String, Object?>> _invoices = [];
  List<Map<String, Object?>> _returns = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
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

  Future<void> _load() async {
    final db = await AppDatabase.instance.database;
    final invoices = await db.rawQuery("""
      SELECT i.*, p.name AS party_name
      FROM invoices i
      LEFT JOIN parties p ON p.id = i.party_id
      WHERE i.invoice_type = 'sale'
      ORDER BY i.id DESC
    """);
    final returns = await db.rawQuery("""
      SELECT r.*, p.name AS party_name, o.invoice_number AS original_number
      FROM invoices r
      LEFT JOIN parties p ON p.id = r.party_id
      LEFT JOIN invoices o ON o.id = r.parent_invoice_id
      WHERE r.invoice_type = 'sales_return'
      ORDER BY r.id DESC
    """);
    if (!mounted) return;
    setState(() {
      _invoices = invoices;
      _returns = returns;
      _loading = false;
    });
  }

  Future<void> _startReturn(Map<String, Object?> invoice) async {
    final db = await AppDatabase.instance.database;
    final originalItems = await db.query(
      'invoice_items',
      where: 'invoice_id = ?',
      whereArgs: [invoice['id']],
      orderBy: 'id ASC',
    );
    if (originalItems.isEmpty) {
      _message('This invoice has no returnable items.');
      return;
    }

    final lines = <_SalesReturnLine>[];
    for (final item in originalItems) {
      final returned = await db.rawQuery("""
        SELECT COALESCE(SUM(ri.quantity), 0) AS qty
        FROM invoice_items ri
        INNER JOIN invoices r ON r.id = ri.invoice_id
        WHERE r.invoice_type = 'sales_return'
          AND r.parent_invoice_id = ?
          AND ri.original_invoice_item_id = ?
      """, [invoice['id'], item['id']]);
      final alreadyReturned = (returned.first['qty'] as num?)?.toDouble() ?? 0;
      final originalQty = (item['quantity'] as num).toDouble();
      final remaining = originalQty - alreadyReturned;
      if (remaining > 0.0000001 && item['product_id'] != null) {
        lines.add(_SalesReturnLine(item: item, remaining: remaining));
      }
    }
    if (lines.isEmpty) {
      _message('All quantities on this invoice have already been returned.');
      return;
    }

    if (!mounted) {
      for (final line in lines) { line.dispose(); }
      return;
    }
    final formKey = GlobalKey<FormState>();
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: Text('Return items • ${invoice['invoice_number']}'),
        content: SizedBox(
          width: 560,
          child: Form(
            key: formKey,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('Customer: ${invoice['party_name'] ?? 'Walk-in customer'}'),
                  const SizedBox(height: 12),
                  for (final line in lines)
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(10),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(line.item['description']?.toString() ?? 'Item',
                                style: const TextStyle(fontWeight: FontWeight.bold)),
                            Text('Returnable: ${line.remaining} ${line.item['unit'] ?? ''}'),
                            TextFormField(
                              controller: line.quantity,
                              decoration: const InputDecoration(labelText: 'Return quantity'),
                              keyboardType: const TextInputType.numberWithOptions(decimal: true),
                              validator: (value) {
                                final qty = double.tryParse(value ?? '');
                                if (qty == null || !qty.isFinite || qty <= 0) return 'Enter a quantity greater than zero';
                                if (qty > line.remaining + 0.0000001) return 'Cannot exceed returnable quantity';
                                return null;
                              },
                            ),
                          ],
                        ),
                      ),
                    ),
                  const Text('Returned goods will be added back to stock. The customer balance will be credited; cash refund is not processed by this screen.',
                      style: TextStyle(fontSize: 12)),
                ],
              ),
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancel')),
          FilledButton(
            onPressed: () {
              if (formKey.currentState?.validate() ?? false) {
                Navigator.pop(dialogContext, true);
              }
            },
            child: const Text('Create sales return'),
          ),
        ],
      ),
    );

    if (confirmed != true) {
      for (final line in lines) { line.dispose(); }
      return;
    }

    try {
      await db.transaction((txn) async {
        final now = DateTime.now();
        final number = 'SR-${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}-${now.microsecondsSinceEpoch.toString().substring(8)}';
        var subtotal = 0.0;
        var taxTotal = 0.0;
        var total = 0.0;
        final prepared = <Map<String, Object?>>[];

        final currentInvoice = await txn.query(
          'invoices',
          columns: ['id', 'invoice_type'],
          where: 'id = ?',
          whereArgs: [invoice['id']],
          limit: 1,
        );
        if (currentInvoice.isEmpty || currentInvoice.first['invoice_type'] != 'sale') {
          throw StateError('The original sales invoice is no longer available.');
        }

        for (final line in lines) {
          final qty = double.tryParse(line.quantity.text.trim());
          if (qty == null || !qty.isFinite || qty <= 0) {
            throw StateError('Return quantity must be a finite number greater than zero.');
          }
          final originalQty = (line.item['quantity'] as num).toDouble();
          final priorRows = await txn.rawQuery(
            """
            SELECT COALESCE(SUM(ri.quantity), 0) AS qty
            FROM invoice_items ri
            INNER JOIN invoices r ON r.id = ri.invoice_id
            WHERE r.invoice_type = 'sales_return'
              AND r.parent_invoice_id = ?
              AND ri.original_invoice_item_id = ?
            """,
            [invoice['id'], line.item['id']],
          );
          final alreadyReturned = (priorRows.first['qty'] as num?)?.toDouble() ?? 0;
          if (!originalQty.isFinite || originalQty <= 0 ||
              !alreadyReturned.isFinite || alreadyReturned < 0 ||
              alreadyReturned + qty > originalQty + 0.0000001) {
            throw StateError('Return quantity exceeds the remaining quantity on the original invoice.');
          }
          final originalDiscount = (line.item['discount'] as num?)?.toDouble() ?? 0;
          final rate = (line.item['rate'] as num).toDouble();
          final originalTax = (line.item['tax_amount'] as num?)?.toDouble() ?? 0;
          if (!rate.isFinite || rate < 0 || !originalDiscount.isFinite ||
              originalDiscount < 0 || !originalTax.isFinite || originalTax < 0) {
            throw StateError('Original invoice item contains invalid amount values.');
          }
          final base = qty * rate;
          if (!base.isFinite) {
            throw StateError('Return amount is too large.');
          }
          final discount = originalQty > 0 ? originalDiscount * qty / originalQty : 0.0;
          final taxable = (base - discount).clamp(0.0, double.infinity).toDouble();
          final tax = originalQty > 0 ? originalTax * qty / originalQty : 0.0;
          final cgst = originalQty > 0 ? ((line.item['cgst_amount'] as num?)?.toDouble() ?? 0) * qty / originalQty : 0.0;
          final sgst = originalQty > 0 ? ((line.item['sgst_amount'] as num?)?.toDouble() ?? 0) * qty / originalQty : 0.0;
          final igst = originalQty > 0 ? ((line.item['igst_amount'] as num?)?.toDouble() ?? 0) * qty / originalQty : 0.0;
          subtotal += taxable;
          taxTotal += tax;
          total += taxable + tax;
          prepared.add({
            'original_invoice_item_id': line.item['id'],
            'product_id': line.item['product_id'],
            'description': line.item['description'],
            'quantity': qty,
            'unit': line.item['unit'],
            'rate': line.item['rate'],
            'discount': discount,
            'gst_rate': line.item['gst_rate'],
            'tax_amount': tax,
            'hsn_sac': line.item['hsn_sac'],
            'cgst_amount': cgst,
            'sgst_amount': sgst,
            'igst_amount': igst,
            'line_total': taxable + tax,
          });
        }

        final returnSyncId = AppDatabase.instance.createSyncId();
        final originalInvoiceSyncId = invoice['sync_id'] as String?;
        if (originalInvoiceSyncId == null || originalInvoiceSyncId.isEmpty) throw StateError('Original sales invoice is missing its cloud identifier.');
        final returnId = await txn.insert('invoices', {
          'sync_id': returnSyncId,
          'invoice_number': number,
          'invoice_type': 'sales_return',
          'party_id': invoice['party_id'],
          'invoice_date': now.toIso8601String(),
          'subtotal': subtotal,
          'tax_total': taxTotal,
          'grand_total': total,
          'amount_paid': 0,
          'status': 'credit_note',
          'notes': 'Return against invoice ${invoice['invoice_number']}',
          'parent_invoice_id': invoice['id'],
          'place_of_supply': invoice['place_of_supply'],
          'tax_type': invoice['tax_type'],
          'cgst_total': prepared.fold<double>(0, (s, x) => s + (x['cgst_amount'] as num).toDouble()),
          'sgst_total': prepared.fold<double>(0, (s, x) => s + (x['sgst_amount'] as num).toDouble()),
          'igst_total': prepared.fold<double>(0, (s, x) => s + (x['igst_amount'] as num).toDouble()),
        });

        var restoredCost = 0.0;
        final syncedReturnItems = <Map<String, dynamic>>[];
        for (final item in prepared) {
          final returnItemData = Map<String, Object?>.from(item);
          final originalItemId = returnItemData['original_invoice_item_id'] as int;
          final originalItemRows = await txn.query('invoice_items', columns: ['sync_id'], where: 'id = ?', whereArgs: [originalItemId], limit: 1);
          final originalItemSyncId = originalItemRows.isEmpty ? null : originalItemRows.first['sync_id'] as String?;
          if (originalItemSyncId == null || originalItemSyncId.isEmpty) throw StateError('Original sales invoice line is missing its cloud identifier.');
          final productId = item['product_id'] as int;
          final productRows = await txn.query('products', columns: ['sync_id'], where: 'id = ?', whereArgs: [productId], limit: 1);
          final productSyncId = productRows.isEmpty ? null : productRows.first['sync_id'] as String?;
          if (productSyncId == null || productSyncId.isEmpty) throw StateError('Returned product is missing its cloud identifier.');
          final returnItemSyncId = AppDatabase.instance.createSyncId();
          returnItemData.remove('original_invoice_item_id');
          final returnItemId = await txn.insert('invoice_items', {'sync_id': returnItemSyncId, 'invoice_id': returnId, 'original_invoice_item_id': originalItemId, ...returnItemData});
          final syncedItem = Map<String, dynamic>.from(returnItemData)..remove('product_id')..['sync_id'] = returnItemSyncId..['product_sync_id'] = productSyncId..['original_invoice_item_sync_id'] = originalItemSyncId;
          syncedReturnItems.add(syncedItem);
          restoredCost += await InventoryCostService.restoreSalesReturn(
            txn,
            returnItemId: returnItemId,
            originalInvoiceItemId: originalItemId,
            productId: productId,
            quantity: (item['quantity'] as num).toDouble(),
            returnedAt: now.toIso8601String(),
          );
          await txn.rawUpdate(
            'UPDATE products SET current_stock = current_stock + ?, updated_at = ? WHERE id = ?',
            [item['quantity'], now.toIso8601String(), productId],
          );
          final movementId = await txn.insert('stock_movements', {
            'sync_id': AppDatabase.instance.createSyncId(),
            'product_id': productId,
            'movement_type': 'sales_return',
            'quantity_change': item['quantity'],
            'reference': number,
            'notes': 'Return against invoice ${invoice['invoice_number']}',
            'created_at': now.toIso8601String(),
          });
          await AppDatabase.instance.enqueueProductSyncById(txn, productId);
          await AppDatabase.instance.enqueueStockMovementSync(txn, movementId);
        }
        await AccountingService.postSalesReturn(
          txn,
          returnId: returnId,
          returnNumber: number,
          date: now.toIso8601String(),
          subtotal: subtotal,
          tax: taxTotal,
          total: total,
          costOfGoodsReturned: restoredCost,
        );
        final returnRows = await txn.query('invoices', where: 'id = ?', whereArgs: [returnId], limit: 1);
        final partyId = invoice['party_id'] as int?;
        final partyRows = partyId == null ? <Map<String, Object?>>[] : await txn.query('parties', columns: ['sync_id'], where: 'id = ?', whereArgs: [partyId], limit: 1);
        final returnPayload = Map<String, dynamic>.from(returnRows.single)..remove('id')..remove('party_id')..remove('parent_invoice_id')..['party_sync_id'] = partyRows.isEmpty ? null : partyRows.first['sync_id']..['parent_invoice_sync_id'] = originalInvoiceSyncId..['items'] = syncedReturnItems;
        await AppDatabase.instance.enqueueSyncOperation(executor: txn, tableName: 'invoices', recordId: returnSyncId, operation: 'insert', payload: returnPayload);
      });
      await _syncIfConfigured();
      _message('Sales return saved. Stock and accounting entries were updated.');
      await _load();
    } catch (error) {
      _message('Could not create sales return: $error');
    } finally {
      for (final line in lines) { line.dispose(); }
    }
  }

  void _message(String value) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(value)));
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Sales Returns')),
    body: _loading
        ? const Center(child: CircularProgressIndicator())
        : RefreshIndicator(
            onRefresh: _load,
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text('Original sales invoices', style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 8),
                if (_invoices.isEmpty)
                  const Card(child: Padding(padding: EdgeInsets.all(16), child: Text('No sales invoices found.')))
                else
                  for (final invoice in _invoices)
                    Card(
                      child: ListTile(
                        leading: const CircleAvatar(child: Icon(Icons.receipt_long)),
                        title: Text(invoice['invoice_number']?.toString() ?? ''),
                        subtitle: Text('${invoice['party_name'] ?? 'Walk-in customer'} • ${(invoice['invoice_date'] as String).split('T').first}'),
                        trailing: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text('₹${((invoice['grand_total'] as num?)?.toDouble() ?? 0).toStringAsFixed(2)}'),
                            const Text('Create return', style: TextStyle(fontSize: 11)),
                          ],
                        ),
                        onTap: () => _startReturn(invoice),
                      ),
                    ),
                const SizedBox(height: 20),
                Text('Sales return history', style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 8),
                if (_returns.isEmpty)
                  const Card(child: Padding(padding: EdgeInsets.all(16), child: Text('No sales returns recorded yet.')))
                else
                  for (final row in _returns)
                    Card(
                      child: ListTile(
                        leading: const Icon(Icons.assignment_return),
                        title: Text(row['invoice_number']?.toString() ?? ''),
                        subtitle: Text('Against ${row['original_number'] ?? 'N/A'} • ${row['party_name'] ?? 'Walk-in customer'}'),
                        trailing: Text('₹${((row['grand_total'] as num?)?.toDouble() ?? 0).toStringAsFixed(2)}'),
                      ),
                    ),
              ],
            ),
          ),
  );
}

class _SalesReturnLine {
  _SalesReturnLine({required this.item, required this.remaining})
      : quantity = TextEditingController(text: remaining.toString());
  final Map<String, Object?> item;
  final double remaining;
  final TextEditingController quantity;
  void dispose() => quantity.dispose();
}
