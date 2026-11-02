import 'package:flutter/material.dart';

import '../../data/local/app_database.dart';
import '../../data/local/debit_note_service.dart';
import 'debit_note_pdf_service.dart';

class DebitNotesPage extends StatefulWidget {
  const DebitNotesPage({super.key});

  @override
  State<DebitNotesPage> createState() => _DebitNotesPageState();
}

class _DebitNotesPageState extends State<DebitNotesPage> {
  List<Map<String, Object?>> _notes = [];
  List<Map<String, Object?>> _invoices = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final db = await AppDatabase.instance.database;
    final invoices = await db.rawQuery("""
      SELECT i.id, i.invoice_number, i.invoice_date, i.grand_total,
             i.tax_type, i.place_of_supply, p.name AS party_name
      FROM invoices i
      LEFT JOIN parties p ON p.id = i.party_id
      WHERE i.invoice_type = 'sale'
      ORDER BY i.id DESC
    """);
    final notes = await db.rawQuery("""
      SELECT d.*, i.invoice_number AS original_number, p.name AS party_name
      FROM debit_notes d
      LEFT JOIN invoices i ON i.id = d.original_invoice_id
      LEFT JOIN parties p ON p.id = d.party_id
      ORDER BY d.id DESC
    """);
    if (!mounted) return;
    setState(() {
      _invoices = invoices;
      _notes = notes;
      _loading = false;
    });
  }

  Future<void> _printNote(Map<String, Object?> note) async {
    try {
      final db = await AppDatabase.instance.database;
      final rows = await db.rawQuery('''
        SELECT d.*, i.invoice_number AS original_number,
               p.name AS party_name, p.gstin AS party_gstin,
               p.state AS party_state
        FROM debit_notes d
        LEFT JOIN invoices i ON i.id = d.original_invoice_id
        LEFT JOIN parties p ON p.id = d.party_id
        WHERE d.id = ?
        LIMIT 1
      ''', [note['id']]);
      if (rows.isEmpty) throw StateError('Debit Note record not found.');
      final items = await db.query(
        'debit_note_items',
        where: 'debit_note_id = ?',
        whereArgs: [note['id']],
        orderBy: 'id ASC',
      );
      final settingsRows = await db.query('app_settings');
      final business = <String, String>{
        for (final row in settingsRows)
          row['setting_key'] as String: row['setting_value'] as String,
      };
      await DebitNotePdfService.printDebitNote(
        note: rows.first,
        items: items,
        business: business,
      );
    } catch (error) {
      _message('Debit Note PDF could not be created: $error');
    }
  }

  void _message(String value) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(value)));
  }

  Future<void> _create() async {
    if (AppDatabase.instance.activeBusinessId != null) {
      _message('Cloud business mode-এ Debit Note আপাতত বন্ধ। Cloud sync support সম্পূর্ণ না হওয়া পর্যন্ত local mode ব্যবহার করুন।');
      return;
    }
    if (_invoices.isEmpty) {
      _message('প্রথমে একটি Sales Invoice তৈরি করুন।');
      return;
    }

    final number = TextEditingController(
      text: 'DN-${DateTime.now().millisecondsSinceEpoch}',
    );
    final reason = TextEditingController();
    final description = TextEditingController();
    final quantity = TextEditingController(text: '1');
    final unit = TextEditingController(text: 'pcs');
    final rate = TextEditingController(text: '0');
    final gstRate = TextEditingController(text: '18');
    final hsn = TextEditingController();
    final formKey = GlobalKey<FormState>();
    int? selectedInvoiceId = _invoices.first['id'] as int;

    final accepted = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, refresh) {
          final selected = _invoices.firstWhere((e) => e['id'] == selectedInvoiceId);
          final taxType = selected['tax_type']?.toString();
          final qty = double.tryParse(quantity.text) ?? 0;
          final unitRate = double.tryParse(rate.text) ?? 0;
          final gst = double.tryParse(gstRate.text) ?? 0;
          final taxable = qty > 0 && unitRate >= 0 ? qty * unitRate : 0.0;
          final tax = taxable * gst / 100;
          final intra = taxType == 'intra_state';
          return AlertDialog(
            title: const Text('Create Sales Debit Note'),
            content: SizedBox(
              width: 560,
              child: Form(
                key: formKey,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      DropdownButtonFormField<int>(
                        initialValue: selectedInvoiceId,
                        isExpanded: true,
                        decoration: const InputDecoration(labelText: 'Original Sales Invoice *'),
                        items: _invoices.map((invoice) => DropdownMenuItem<int>(
                          value: invoice['id'] as int,
                          child: Text('${invoice['invoice_number']} • ${invoice['party_name'] ?? 'Walk-in'}'),
                        )).toList(),
                        onChanged: (value) => refresh(() => selectedInvoiceId = value),
                      ),
                      const SizedBox(height: 8),
                      TextFormField(controller: number, decoration: const InputDecoration(labelText: 'Debit Note Number *'),
                        validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null),
                      TextFormField(controller: reason, decoration: const InputDecoration(labelText: 'Reason *'),
                        validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null),
                      const Divider(height: 24),
                      TextFormField(controller: description, decoration: const InputDecoration(labelText: 'Item / Service description *'),
                        validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null),
                      Row(children: [
                        Expanded(child: TextFormField(controller: quantity, keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          decoration: const InputDecoration(labelText: 'Quantity *'), onChanged: (_) => refresh(() {}),
                          validator: (v) { final n = double.tryParse(v ?? ''); return n == null || n.isNaN || n.isInfinite || n <= 0 ? 'Invalid quantity' : null; })),
                        const SizedBox(width: 8),
                        Expanded(child: TextFormField(controller: unit, decoration: const InputDecoration(labelText: 'Unit *'),
                          validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null)),
                        const SizedBox(width: 8),
                        Expanded(child: TextFormField(controller: rate, keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          decoration: const InputDecoration(labelText: 'Rate *'), onChanged: (_) => refresh(() {}),
                          validator: (v) { final n = double.tryParse(v ?? ''); return n == null || n.isNaN || n.isInfinite || n < 0 ? 'Invalid rate' : null; })),
                      ]),
                      Row(children: [
                        Expanded(child: TextFormField(controller: gstRate, keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          decoration: const InputDecoration(labelText: 'GST Rate % *'), onChanged: (_) => refresh(() {}),
                          validator: (v) { final n = double.tryParse(v ?? ''); return n == null || n.isNaN || n.isInfinite || n < 0 || n > 100 ? 'Invalid GST rate' : null; })),
                        const SizedBox(width: 8),
                        Expanded(child: TextFormField(controller: hsn, decoration: const InputDecoration(labelText: 'HSN/SAC (optional)'))),
                      ]),
                      const SizedBox(height: 12),
                      Align(alignment: Alignment.centerLeft, child: Text(
                        'Taxable: ₹${taxable.toStringAsFixed(2)}   •   ${intra ? 'CGST + SGST' : 'IGST'}: ₹${tax.toStringAsFixed(2)}\nGrand total: ₹${(taxable + tax).toStringAsFixed(2)}',
                        style: const TextStyle(fontWeight: FontWeight.w600))),
                      if (taxType != 'intra_state' && taxType != 'inter_state')
                        const Text('Original invoice GST classification is invalid. Debit Note cannot be created.', style: TextStyle(color: Colors.red)),
                    ],
                  ),
                ),
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancel')),
              FilledButton(
                onPressed: () {
                  if (formKey.currentState?.validate() ?? false) Navigator.pop(dialogContext, true);
                },
                child: const Text('Save Debit Note'),
              ),
            ],
          );
        },
      ),
    );

    if (accepted == true) {
      try {
        final selected = _invoices.firstWhere((e) => e['id'] == selectedInvoiceId);
        final taxType = selected['tax_type'] as String?;
        if (taxType != 'intra_state' && taxType != 'inter_state') {
          throw StateError('Original invoice GST classification is invalid.');
        }
        final qty = double.parse(quantity.text.trim());
        final unitRate = double.parse(rate.text.trim());
        final gst = double.parse(gstRate.text.trim());
        final taxable = qty * unitRate;
        final totalTax = taxable * gst / 100;
        final roundedTax = double.parse(totalTax.toStringAsFixed(2));
        final cgst = taxType == 'intra_state' ? double.parse((roundedTax / 2).toStringAsFixed(2)) : 0.0;
        final sgst = taxType == 'intra_state' ? double.parse((roundedTax - cgst).toStringAsFixed(2)) : 0.0;
        final igst = taxType == 'inter_state' ? roundedTax : 0.0;
        final line = DebitNoteLine(
          description: description.text.trim(),
          quantity: qty,
          unit: unit.text.trim(),
          rate: unitRate,
          gstRate: gst,
          taxableValue: taxable,
          cgst: cgst,
          sgst: sgst,
          igst: igst,
          hsnSac: hsn.text.trim().isEmpty ? null : hsn.text.trim(),
        );
        final db = await AppDatabase.instance.database;
        await db.transaction((txn) async {
          await DebitNoteService.createSalesDebitNote(
            txn: txn,
            originalInvoiceId: selectedInvoiceId!,
            debitNoteNumber: number.text.trim(),
            noteDate: DateTime.now().toIso8601String(),
            reason: reason.text.trim(),
            lines: [line],
          );
        });
        _message('Debit Note saved. Accounting entries posted; stock was not changed.');
        await _load();
      } catch (error) {
        _message('Debit Note could not be saved: $error');
      }
    }

    number.dispose();
    reason.dispose();
    description.dispose();
    quantity.dispose();
    unit.dispose();
    rate.dispose();
    gstRate.dispose();
    hsn.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Sales Debit Notes')),
    floatingActionButton: FloatingActionButton.extended(
      onPressed: _create,
      icon: const Icon(Icons.add),
      label: const Text('New Debit Note'),
    ),
    body: _loading
      ? const Center(child: CircularProgressIndicator())
      : RefreshIndicator(
          onRefresh: _load,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              const Card(child: Padding(
                padding: EdgeInsets.all(14),
                child: Text('Debit Note increases the customer receivable and sales/GST liability. It must be linked to an existing sales invoice. This screen is currently local-mode only; cloud sync and GSTN filing are not enabled.'),
              )),
              Text('Debit Note history', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 8),
              if (_notes.isEmpty)
                const Card(child: Padding(padding: EdgeInsets.all(16), child: Text('No Debit Notes recorded yet.')))
              else
                for (final note in _notes)
                  Card(child: ListTile(
                    leading: const CircleAvatar(child: Icon(Icons.note_add)),
                    title: Text(note['debit_note_number']?.toString() ?? ''),
                    subtitle: Text('Against ${note['original_number'] ?? '-'} • ${note['party_name'] ?? 'Walk-in'}\n${note['reason'] ?? ''}'),
                    isThreeLine: true,
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('₹${((note['grand_total'] as num?)?.toDouble() ?? 0).toStringAsFixed(2)}'),
                        IconButton(
                          tooltip: 'PDF / Print',
                          icon: const Icon(Icons.picture_as_pdf),
                          onPressed: () => _printNote(note),
                        ),
                      ],
                    ),
                    onTap: () => _printNote(note),
                  )),
            ],
          ),
        ),
  );
}
