import 'package:flutter/material.dart';

import '../../data/local/app_database.dart';

class StockControlPage extends StatefulWidget {
  const StockControlPage({super.key});

  @override
  State<StockControlPage> createState() => _StockControlPageState();
}

class _StockControlPageState extends State<StockControlPage> {
  List<Map<String, Object?>> _movements = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadMovements();
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
    if (!mounted) return;
    setState(() {
      _movements = rows;
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
    int? itemId;
    double availableQuantity = 0;
    final quantity = TextEditingController(text: '1');
    final notes = TextEditingController();
    final formKey = GlobalKey<FormState>();
    List<Map<String, Object?>> invoiceItems = [];

    final saved = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, refresh) => AlertDialog(
          title: const Text('Purchase return'),
          content: SizedBox(
            width: 480,
            child: Form(
              key: formKey,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    DropdownButtonFormField<int>(
                      initialValue: invoiceId,
                      decoration: const InputDecoration(labelText: 'Original purchase invoice *'),
                      items: purchases.map((row) => DropdownMenuItem<int>(
                        value: row['id'] as int,
                        child: Text('${row['invoice_number']} • ${row['supplier_name'] ?? 'Supplier not selected'}'),
                      )).toList(),
                      validator: (value) => value == null ? 'Select the original purchase' : null,
                      onChanged: (value) async {
                        invoiceId = value;
                        itemId = null;
                        invoiceItems = await db.query(
                          'invoice_items',
                          where: 'invoice_id = ?',
                          whereArgs: [value],
                          orderBy: 'id',
                        );
                        refresh(() {});
                      },
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<int>(
                      key: ValueKey(invoiceId),
                      initialValue: itemId,
                      decoration: const InputDecoration(labelText: 'Product to return *'),
                      items: invoiceItems.map((row) => DropdownMenuItem<int>(
                        value: row['id'] as int,
                        child: Text('${row['description']} • Qty ${row['quantity']}'),
                      )).toList(),
                      validator: (value) => value == null ? 'Select a purchase item' : null,
                      onChanged: (value) async {
                        itemId = value;
                        availableQuantity = 0;
                        if (invoiceId != null && value != null) {
                          final selected = invoiceItems.firstWhere((row) => row['id'] == value);
                          final previous = await db.rawQuery('''
                            SELECT COALESCE(SUM(ri.quantity), 0) AS returned
                            FROM invoices r
                            JOIN invoice_items ri ON ri.invoice_id = r.id
                            WHERE r.invoice_type = 'purchase_return'
                              AND r.parent_invoice_id = ?
                              AND ri.product_id = ?
                          ''', [invoiceId, selected['product_id']]);
                          availableQuantity = (selected['quantity'] as num).toDouble() -
                              ((previous.first['returned'] as num).toDouble());
                        }
                        refresh(() {});
                      },
                    ),
                    if (itemId != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text('Returnable quantity: ${availableQuantity.toStringAsFixed(3)}'),
                      ),
                    TextFormField(
                      controller: quantity,
                      decoration: const InputDecoration(labelText: 'Return quantity *'),
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      validator: (value) {
                        final parsed = double.tryParse(value ?? '');
                        if (parsed == null || !parsed.isFinite || parsed <= 0) {
                          return 'Enter a quantity greater than zero';
                        }
                        if (parsed > availableQuantity) return 'Exceeds returnable quantity';
                        return null;
                      },
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
            TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancel')),
            FilledButton(
              onPressed: () {
                if (formKey.currentState?.validate() ?? false) {
                  Navigator.pop(dialogContext, true);
                }
              },
              child: const Text('Save return'),
            ),
          ],
        ),
      ),
    );

    if (saved == true && invoiceId != null && itemId != null) {
      try {
        await db.transaction((txn) async {
          final original = purchases.firstWhere((row) => row['id'] == invoiceId);
          final originalItem = invoiceItems.firstWhere((row) => row['id'] == itemId);
          final returnQty = double.parse(quantity.text.trim());
          final previous = await txn.rawQuery('''
            SELECT COALESCE(SUM(ri.quantity), 0) AS returned
            FROM invoices r
            JOIN invoice_items ri ON ri.invoice_id = r.id
            WHERE r.invoice_type = 'purchase_return'
              AND r.parent_invoice_id = ?
              AND ri.product_id = ?
          ''', [invoiceId, originalItem['product_id']]);
          final alreadyReturned = (previous.first['returned'] as num).toDouble();
          final purchasedQty = (originalItem['quantity'] as num).toDouble();
          if (returnQty <= 0 || alreadyReturned + returnQty > purchasedQty) {
            throw StateError('Return quantity exceeds the remaining quantity on this purchase.');
          }
          final stockRows = await txn.query(
            'products',
            columns: ['current_stock'],
            where: 'id = ?',
            whereArgs: [originalItem['product_id']],
          );
          if (stockRows.isEmpty ||
              (stockRows.first['current_stock'] as num).toDouble() < returnQty) {
            throw StateError('Insufficient current stock to process this return.');
          }
          final rate = (originalItem['rate'] as num).toDouble();
          final gstRate = (originalItem['gst_rate'] as num).toDouble();
          final base = returnQty * rate;
          final tax = base * gstRate / 100;
          final now = DateTime.now();
          final returnNumber = 'PR-${now.microsecondsSinceEpoch}';
          final returnInvoiceId = await txn.insert('invoices', {
            'invoice_number': returnNumber,
            'invoice_type': 'purchase_return',
            'parent_invoice_id': invoiceId,
            'party_id': original['party_id'],
            'invoice_date': now.toIso8601String(),
            'subtotal': base,
            'tax_total': tax,
            'grand_total': base + tax,
            'amount_paid': 0,
            'status': 'recorded',
            'notes': 'Return against ${original['invoice_number']}. ${notes.text.trim()}'.trim(),
          });
          await txn.insert('invoice_items', {
            'invoice_id': returnInvoiceId,
            'product_id': originalItem['product_id'],
            'description': originalItem['description'],
            'quantity': returnQty,
            'unit': originalItem['unit'],
            'rate': rate,
            'discount': 0,
            'gst_rate': gstRate,
            'tax_amount': tax,
            'line_total': base + tax,
          });
          await txn.rawUpdate(
            'UPDATE products SET current_stock = current_stock - ?, updated_at = ? WHERE id = ?',
            [returnQty, now.toIso8601String(), originalItem['product_id']],
          );
          await txn.insert('stock_movements', {
            'product_id': originalItem['product_id'],
            'movement_type': 'purchase_return',
            'quantity_change': -returnQty,
            'reference': returnNumber,
            'notes': 'Against ${original['invoice_number']}. ${notes.text.trim()}'.trim(),
            'created_at': now.toIso8601String(),
          });
        });
        _message('Purchase return saved and stock reduced.');
        await _loadMovements();
      } catch (error) {
        _message('Could not save purchase return: $error');
      }
    }

    quantity.dispose();
    notes.dispose();
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
                        final selected = products.firstWhere((row) => row['id'] == productId);
                        if (parsed > (selected['current_stock'] as num).toDouble()) {
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
          final selected = products.firstWhere((row) => row['id'] == productId);
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
          await txn.rawUpdate(
            'UPDATE products SET current_stock = current_stock + ?, updated_at = ? WHERE id = ?',
            [signedQty, now.toIso8601String(), productId],
          );
          await txn.insert('stock_movements', {
            'product_id': productId,
            'movement_type': 'adjustment',
            'quantity_change': signedQty,
            'reference': 'ADJ-${now.microsecondsSinceEpoch}',
            'notes': reason.text.trim(),
            'created_at': now.toIso8601String(),
          });
        });
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
