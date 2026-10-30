import 'package:flutter/material.dart';

import '../../data/local/app_database.dart';
import '../../data/indian_states.dart';
import '../invoices/invoice_pdf_service.dart';

class PurchasesPage extends StatefulWidget {
  const PurchasesPage({super.key});

  @override
  State<PurchasesPage> createState() => _PurchasesPageState();
}

class _PurchasesPageState extends State<PurchasesPage> {
  List<Map<String, Object?>> _rows = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final db = await AppDatabase.instance.database;
    final rows = await db.rawQuery('''
      SELECT invoices.*, parties.name AS party_name,
             parties.gstin AS party_gstin, parties.state AS party_state
      FROM invoices
      LEFT JOIN parties ON parties.id = invoices.party_id
      WHERE invoices.invoice_type = 'purchase'
      ORDER BY invoices.id DESC
    ''');
    if (!mounted) return;
    setState(() {
      _rows = rows;
      _loading = false;
    });
  }

  Future<void> _add() async {
    final db = await AppDatabase.instance.database;
    final suppliers = await db.query(
      'parties',
      where: "party_type IN ('supplier', 'both')",
      orderBy: 'name COLLATE NOCASE',
    );
    final products = await db.query(
      'products',
      where: 'is_service = 0 OR is_service IS NULL',
      orderBy: 'name COLLATE NOCASE',
    );
    if (!mounted) return;
    if (products.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Add stock products before recording a purchase.')),
      );
      return;
    }

    final settingsRows = await db.query('app_settings');
    if (!mounted) return;
    final settings = <String, String>{
      for (final row in settingsRows)
        row['setting_key'] as String: row['setting_value'] as String,
    };
    final businessState = (settings['company_state'] ?? '').trim();
    if (businessState.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Set your GST registration state in Settings before recording a GST purchase.')),
      );
      return;
    }
    if (!IndianStates.all.contains(businessState)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Select a valid GST registration state in Settings.')),
      );
      return;
    }
    final placeOfSupply = TextEditingController(text: businessState);
    int? supplierId;
    final lines = <_PurchaseLine>[_PurchaseLine()];
    final notes = TextEditingController();
    final formKey = GlobalKey<FormState>();

    final saved = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, refreshDialog) {
          double subtotal = 0;
          double taxTotal = 0;
          for (final line in lines) {
            final quantity = double.tryParse(line.quantity.text) ?? 0;
            final rate = double.tryParse(line.rate.text) ?? 0;
            final gstRate = double.tryParse(line.gstRate.text) ?? 0;
            final base = quantity * rate;
            subtotal += base;
            taxTotal += base * gstRate / 100;
          }

          final isIntraState = placeOfSupply.text.trim().toLowerCase() == businessState.toLowerCase();
          final cgstTotal = isIntraState ? taxTotal / 2 : 0.0;
          final sgstTotal = isIntraState ? taxTotal - cgstTotal : 0.0;
          final igstTotal = isIntraState ? 0.0 : taxTotal;
          return AlertDialog(
            title: const Text('Record purchase'),
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
                        initialValue: supplierId,
                        decoration: const InputDecoration(labelText: 'Supplier (optional)'),
                        items: suppliers.map((supplier) => DropdownMenuItem<int>(
                          value: supplier['id'] as int,
                          child: Text(supplier['name'] as String),
                        )).toList(),
                        onChanged: (value) => refreshDialog(() => supplierId = value),
                      ),
                      if (supplierId != null) ...[
                        _partyTaxDetails(suppliers.firstWhere((supplier) => supplier['id'] == supplierId)),
                      ],
                      DropdownButtonFormField<String>(
                        initialValue: IndianStates.all.contains(placeOfSupply.text)
                            ? placeOfSupply.text
                            : null,
                        decoration: const InputDecoration(
                          labelText: 'Place of Supply state *',
                          helperText: 'Select the Place of Supply shown on supplier tax invoice.',
                        ),
                        items: IndianStates.all.map((state) => DropdownMenuItem<String>(
                          value: state,
                          child: Text(state),
                        )).toList(),
                        validator: (value) => value == null
                            ? 'Select Place of Supply state'
                            : null,
                        onChanged: (value) {
                          placeOfSupply.text = value ?? '';
                          refreshDialog(() {});
                        },
                      ),
                      const SizedBox(height: 16),
                      Text('Purchase items', style: Theme.of(dialogContext).textTheme.titleMedium),
                      const SizedBox(height: 8),
                      for (var index = 0; index < lines.length; index++)
                        _buildLine(
                          line: lines[index],
                          products: products,
                          onChanged: () => refreshDialog(() {}),
                          onRemove: lines.length == 1
                              ? null
                              : () {
                                  final removed = lines.removeAt(index);
                                  removed.dispose();
                                  refreshDialog(() {});
                                },
                        ),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton.icon(
                          onPressed: () => refreshDialog(() => lines.add(_PurchaseLine())),
                          icon: const Icon(Icons.add),
                          label: const Text('Add another item'),
                        ),
                      ),
                      TextFormField(
                        controller: notes,
                        decoration: const InputDecoration(labelText: 'Notes (optional)'),
                        maxLines: 2,
                      ),
                      const Divider(height: 24),
                      _totalRow('Taxable subtotal', subtotal),
                      _totalRow('Total GST', taxTotal),
                      if (isIntraState) ...[
                        _totalRow('CGST', cgstTotal),
                        _totalRow('SGST', sgstTotal),
                      ] else
                        _totalRow('IGST', igstTotal),
                      _totalRow('Grand total', subtotal + taxTotal, bold: true),
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
                  for (final line in lines) {
                    if (line.productId == null) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Select a product for every purchase item.')),
                      );
                      return;
                    }
                  }
                  Navigator.pop(dialogContext, true);
                },
                child: const Text('Save purchase'),
              ),
            ],
          );
        },
      ),
    );

    if (saved == true) {
      try {
        await db.transaction((txn) async {
          final now = DateTime.now();
          final invoiceNumber =
              'PUR-${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}-${now.microsecondsSinceEpoch.toString().substring(8)}';
          double subtotal = 0;
          double taxTotal = 0;
          final preparedItems = <Map<String, Object?>>[];

          for (final line in lines) {
            final product = products.firstWhere((item) => item['id'] == line.productId);
            final quantity = double.parse(line.quantity.text.trim());
            final rate = double.parse(line.rate.text.trim());
            final gstRate = double.parse(line.gstRate.text.trim());
            if (!quantity.isFinite || quantity <= 0 ||
                !rate.isFinite || rate < 0 ||
                !gstRate.isFinite || gstRate < 0 || gstRate > 100) {
              throw StateError('One or more purchase item values are invalid.');
            }
            final base = quantity * rate;
            final tax = base * gstRate / 100;
            final isIntraState = placeOfSupply.text.trim().toLowerCase() == businessState.toLowerCase();
            final cgst = isIntraState ? tax / 2 : 0.0;
            final sgst = isIntraState ? tax - cgst : 0.0;
            final igst = isIntraState ? 0.0 : tax;
            if (!base.isFinite || !tax.isFinite) {
              throw StateError('Purchase amount is too large.');
            }
            subtotal += base;
            taxTotal += tax;
            preparedItems.add({
              'product_id': line.productId,
              'description': product['name'] as String,
              'hsn_sac': product['hsn_sac'],
              'quantity': quantity,
              'unit': product['unit'] as String? ?? 'pcs',
              'rate': rate,
              'discount': 0,
              'gst_rate': gstRate,
              'tax_amount': tax,
              'cgst_amount': cgst,
              'sgst_amount': sgst,
              'igst_amount': igst,
              'line_total': base + tax,
            });
          }

          final invoiceId = await txn.insert('invoices', {
            'invoice_number': invoiceNumber,
            'invoice_type': 'purchase',
            'party_id': supplierId,
            'invoice_date': now.toIso8601String(),
            'subtotal': subtotal,
            'tax_total': taxTotal,
            'place_of_supply': placeOfSupply.text.trim(),
            'tax_type': placeOfSupply.text.trim().toLowerCase() == businessState.toLowerCase() ? 'intra_state' : 'inter_state',
            'cgst_total': placeOfSupply.text.trim().toLowerCase() == businessState.toLowerCase() ? taxTotal / 2 : 0,
            'sgst_total': placeOfSupply.text.trim().toLowerCase() == businessState.toLowerCase() ? taxTotal / 2 : 0,
            'igst_total': placeOfSupply.text.trim().toLowerCase() == businessState.toLowerCase() ? 0 : taxTotal,
            'grand_total': subtotal + taxTotal,
            'amount_paid': 0,
            'status': 'unpaid',
            'notes': notes.text.trim(),
          });

          for (final item in preparedItems) {
            await txn.insert('invoice_items', {
              'invoice_id': invoiceId,
              ...item,
            });
            await txn.rawUpdate(
              'UPDATE products SET current_stock = current_stock + ?, purchase_price = ?, updated_at = ? WHERE id = ?',
              [
                item['quantity'],
                item['rate'],
                now.toIso8601String(),
                item['product_id'],
              ],
            );
          }
        });

        await _load();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Purchase saved and stock updated for all items.')),
          );
        }
      } catch (error) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Could not save purchase: $error')),
          );
        }
      }
    }

    for (final line in lines) {
      line.dispose();
    }
    notes.dispose();
    placeOfSupply.dispose();
  }

  Widget _buildLine({
    required _PurchaseLine line,
    required List<Map<String, Object?>> products,
    required VoidCallback onChanged,
    required VoidCallback? onRemove,
  }) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<int>(
                    initialValue: line.productId,
                    decoration: const InputDecoration(labelText: 'Product *'),
                    items: products.map((product) => DropdownMenuItem<int>(
                      value: product['id'] as int,
                      child: Text(
                        product['name'] as String,
                        overflow: TextOverflow.ellipsis,
                      ),
                    )).toList(),
                    validator: (value) => value == null ? 'Select a product' : null,
                    onChanged: (value) {
                      line.productId = value;
                      final product = products.firstWhere((item) => item['id'] == value);
                      line.rate.text = ((product['purchase_price'] as num?) ?? 0).toString();
                      line.gstRate.text = ((product['gst_rate'] as num?) ?? 0).toString();
                      onChanged();
                    },
                  ),
                ),
                IconButton(
                  tooltip: 'Remove item',
                  onPressed: onRemove,
                  icon: const Icon(Icons.remove_circle_outline),
                ),
              ],
            ),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: line.quantity,
                    decoration: const InputDecoration(labelText: 'Quantity'),
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    validator: (value) {
                      final number = double.tryParse(value ?? '');
                      if (number == null || !number.isFinite || number <= 0) {
                        return 'Enter quantity > 0';
                      }
                      return null;
                    },
                    onChanged: (_) => onChanged(),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextFormField(
                    controller: line.rate,
                    decoration: const InputDecoration(labelText: 'Purchase rate (₹)'),
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    validator: (value) {
                      final number = double.tryParse(value ?? '');
                      if (number == null || !number.isFinite || number < 0) {
                        return 'Enter a valid rate';
                      }
                      return null;
                    },
                    onChanged: (_) => onChanged(),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextFormField(
                    controller: line.gstRate,
                    decoration: const InputDecoration(labelText: 'GST (%)'),
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    validator: (value) {
                      final number = double.tryParse(value ?? '');
                      if (number == null || !number.isFinite || number < 0 || number > 100) {
                        return '0–100';
                      }
                      return null;
                    },
                    onChanged: (_) => onChanged(),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _partyTaxDetails(Map<String, Object?> party) {
    final gstin = (party['gstin']?.toString() ?? '').trim();
    final state = (party['state']?.toString() ?? '').trim();
    if (gstin.isEmpty && state.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 8),
      child: Text(
        [
          if (state.isNotEmpty) 'State: $state',
          if (gstin.isNotEmpty) 'GSTIN: $gstin',
        ].join('  |  '),
        style: const TextStyle(fontSize: 12, color: Colors.blueGrey),
      ),
    );
  }

  Widget _totalRow(String label, double amount, {bool bold = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(fontWeight: bold ? FontWeight.bold : FontWeight.normal),
          ),
          Text(
            '₹${amount.toStringAsFixed(2)}',
            style: TextStyle(fontWeight: bold ? FontWeight.bold : FontWeight.normal),
          ),
        ],
      ),
    );
  }


  Future<void> _showPurchaseDetails(Map<String, Object?> invoice) async {
    final db = await AppDatabase.instance.database;
    final items = await db.query(
      'invoice_items',
      where: 'invoice_id = ?',
      whereArgs: [invoice['id']],
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
        title: Text(invoice['invoice_number'] as String),
        content: SizedBox(
          width: 480,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Supplier: ${invoice['party_name'] ?? 'Supplier not selected'}'),
                if ((invoice['party_gstin']?.toString() ?? '').isNotEmpty)
                  Text('Supplier GSTIN: ${invoice['party_gstin']}'),
                if ((invoice['party_state']?.toString() ?? '').isNotEmpty)
                  Text('Supplier State: ${invoice['party_state']}'),
                Text('Date: ${(invoice['invoice_date'] as String).split('T').first}'),
                Text('Place of Supply: ${invoice['place_of_supply'] ?? 'Not recorded'}'),
                Text('Tax type: ${invoice['tax_type'] ?? 'Not classified'}'),
                _totalRow('CGST', (invoice['cgst_total'] as num?)?.toDouble() ?? 0),
                _totalRow('SGST', (invoice['sgst_total'] as num?)?.toDouble() ?? 0),
                _totalRow('IGST', (invoice['igst_total'] as num?)?.toDouble() ?? 0),
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
                _totalRow('Taxable subtotal', (invoice['subtotal'] as num?)?.toDouble() ?? 0),
                _totalRow('GST', (invoice['tax_total'] as num?)?.toDouble() ?? 0),
                _totalRow(
                  'Grand total',
                  (invoice['grand_total'] as num?)?.toDouble() ?? 0,
                  bold: true,
                ),
                Text('Status: ${invoice['status'] ?? 'unpaid'}'),
                if ((invoice['notes']?.toString() ?? '').trim().isNotEmpty)
                  Text('Notes: ${invoice['notes']}'),
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
                  isPurchase: true,
                );
              } catch (error) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Could not create purchase PDF: $error')),
                  );
                }
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

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Purchases')),
    floatingActionButton: FloatingActionButton.extended(
      onPressed: _add,
      icon: const Icon(Icons.add),
      label: const Text('Record purchase'),
    ),
    body: _loading
        ? const Center(child: CircularProgressIndicator())
        : _rows.isEmpty
            ? const Center(child: Text('No purchases recorded yet.'))
            : ListView.separated(
                padding: const EdgeInsets.all(16),
                itemCount: _rows.length,
                separatorBuilder: (_, index) => const Divider(),
                itemBuilder: (context, index) {
                  final row = _rows[index];
                  final total = (row['grand_total'] as num).toDouble();
                  return ListTile(
                    leading: const CircleAvatar(child: Icon(Icons.shopping_cart)),
                    title: Text(row['invoice_number'] as String),
                    subtitle: Text(
                      '${row['party_name'] ?? 'Supplier not selected'} • ${(row['invoice_date'] as String).split('T').first} • ${row['status'] ?? 'unpaid'}',
                    ),
                    trailing: Text('₹${total.toStringAsFixed(2)}'),
                    onTap: () => _showPurchaseDetails(row),
                  );
                },
              ),
  );
}

class _PurchaseLine {
  int? productId;
  final TextEditingController quantity = TextEditingController(text: '1');
  final TextEditingController rate = TextEditingController(text: '0');
  final TextEditingController gstRate = TextEditingController(text: '0');

  void dispose() {
    quantity.dispose();
    rate.dispose();
    gstRate.dispose();
  }
}
