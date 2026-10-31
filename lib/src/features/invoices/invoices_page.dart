import 'package:flutter/material.dart';

import '../../data/local/app_database.dart';
import '../../data/sync/business_sync_service.dart';
import '../../data/local/accounting_service.dart';
import '../../data/local/inventory_cost_service.dart';
import '../../data/local/gst_calculator.dart';
import '../../data/indian_states.dart';
import 'invoice_pdf_service.dart';

class InvoicesPage extends StatefulWidget {
  const InvoicesPage({super.key});

  @override
  State<InvoicesPage> createState() => _InvoicesPageState();
}

class _InvoicesPageState extends State<InvoicesPage> {
  List<Map<String, Object?>> _invoices = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadInvoices();
  }

  Future<void> _syncIfConfigured() async {
    final businessId = AppDatabase.instance.activeBusinessId;
    if (businessId == null) return;
    try {
      await BusinessSyncService(businessId: businessId).syncNow();
    } catch (_) {
      // Keep invoicing available offline; queued records remain on this device.
    }
  }

  Future<void> _loadInvoices() async {
    final db = await AppDatabase.instance.database;
    final rows = await db.rawQuery('''
      SELECT invoices.*, parties.name AS party_name,
             parties.gstin AS party_gstin, parties.state AS party_state
      FROM invoices
      LEFT JOIN parties ON parties.id = invoices.party_id
      WHERE invoices.invoice_type = 'sale'
      ORDER BY invoices.id DESC
    ''');
    if (!mounted) return;
    setState(() {
      _invoices = rows;
      _loading = false;
    });
  }

  Future<void> _createInvoice() async {
    final db = await AppDatabase.instance.database;
    final parties = await db.query(
      'parties',
      where: "party_type IN ('customer','both')",
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
        const SnackBar(content: Text('Please add a product before creating an invoice.')),
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
        const SnackBar(content: Text('Set your GST registration state in Settings before creating a GST invoice.')),
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
    final formKey = GlobalKey<FormState>();
    int? selectedPartyId;
    final lines = <_InvoiceLine>[_InvoiceLine()];
    final notes = TextEditingController();

    final saved = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, refreshDialog) {
          double subtotal = 0;
          double taxTotal = 0;
          double cgstTotal = 0;
          double sgstTotal = 0;
          double igstTotal = 0;
          final isIntraState = placeOfSupply.text.trim().toLowerCase() == businessState.toLowerCase();
          for (final line in lines) {
            final quantity = double.tryParse(line.quantity.text) ?? 0;
            final rate = double.tryParse(line.rate.text) ?? 0;
            final gst = double.tryParse(line.gstRate.text) ?? 0;
            if (quantity <= 0 || rate < 0 || gst < 0 || gst > 100) continue;
            final tax = GstCalculator.calculate(quantity: quantity, unitRate: rate, gstRate: gst, intraState: isIntraState);
            subtotal += tax.taxableValue;
            taxTotal += tax.taxAmount;
            cgstTotal += tax.cgstAmount;
            sgstTotal += tax.sgstAmount;
            igstTotal += tax.igstAmount;
          }
          final grandTotal = subtotal + taxTotal;

          return AlertDialog(
            title: const Text('Create sales invoice'),
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
                        initialValue: selectedPartyId,
                        decoration: const InputDecoration(labelText: 'Customer (optional)'),
                        items: parties.map((party) => DropdownMenuItem<int>(
                          value: party['id'] as int,
                          child: Text(party['name'] as String),
                        )).toList(),
                        onChanged: (value) => refreshDialog(() => selectedPartyId = value),
                      ),
                      if (selectedPartyId != null) ...[
                        _partyTaxDetails(parties.firstWhere((party) => party['id'] == selectedPartyId)),
                      ],
                      DropdownButtonFormField<String>(
                        initialValue: IndianStates.all.contains(placeOfSupply.text)
                            ? placeOfSupply.text
                            : null,
                        decoration: const InputDecoration(
                          labelText: 'Place of Supply state *',
                          helperText: 'Select the state applicable to this supply.',
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
                      Text('Invoice items', style: Theme.of(context).textTheme.titleMedium),
                      const SizedBox(height: 8),
                      for (var index = 0; index < lines.length; index++)
                        _buildLine(
                          line: lines[index],
                          products: products,
                          onChanged: () => refreshDialog(() {}),
                          onRemove: lines.length == 1 ? null : () {
                            final removed = lines.removeAt(index);
                            removed.dispose();
                            refreshDialog(() {});
                          },
                        ),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton.icon(
                          onPressed: () => refreshDialog(() => lines.add(_InvoiceLine())),
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
                      _totalRow('Grand total', grandTotal, bold: true),
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
                onPressed: () async {
                  final valid = formKey.currentState?.validate() ?? false;
                  if (!valid) return;
                  for (final line in lines) {
                    if (line.productId == null) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Select a product for every invoice item.')),
                      );
                      return;
                    }
                  }
                  Navigator.pop(dialogContext, true);
                },
                child: const Text('Save invoice'),
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
          final invoiceNumber = 'INV-${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}-${now.microsecondsSinceEpoch.toString().substring(8)}';
          double subtotal = 0;
          double taxTotal = 0;
          double cgstTotal = 0;
          double sgstTotal = 0;
          double igstTotal = 0;
          final prepared = <Map<String, Object?>>[];

          for (final line in lines) {
            final product = products.firstWhere((item) => item['id'] == line.productId);
            final quantity = double.parse(line.quantity.text.trim());
            final rate = double.parse(line.rate.text.trim());
            final gstRate = double.parse(line.gstRate.text.trim());
            final stock = (product['current_stock'] as num?)?.toDouble() ?? 0;
            if (quantity > stock) {
              throw StateError('Insufficient stock for ${product['name']}. Available: $stock');
            }
            final isIntraState = placeOfSupply.text.trim().toLowerCase() == businessState.toLowerCase();
            final tax = GstCalculator.calculate(quantity: quantity, unitRate: rate, gstRate: gstRate, intraState: isIntraState);
            final base = tax.taxableValue;
            subtotal += base;
            taxTotal += tax.taxAmount;
            cgstTotal += tax.cgstAmount;
            sgstTotal += tax.sgstAmount;
            igstTotal += tax.igstAmount;
            prepared.add({
              'product_id': line.productId,
              'description': product['name'] as String,
              'hsn_sac': product['hsn_sac'],
              'quantity': quantity,
              'unit': product['unit'] as String? ?? 'pcs',
              'rate': rate,
              'discount': 0,
              'gst_rate': gstRate,
              'tax_amount': tax.taxAmount,
              'cgst_amount': tax.cgstAmount,
              'sgst_amount': tax.sgstAmount,
              'igst_amount': tax.igstAmount,
              'line_total': tax.lineTotal,
            });
          }

          subtotal = GstCalculator.roundMoney(subtotal);
          taxTotal = GstCalculator.roundMoney(taxTotal);
          cgstTotal = GstCalculator.roundMoney(cgstTotal);
          sgstTotal = GstCalculator.roundMoney(sgstTotal);
          igstTotal = GstCalculator.roundMoney(igstTotal);

          final invoiceSyncId = AppDatabase.instance.createSyncId();
          final invoiceId = await txn.insert('invoices', {
            'sync_id': invoiceSyncId,
            'invoice_number': invoiceNumber,
            'invoice_type': 'sale',
            'party_id': selectedPartyId,
            'invoice_date': now.toIso8601String(),
            'subtotal': subtotal,
            'tax_total': taxTotal,
            'place_of_supply': placeOfSupply.text.trim(),
            'tax_type': placeOfSupply.text.trim().toLowerCase() == businessState.toLowerCase() ? 'intra_state' : 'inter_state',
            'cgst_total': cgstTotal,
            'sgst_total': sgstTotal,
            'igst_total': igstTotal,
            'grand_total': GstCalculator.roundMoney(subtotal + taxTotal),
            'amount_paid': 0,
            'status': 'unpaid',
            'notes': notes.text.trim(),
          });

          var totalCogs = 0.0;
          for (final item in prepared) {
            item['sync_id'] = AppDatabase.instance.createSyncId();
            final invoiceItemId = await txn.insert('invoice_items', {'invoice_id': invoiceId, ...item});
            totalCogs += await InventoryCostService.consumeForSale(
              txn,
              invoiceItemId: invoiceItemId,
              productId: item['product_id'] as int,
              quantity: (item['quantity'] as num).toDouble(),
              soldAt: now.toIso8601String(),
            );
            await txn.rawUpdate(
              'UPDATE products SET current_stock = current_stock - ?, updated_at = ? WHERE id = ?',
              [item['quantity'], now.toIso8601String(), item['product_id']],
            );
            final productRows = await txn.query(
              'products',
              where: 'id = ?',
              whereArgs: [item['product_id']],
              limit: 1,
            );
            if (productRows.isNotEmpty) {
              final product = Map<String, dynamic>.from(productRows.single);
              final productSyncId = product['sync_id'] as String?;
              if (productSyncId != null && productSyncId.isNotEmpty) {
                await AppDatabase.instance.enqueueSyncOperation(
                  executor: txn,
                  tableName: 'products',
                  recordId: productSyncId,
                  operation: 'update',
                  payload: product,
                );
              }
            }
          }

          final invoiceRows = await txn.query(
            'invoices',
            where: 'id = ?',
            whereArgs: [invoiceId],
            limit: 1,
          );
          final partyRows = selectedPartyId == null
              ? <Map<String, Object?>>[]
              : await txn.query(
                  'parties',
                  columns: ['sync_id'],
                  where: 'id = ?',
                  whereArgs: [selectedPartyId],
                  limit: 1,
                );
          final partySyncId = partyRows.isEmpty ? null : partyRows.first['sync_id'] as String?;
          final invoiceItems = await txn.query(
            'invoice_items',
            where: 'invoice_id = ?',
            whereArgs: [invoiceId],
            orderBy: 'id ASC',
          );
          final syncedItems = <Map<String, dynamic>>[];
          for (final rawItem in invoiceItems) {
            final item = Map<String, dynamic>.from(rawItem);
            final productId = item.remove('product_id') as int?;
            item.remove('id');
            item.remove('invoice_id');
            String? productSyncId;
            if (productId != null) {
              final productRows = await txn.query(
                'products',
                columns: ['sync_id'],
                where: 'id = ?',
                whereArgs: [productId],
                limit: 1,
              );
              productSyncId = productRows.isEmpty ? null : productRows.first['sync_id'] as String?;
            }
            item['product_sync_id'] = productSyncId;
            syncedItems.add(item);
          }
          final invoicePayload = Map<String, dynamic>.from(invoiceRows.single)
            ..remove('id')
            ..remove('party_id')
            ..['party_sync_id'] = partySyncId
            ..['items'] = syncedItems;
          await AppDatabase.instance.enqueueSyncOperation(
            executor: txn,
            tableName: 'invoices',
            recordId: invoiceSyncId,
            operation: 'insert',
            payload: invoicePayload,
          );

          await AccountingService.postSalesInvoice(
            txn,
            invoiceId: invoiceId,
            invoiceNumber: invoiceNumber,
            date: now.toIso8601String(),
            subtotal: subtotal,
            tax: taxTotal,
            total: subtotal + taxTotal,
            costOfGoodsSold: totalCogs,
          );
        });
        await _syncIfConfigured();
        await _loadInvoices();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Sales invoice saved and stock updated.')),
          );
        }
      } on StateError catch (error) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(error.message)),
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
    required _InvoiceLine line,
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
                      child: Text(product['name'] as String, overflow: TextOverflow.ellipsis),
                    )).toList(),
                    validator: (value) => value == null ? 'Select a product' : null,
                    onChanged: (value) {
                      line.productId = value;
                      final product = products.firstWhere((item) => item['id'] == value);
                      line.rate.text = ((product['sale_price'] as num?) ?? 0).toString();
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
                Expanded(child: TextFormField(
                  controller: line.quantity,
                  decoration: const InputDecoration(labelText: 'Quantity'),
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  validator: (value) {
                    final number = double.tryParse(value ?? '');
                    if (number == null || number <= 0) return 'Enter quantity > 0';
                    return null;
                  },
                  onChanged: (_) => onChanged(),
                )),
                const SizedBox(width: 12),
                Expanded(child: TextFormField(
                  controller: line.rate,
                  decoration: const InputDecoration(labelText: 'Rate (₹)'),
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  validator: (value) {
                    final number = double.tryParse(value ?? '');
                    if (number == null || number < 0) return 'Enter a valid rate';
                    return null;
                  },
                  onChanged: (_) => onChanged(),
                )),
                const SizedBox(width: 12),
                Expanded(child: TextFormField(
                  controller: line.gstRate,
                  decoration: const InputDecoration(labelText: 'GST (%)'),
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  validator: (value) {
                    final number = double.tryParse(value ?? '');
                    if (number == null || number < 0 || number > 100) return '0–100';
                    return null;
                  },
                  onChanged: (_) => onChanged(),
                )),
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
          Text(label, style: TextStyle(fontWeight: bold ? FontWeight.bold : FontWeight.normal)),
          Text(
            '₹${amount.toStringAsFixed(2)}',
            style: TextStyle(fontWeight: bold ? FontWeight.bold : FontWeight.normal),
          ),
        ],
      ),
    );
  }

  Future<void> _showInvoiceDetails(Map<String, Object?> invoice) async {
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
      builder: (context) => AlertDialog(
        title: Text(invoice['invoice_number'] as String),
        content: SizedBox(
          width: 440,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Customer: ${invoice['party_name'] ?? 'Walk-in customer'}'),
              if ((invoice['party_gstin']?.toString() ?? '').isNotEmpty)
                Text('Customer GSTIN: ${invoice['party_gstin']}'),
              if ((invoice['party_state']?.toString() ?? '').isNotEmpty)
                Text('Customer State: ${invoice['party_state']}'),
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
                  title: Text(item['description'] as String),
                  subtitle: Text('${item['quantity']} ${item['unit']} × ₹${item['rate']}  |  GST ${item['gst_rate']}%'),
                  trailing: Text('₹${(item['line_total'] as num).toStringAsFixed(2)}'),
                ),
              const Divider(),
              _totalRow('Total', (invoice['grand_total'] as num).toDouble(), bold: true),
              Text('Status: ${invoice['status']}'),
            ],
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
                );
              } catch (error) {
                if (mounted) {
                  ScaffoldMessenger.of(this.context).showSnackBar(
                    SnackBar(content: Text('Could not create invoice PDF: $error')),
                  );
                }
              }
            },
            icon: const Icon(Icons.picture_as_pdf),
            label: const Text('PDF / Print'),
          ),
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close')),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Sales & Invoices')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _createInvoice,
        icon: const Icon(Icons.add),
        label: const Text('New invoice'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _invoices.isEmpty
              ? const Center(child: Text('No sales invoices yet. Tap New invoice to create one.'))
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 88),
                  itemCount: _invoices.length,
                  separatorBuilder: (_, index) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final invoice = _invoices[index];
                    final total = (invoice['grand_total'] as num).toDouble();
                    return ListTile(
                      leading: const CircleAvatar(child: Icon(Icons.receipt_long)),
                      title: Text(invoice['invoice_number'] as String),
                      subtitle: Text(
                        '${invoice['party_name'] ?? 'Walk-in customer'} • ${(invoice['invoice_date'] as String).split('T').first} • ${invoice['status']}',
                      ),
                      trailing: Text('₹${total.toStringAsFixed(2)}'),
                      onTap: () => _showInvoiceDetails(invoice),
                    );
                  },
                ),
    );
  }
}

class _InvoiceLine {
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
