import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'accounting_service.dart';
import 'app_database.dart';

class DebitNoteLine {
  const DebitNoteLine({
    required this.description,
    required this.quantity,
    required this.unit,
    required this.rate,
    required this.gstRate,
    required this.taxableValue,
    required this.cgst,
    required this.sgst,
    required this.igst,
    this.cess = 0,
    this.hsnSac,
  });

  final String description;
  final double quantity;
  final String unit;
  final double rate;
  final double gstRate;
  final double taxableValue;
  final double cgst;
  final double sgst;
  final double igst;
  final double cess;
  final String? hsnSac;

  double get taxAmount => cgst + sgst + igst + cess;
  double get lineTotal => taxableValue + taxAmount;

  void validate({required String taxType}) {
    final values = [quantity, rate, gstRate, taxableValue, cgst, sgst, igst, cess];
    if (description.trim().isEmpty || unit.trim().isEmpty ||
        values.any((value) => !value.isFinite) ||
        quantity <= 0 || rate < 0 || gstRate < 0 || gstRate > 100 ||
        taxableValue < 0 || cgst < 0 || sgst < 0 || igst < 0 || cess < 0) {
      throw const FormatException('Debit note line contains invalid description, quantity, rate or tax values.');
    }
    if ((quantity * rate - taxableValue).abs() > 0.02) {
      throw const FormatException('Debit note taxable value does not match quantity multiplied by rate.');
    }
    if (taxType == 'intra_state' && igst > 0.005) {
      throw const FormatException('Intra-state debit note must not contain IGST.');
    }
    if (taxType == 'inter_state' && (cgst > 0.005 || sgst > 0.005)) {
      throw const FormatException('Inter-state debit note must not contain CGST or SGST.');
    }
    final expectedTax = taxableValue * gstRate / 100;
    if ((taxAmount - expectedTax).abs() > 0.02) {
      throw const FormatException('Debit note GST amounts do not match the selected GST rate.');
    }
  }
}

class DebitNoteService {
  DebitNoteService._();

  /// Creates a local sales debit note against an existing sales invoice.
  /// Cloud-business sync is intentionally blocked until debit-note entities
  /// are supported by the remote schema and conflict-resolution pipeline.
  static Future<int> createSalesDebitNote({
    required Transaction txn,
    required int originalInvoiceId,
    required String debitNoteNumber,
    required String noteDate,
    required String reason,
    required List<DebitNoteLine> lines,
  }) async {
    if (AppDatabase.instance.activeBusinessId != null) {
      throw StateError('Sales debit notes are not yet enabled for cloud businesses. No unsynced cloud record was created.');
    }
    final number = debitNoteNumber.trim();
    final cleanReason = reason.trim();
    final parsedDate = DateTime.tryParse(noteDate);
    if (number.isEmpty || cleanReason.isEmpty || parsedDate == null || lines.isEmpty) {
      throw const FormatException('Debit note number, valid date, reason and at least one line are required.');
    }
    final originalRows = await txn.query(
      'invoices',
      columns: ['id', 'invoice_type', 'party_id', 'place_of_supply', 'tax_type'],
      where: 'id = ?',
      whereArgs: [originalInvoiceId],
      limit: 1,
    );
    if (originalRows.isEmpty || originalRows.single['invoice_type'] != 'sale') {
      throw StateError('A sales debit note must be linked to an existing sales invoice.');
    }
    final original = originalRows.single;
    final taxType = original['tax_type'] as String?;
    final placeOfSupply = (original['place_of_supply'] as String?)?.trim() ?? '';
    if ((taxType != 'intra_state' && taxType != 'inter_state') || placeOfSupply.isEmpty) {
      throw StateError('The original invoice has no verified GST place-of-supply classification.');
    }
    for (final line in lines) {
      line.validate(taxType: taxType!);
    }
    final duplicate = await txn.query(
      'debit_notes',
      columns: ['id'],
      where: 'debit_note_number = ?',
      whereArgs: [number],
      limit: 1,
    );
    if (duplicate.isNotEmpty) throw StateError('This debit note number already exists.');

    double sum(double Function(DebitNoteLine line) value) =>
        lines.fold<double>(0, (total, line) => total + value(line));
    final taxable = sum((line) => line.taxableValue);
    final cgst = sum((line) => line.cgst);
    final sgst = sum((line) => line.sgst);
    final igst = sum((line) => line.igst);
    final cess = sum((line) => line.cess);
    final tax = cgst + sgst + igst + cess;
    final total = taxable + tax;
    if ([taxable, cgst, sgst, igst, cess, tax, total].any((value) => !value.isFinite)) {
      throw StateError('Debit note totals exceed the supported numeric range.');
    }

    final id = await txn.insert('debit_notes', {
      'debit_note_number': number,
      'original_invoice_id': originalInvoiceId,
      'party_id': original['party_id'],
      'note_date': parsedDate.toIso8601String(),
      'reason': cleanReason,
      'place_of_supply': placeOfSupply,
      'tax_type': taxType,
      'taxable_value': taxable,
      'cgst_total': cgst,
      'sgst_total': sgst,
      'igst_total': igst,
      'cess_total': cess,
      'tax_total': tax,
      'grand_total': total,
      'status': 'posted',
    });
    for (final line in lines) {
      await txn.insert('debit_note_items', {
        'debit_note_id': id,
        'description': line.description.trim(),
        'hsn_sac': line.hsnSac?.trim(),
        'quantity': line.quantity,
        'unit': line.unit.trim(),
        'rate': line.rate,
        'taxable_value': line.taxableValue,
        'gst_rate': line.gstRate,
        'cgst_amount': line.cgst,
        'sgst_amount': line.sgst,
        'igst_amount': line.igst,
        'cess_amount': line.cess,
        'tax_amount': line.taxAmount,
        'line_total': line.lineTotal,
      });
    }
    await AccountingService.postSalesDebitNote(
      txn,
      debitNoteId: id,
      debitNoteNumber: number,
      date: parsedDate.toIso8601String(),
      taxableValue: taxable,
      tax: tax,
      total: total,
    );
    return id;
  }
}
