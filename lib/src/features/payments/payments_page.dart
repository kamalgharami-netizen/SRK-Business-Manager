import 'package:flutter/material.dart';
import '../../data/local/app_database.dart';
import '../../data/local/accounting_service.dart';
import '../../data/sync/business_sync_service.dart';

class PaymentsPage extends StatefulWidget {
  const PaymentsPage({super.key});
  @override
  State<PaymentsPage> createState() => _PaymentsPageState();
}

class _PaymentsPageState extends State<PaymentsPage> {
  List<Map<String, Object?>> _rows = [];
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
    } catch (_) {
      // Keep the saved transaction locally; its queue entry remains available for retry.
    }
  }

  Future<void> _load() async {
    final db = await AppDatabase.instance.database;
    final rows = await db.rawQuery('''
      SELECT payments.*, parties.name AS party_name, invoices.invoice_number
      FROM payments
      LEFT JOIN parties ON parties.id = payments.party_id
      LEFT JOIN invoices ON invoices.id = payments.invoice_id
      ORDER BY payments.id DESC
    ''');
    if (!mounted) return;
    setState(() {
      _rows = rows;
      _loading = false;
    });
  }

  String? _validateAmount(String? value) {
    final number = double.tryParse(value?.trim() ?? '');
    if (number == null || !number.isFinite || number <= 0) {
      return 'Enter an amount greater than zero';
    }
    return null;
  }

  Future<void> _add(String type) async {
    final db = await AppDatabase.instance.database;
    final isReceipt = type == 'receipt';
    final expectedInvoiceType = isReceipt ? 'sale' : 'purchase';
    final expectedPartyType = isReceipt ? 'customer' : 'supplier';
    final parties = await db.query(
      'parties',
      where: "party_type IN (?, 'both')",
      whereArgs: [expectedPartyType],
      orderBy: 'name COLLATE NOCASE',
    );
    final invoices = await db.query(
      'invoices',
      where: 'invoice_type = ?',
      whereArgs: [expectedInvoiceType],
      orderBy: 'id DESC',
    );
    if (!mounted) return;

    int? partyId;
    int? invoiceId;
    String mode = 'cash';
    final amount = TextEditingController();
    final reference = TextEditingController();
    final notes = TextEditingController();
    final formKey = GlobalKey<FormState>();

    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, refresh) => AlertDialog(
          title: Text(isReceipt ? 'Record receipt' : 'Record payment'),
          content: SizedBox(
            width: 420,
            child: Form(
              key: formKey,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    DropdownButtonFormField<int>(
                      initialValue: partyId,
                      decoration: InputDecoration(
                        labelText: isReceipt ? 'Customer (optional)' : 'Supplier (optional)',
                      ),
                      items: parties.map((party) => DropdownMenuItem<int>(
                        value: party['id'] as int,
                        child: Text(party['name'] as String),
                      )).toList(),
                      onChanged: (value) => refresh(() => partyId = value),
                    ),
                    DropdownButtonFormField<int>(
                      initialValue: invoiceId,
                      decoration: const InputDecoration(labelText: 'Link invoice (optional)'),
                      items: invoices.map((invoice) {
                        final total = ((invoice['grand_total'] as num?) ?? 0).toDouble();
                        final paid = ((invoice['amount_paid'] as num?) ?? 0).toDouble();
                        final due = (total - paid).clamp(0, double.infinity);
                        return DropdownMenuItem<int>(
                          value: invoice['id'] as int,
                          child: Text(
                            '${invoice['invoice_number']} • Due ₹${due.toStringAsFixed(2)}',
                            overflow: TextOverflow.ellipsis,
                          ),
                        );
                      }).toList(),
                      onChanged: (value) => refresh(() => invoiceId = value),
                    ),
                    TextFormField(
                      controller: amount,
                      decoration: const InputDecoration(labelText: 'Amount (₹) *'),
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      validator: _validateAmount,
                    ),
                    DropdownButtonFormField<String>(
                      initialValue: mode,
                      decoration: const InputDecoration(labelText: 'Payment mode'),
                      items: const [
                        DropdownMenuItem(value: 'cash', child: Text('Cash')),
                        DropdownMenuItem(value: 'upi', child: Text('UPI')),
                        DropdownMenuItem(value: 'bank', child: Text('Bank transfer')),
                        DropdownMenuItem(value: 'card', child: Text('Card')),
                        DropdownMenuItem(value: 'cheque', child: Text('Cheque')),
                      ],
                      onChanged: (value) => refresh(() => mode = value ?? 'cash'),
                    ),
                    TextFormField(
                      controller: reference,
                      decoration: const InputDecoration(labelText: 'Reference / Transaction ID'),
                    ),
                    TextFormField(
                      controller: notes,
                      decoration: const InputDecoration(labelText: 'Notes'),
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
                if (formKey.currentState?.validate() ?? false) {
                  Navigator.pop(dialogContext, true);
                }
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );

    if (saved == true) {
      final value = double.parse(amount.text.trim());
      try {
        await db.transaction((txn) async {
          int? effectivePartyId = partyId;
          late int savedPaymentId;
          final paymentDate = DateTime.now().toIso8601String();

          if (partyId != null) {
            final selectedParties = await txn.query(
              'parties',
              columns: ['id', 'party_type'],
              where: 'id = ?',
              whereArgs: [partyId],
              limit: 1,
            );
            if (selectedParties.isEmpty) {
              throw StateError('The selected party no longer exists.');
            }
            final selectedType = selectedParties.first['party_type'];
            if (selectedType != expectedPartyType && selectedType != 'both') {
              throw StateError(
                isReceipt
                    ? 'A receipt can only be recorded for a customer.'
                    : 'A payment can only be recorded for a supplier.',
              );
            }
          }

          if (invoiceId != null) {
            final found = await txn.query(
              'invoices',
              where: 'id = ?',
              whereArgs: [invoiceId],
              limit: 1,
            );
            if (found.isEmpty) {
              throw StateError('The selected invoice no longer exists.');
            }

            final invoice = found.first;
            if (invoice['invoice_type'] != expectedInvoiceType) {
              throw StateError(
                isReceipt
                    ? 'A receipt must be linked to a sales invoice.'
                    : 'A payment must be linked to a purchase invoice.',
              );
            }

            final invoicePartyId = invoice['party_id'] as int?;
            if (partyId != null && partyId != invoicePartyId) {
              throw StateError('The selected party does not match the invoice party.');
            }
            effectivePartyId ??= invoicePartyId;

            final total = ((invoice['grand_total'] as num?) ?? 0).toDouble();
            final alreadyPaid = ((invoice['amount_paid'] as num?) ?? 0).toDouble();
            if (!total.isFinite || !alreadyPaid.isFinite || total <= 0 || alreadyPaid < 0) {
              throw StateError('The invoice total or paid amount is invalid.');
            }
            final outstanding = total - alreadyPaid;
            if (outstanding <= 0.005) {
              throw StateError('This invoice is already fully paid.');
            }
            if (value > outstanding + 0.005) {
              throw StateError(
                'Amount exceeds the outstanding balance of ₹${outstanding.toStringAsFixed(2)}.',
              );
            }

            final updatedPaid = (alreadyPaid + value).clamp(0, total).toDouble();
            final paymentSyncId = AppDatabase.instance.createSyncId();
            savedPaymentId = await txn.insert('payments', {
              'sync_id': paymentSyncId,
              'party_id': effectivePartyId,
              'invoice_id': invoiceId,
              'payment_type': type,
              'payment_date': paymentDate,
              'amount': value,
              'mode': mode,
              'reference': reference.text.trim(),
              'notes': notes.text.trim(),
            });
            await txn.update(
              'invoices',
              {
                'amount_paid': updatedPaid,
                'status': updatedPaid >= total - 0.005 ? 'paid' : 'partial',
              },
              where: 'id = ?',
              whereArgs: [invoiceId],
            );
          } else {
            final paymentSyncId = AppDatabase.instance.createSyncId();
            savedPaymentId = await txn.insert('payments', {
              'sync_id': paymentSyncId,
              'party_id': effectivePartyId,
              'invoice_id': null,
              'payment_type': type,
              'payment_date': paymentDate,
              'amount': value,
              'mode': mode,
              'reference': reference.text.trim(),
              'notes': notes.text.trim(),
            });
          }

          await AccountingService.postPayment(
            txn,
            paymentId: savedPaymentId,
            date: paymentDate,
            paymentType: type,
            mode: mode,
            amount: value,
            reference: reference.text,
          );

          final paymentRows = await txn.query(
            'payments',
            where: 'id = ?',
            whereArgs: [savedPaymentId],
            limit: 1,
          );
          final payment = Map<String, dynamic>.from(paymentRows.single);
          final paymentSyncId = payment['sync_id'] as String;
          final partyRows = effectivePartyId == null
              ? <Map<String, Object?>>[]
              : await txn.query('parties', columns: ['sync_id'], where: 'id = ?', whereArgs: [effectivePartyId], limit: 1);
          final partySyncId = partyRows.isEmpty ? null : partyRows.first['sync_id'] as String?;
          if (effectivePartyId != null && (partySyncId == null || partySyncId.isEmpty)) {
            throw StateError('Selected party is missing its cloud sync identifier.');
          }
          String? invoiceSyncId;
          if (invoiceId != null) {
            final invoiceRows = await txn.query('invoices', where: 'id = ?', whereArgs: [invoiceId], limit: 1);
            if (invoiceRows.isEmpty) throw StateError('Linked invoice is no longer available.');
            final invoice = Map<String, dynamic>.from(invoiceRows.single);
            invoiceSyncId = invoice['sync_id'] as String?;
            if (invoiceSyncId == null || invoiceSyncId.isEmpty) {
              throw StateError('Linked invoice is missing its cloud sync identifier.');
            }
            final invoicePartyId = invoice['party_id'] as int?;
            final invoicePartyRows = invoicePartyId == null
                ? <Map<String, Object?>>[]
                : await txn.query('parties', columns: ['sync_id'], where: 'id = ?', whereArgs: [invoicePartyId], limit: 1);
            final rawItems = await txn.query('invoice_items', where: 'invoice_id = ?', whereArgs: [invoiceId], orderBy: 'id ASC');
            final syncedItems = <Map<String, dynamic>>[];
            for (final rawItem in rawItems) {
              final item = Map<String, dynamic>.from(rawItem);
              final productId = item.remove('product_id') as int?;
              item.remove('id');
              item.remove('invoice_id');
              final productRows = productId == null
                  ? <Map<String, Object?>>[]
                  : await txn.query('products', columns: ['sync_id'], where: 'id = ?', whereArgs: [productId], limit: 1);
              final productSyncId = productRows.isEmpty ? null : productRows.first['sync_id'] as String?;
              if (productSyncId == null || productSyncId.isEmpty) {
                throw StateError('An invoice item product is missing its cloud sync identifier.');
              }
              item['product_sync_id'] = productSyncId;
              syncedItems.add(item);
            }
            final invoicePayload = Map<String, dynamic>.from(invoice)
              ..remove('id')
              ..remove('party_id')
              ..['party_sync_id'] = invoicePartyRows.isEmpty ? null : invoicePartyRows.first['sync_id']
              ..['items'] = syncedItems;
            await AppDatabase.instance.enqueueSyncOperation(
              executor: txn,
              tableName: 'invoices',
              recordId: invoiceSyncId,
              operation: 'update',
              payload: invoicePayload,
            );
          }
          payment
            ..remove('id')
            ..remove('party_id')
            ..remove('invoice_id')
            ..['party_sync_id'] = partySyncId
            ..['invoice_sync_id'] = invoiceSyncId;
          await AppDatabase.instance.enqueueSyncOperation(
            executor: txn,
            tableName: 'payments',
            recordId: paymentSyncId,
            operation: 'insert',
            payload: payment,
          );
        });

        await _syncIfConfigured();
        await _load();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Transaction saved successfully.')),
          );
        }
      } on StateError catch (error) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(error.message)),
          );
        }
      } catch (error) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Could not save transaction: $error')),
          );
        }
      }
    }

    amount.dispose();
    reference.dispose();
    notes.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Receipts & Payments')),
    floatingActionButton: Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          FloatingActionButton.extended(
            heroTag: 'receipt',
            onPressed: () => _add('receipt'),
            icon: const Icon(Icons.call_received),
            label: const Text('Receipt'),
          ),
          const SizedBox(height: 10),
          FloatingActionButton.extended(
            heroTag: 'payment',
            onPressed: () => _add('payment'),
            icon: const Icon(Icons.call_made),
            label: const Text('Payment'),
          ),
        ],
      ),
    ),
    body: _loading
        ? const Center(child: CircularProgressIndicator())
        : _rows.isEmpty
            ? const Center(child: Text('No receipts or payments recorded yet.'))
            : ListView.separated(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 150),
                itemCount: _rows.length,
                separatorBuilder: (_, index) => const Divider(),
                itemBuilder: (context, index) {
                  final row = _rows[index];
                  final receipt = row['payment_type'] == 'receipt';
                  final value = (row['amount'] as num).toDouble();
                  return ListTile(
                    leading: CircleAvatar(
                      child: Icon(receipt ? Icons.call_received : Icons.call_made),
                    ),
                    title: Text(
                      '${receipt ? 'Receipt' : 'Payment'} • ${row['party_name'] ?? 'Unlinked party'}',
                    ),
                    subtitle: Text(
                      '${row['payment_date'].toString().split('T').first} • ${row['mode']} • ${row['invoice_number'] ?? 'No invoice linked'}',
                    ),
                    trailing: Text(
                      '₹${value.toStringAsFixed(2)}',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: receipt ? Colors.green : Colors.red,
                      ),
                    ),
                  );
                },
              ),
  );
}
