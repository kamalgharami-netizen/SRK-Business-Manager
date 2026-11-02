import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'app_database.dart';
import 'gst_gstr3b_itc.dart';

class Gstr2bImportRecord {
  const Gstr2bImportRecord({
    required this.supplierGstin, required this.invoiceNumber,
    required this.invoiceDate, required this.returnPeriod,
    required this.taxableValue, this.igst = 0, this.cgst = 0,
    this.sgst = 0, this.cess = 0, this.sourceReference,
  });
  final String supplierGstin, invoiceNumber, invoiceDate, returnPeriod;
  final double taxableValue, igst, cgst, sgst, cess;
  final String? sourceReference;
  Map<String, Object?> toMap() => {
    'supplier_gstin': supplierGstin.trim().toUpperCase(),
    'invoice_number': invoiceNumber.trim().toUpperCase(),
    'invoice_date': _dateOnly(invoiceDate),
    'return_period': returnPeriod,
    'taxable_value': taxableValue, 'igst': igst, 'cgst': cgst,
    'sgst': sgst, 'cess': cess, 'source_reference': sourceReference,
  };
}

class Gstr2bImportResult {
  const Gstr2bImportResult(this.imported, this.duplicates);
  final int imported, duplicates;
}

class Gstr3bItcAssessmentValidator {
  Gstr3bItcAssessmentValidator._();
  static List<String> validate({
    required String supplierGstin, required String supplierInvoiceNumber,
    required String supplierInvoiceDate, required String returnPeriod,
    required double taxableValue, required Gstr3bTaxAmounts tax,
  }) {
    final issues = <String>[];
    final gstin = supplierGstin.trim().toUpperCase();
    if (gstin.isEmpty) {
      issues.add('Supplier GSTIN is missing.');
    } else if (!RegExp(r'^[0-9]{2}[A-Z]{5}[0-9]{4}[A-Z][1-9A-Z]Z[0-9A-Z]$').hasMatch(gstin)) {
      issues.add('Supplier GSTIN format is invalid.');
    }
    if (supplierInvoiceNumber.trim().isEmpty || supplierInvoiceNumber.trim().length > 50) {
      issues.add('Supplier invoice number is missing or exceeds 50 characters.');
    }
    if (_dateOnly(supplierInvoiceDate) == null) issues.add('Supplier invoice date is invalid.');
    if (!RegExp(r'^\d{4}-(0[1-9]|1[0-2])$').hasMatch(returnPeriod)) {
      issues.add('Return period must use YYYY-MM format.');
    }
    if (!taxableValue.isFinite || taxableValue < 0) issues.add('Taxable value must be finite and non-negative.');
    if (!tax.isValid) issues.add('GST components must be finite and non-negative.');
    return List.unmodifiable(issues);
  }
}

class Gstr2bReconciliationMatcher {
  Gstr2bReconciliationMatcher._();
  static bool matches({
    required Gstr2bImportRecord statement, required String supplierGstin,
    required String invoiceNumber, required String invoiceDate,
    required String returnPeriod, required double taxableValue,
    required Gstr3bTaxAmounts tax,
  }) =>
      statement.supplierGstin.trim().toUpperCase() == supplierGstin.trim().toUpperCase() &&
      statement.invoiceNumber.trim().toUpperCase() == invoiceNumber.trim().toUpperCase() &&
      _dateOnly(statement.invoiceDate) == _dateOnly(invoiceDate) &&
      statement.returnPeriod == returnPeriod &&
      (statement.taxableValue - taxableValue).abs() <= 0.01 &&
      (statement.igst - tax.igst).abs() <= 0.01 &&
      (statement.cgst - tax.cgst).abs() <= 0.01 &&
      (statement.sgst - tax.sgst).abs() <= 0.01 &&
      (statement.cess - tax.cess).abs() <= 0.01;
}

class Gstr2bCsvImporter {
  Gstr2bCsvImporter._();

  static const requiredHeaders = [
    'supplier_gstin', 'invoice_number', 'invoice_date',
    'return_period', 'taxable_value', 'igst', 'cgst', 'sgst', 'cess',
  ];

  static List<Gstr2bImportRecord> parse(String content) {
    final rows = _parseCsvRows(content);
    if (rows.length < 2) throw const FormatException('CSV must contain a header and at least one data row.');
    final headers = rows.first.map((v) => v.trim().toLowerCase()).toList();
    if (headers.toSet().length != headers.length) {
      throw const FormatException('CSV contains duplicate column headers.');
    }
    final indexes = <String, int>{for (var i = 0; i < headers.length; i++) headers[i]: i};
    final missing = requiredHeaders.where((h) => !indexes.containsKey(h)).toList();
    if (missing.isNotEmpty) throw FormatException('CSV is missing required columns: ${missing.join(', ')}.');
    String value(List<String> row, String name) {
      final index = indexes[name]!;
      return index < row.length ? row[index].trim() : '';
    }
    double amount(List<String> row, String name) {
      final raw = value(row, name);
      if (raw.isEmpty) return 0;
      final parsed = double.tryParse(raw);
      if (parsed == null || !parsed.isFinite || parsed < 0) {
        throw FormatException('Invalid numeric value in CSV column $name.');
      }
      return parsed;
    }
    final records = <Gstr2bImportRecord>[];
    for (var i = 1; i < rows.length; i++) {
      final row = rows[i];
      if (row.every((v) => v.trim().isEmpty)) continue;
      if (row.length != headers.length) {
        throw FormatException('CSV row ${i + 1} has ${row.length} columns; expected ${headers.length}.');
      }
      records.add(Gstr2bImportRecord(
        supplierGstin: value(row, 'supplier_gstin'),
        invoiceNumber: value(row, 'invoice_number'),
        invoiceDate: value(row, 'invoice_date'),
        returnPeriod: value(row, 'return_period'),
        taxableValue: amount(row, 'taxable_value'),
        igst: amount(row, 'igst'),
        cgst: amount(row, 'cgst'),
        sgst: amount(row, 'sgst'),
        cess: amount(row, 'cess'),
        sourceReference: indexes.containsKey('source_reference') ? value(row, 'source_reference') : null,
      ));
    }
    if (records.isEmpty) throw const FormatException('CSV contains no GSTR-2B invoice rows.');
    return List.unmodifiable(records);
  }

  static List<List<String>> _parseCsvRows(String input) {
    // Accept UTF-8 BOMs commonly added by spreadsheet exports.
    final source = input.startsWith('\uFEFF') ? input.substring(1) : input;
    final rows = <List<String>>[];
    var row = <String>[];
    var field = StringBuffer();
    var quoted = false;
    var quoteClosed = false;

    void finishField() {
      row.add(field.toString());
      field = StringBuffer();
      quoteClosed = false;
    }

    void finishRow() {
      finishField();
      if (row.any((value) => value.trim().isNotEmpty)) {
        rows.add(row);
      }
      row = <String>[];
    }

    for (var i = 0; i < source.length; i++) {
      final char = source[i];
      if (quoted) {
        if (char == '"') {
          if (i + 1 < source.length && source[i + 1] == '"') {
            field.write('"');
            i++;
          } else {
            quoted = false;
            quoteClosed = true;
          }
        } else {
          field.write(char);
        }
        continue;
      }

      if (quoteClosed) {
        if (char == ',') {
          finishField();
        } else if (char == '\n' || char == '\r') {
          if (char == '\r' &&
              i + 1 < source.length &&
              source[i + 1] == '\n') {
            i++;
          }
          finishRow();
        } else {
          throw const FormatException(
            'CSV contains unexpected characters after a closing quote.',
          );
        }
        continue;
      }

      if (char == '"') {
        if (field.length != 0) {
          throw const FormatException(
            'CSV contains a quote inside an unquoted field.',
          );
        }
        quoted = true;
      } else if (char == ',') {
        finishField();
      } else if (char == '\n' || char == '\r') {
        if (char == '\r' &&
            i + 1 < source.length &&
            source[i + 1] == '\n') {
          i++;
        }
        finishRow();
      } else {
        field.write(char);
      }
    }

    if (quoted) {
      throw const FormatException('CSV contains an unclosed quoted field.');
    }
    if (quoteClosed || field.length > 0 || row.isNotEmpty) {
      finishRow();
    }
    return rows;
  }
}

class Gstr3bItcRepository {
  Gstr3bItcRepository._();

  static Future<Gstr3bItcTreatment> savePurchaseAssessment(DatabaseExecutor executor, {
    required int purchaseInvoiceId, required String supplierInvoiceNumber,
    required String supplierInvoiceDate, required String returnPeriod,
    required Gstr3bItcCategory category, required Gstr3bItcTreatment treatment,
    required double taxableValue, required Gstr3bTaxAmounts tax,
  }) async {
    final rows = await executor.rawQuery('''
      SELECT i.invoice_type, p.gstin AS supplier_gstin
      FROM invoices i LEFT JOIN parties p ON p.id = i.party_id
      WHERE i.id = ? LIMIT 1
    ''', [purchaseInvoiceId]);
    if (rows.isEmpty || rows.first['invoice_type'] != 'purchase') {
      throw StateError('ITC assessment must reference an existing purchase invoice.');
    }
    final issues = Gstr3bItcAssessmentValidator.validate(
      supplierGstin: rows.first['supplier_gstin'] as String? ?? '',
      supplierInvoiceNumber: supplierInvoiceNumber,
      supplierInvoiceDate: supplierInvoiceDate,
      returnPeriod: returnPeriod,
      taxableValue: taxableValue,
      tax: tax,
    );
    final blocking = issues.where((e) => !e.startsWith('Supplier GSTIN')).toList();
    if (blocking.isNotEmpty) throw FormatException(blocking.join(' '));
    final gstin = (rows.first['supplier_gstin'] as String? ?? '').trim().toUpperCase();
    final gstinValid = RegExp(r'^[0-9]{2}[A-Z]{5}[0-9]{4}[A-Z][1-9A-Z]Z[0-9A-Z]$').hasMatch(gstin);
    final safeTreatment = gstinValid ? treatment : Gstr3bItcTreatment.pendingReview;
    await executor.insert('purchase_itc_assessments', {
      'purchase_invoice_id': purchaseInvoiceId,
      'supplier_invoice_number': supplierInvoiceNumber.trim(),
      'supplier_invoice_date': _dateOnly(supplierInvoiceDate)!,
      'return_period': returnPeriod,
      'category': category.name, 'treatment': safeTreatment.name,
      'taxable_value': taxableValue,
      'igst': tax.igst, 'cgst': tax.cgst, 'sgst': tax.sgst, 'cess': tax.cess,
      'gstr2b_status': 'pending_review',
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
    return safeTreatment;
  }

  static Future<Gstr2bImportResult> importGstr2bRecords(Iterable<Gstr2bImportRecord> records) async {
    final db = await AppDatabase.instance.database;
    var imported = 0, duplicates = 0;
    await db.transaction((txn) async {
      for (final record in records) {
        final tax = Gstr3bTaxAmounts(igst: record.igst, cgst: record.cgst, sgst: record.sgst, cess: record.cess);
        final issues = Gstr3bItcAssessmentValidator.validate(
          supplierGstin: record.supplierGstin, supplierInvoiceNumber: record.invoiceNumber,
          supplierInvoiceDate: record.invoiceDate, returnPeriod: record.returnPeriod,
          taxableValue: record.taxableValue, tax: tax,
        );
        if (issues.isNotEmpty) throw FormatException(issues.join(' '));
        final existing = await txn.query(
          'gstr2b_documents',
          columns: ['id'],
          where: 'upper(trim(supplier_gstin)) = ? AND upper(trim(invoice_number)) = ? AND invoice_date = ? AND return_period = ?',
          whereArgs: [
            record.supplierGstin.trim().toUpperCase(),
            record.invoiceNumber.trim().toUpperCase(),
            _dateOnly(record.invoiceDate),
            record.returnPeriod,
          ],
          limit: 1,
        );
        if (existing.isNotEmpty) {
          duplicates++;
          continue;
        }
        await txn.insert('gstr2b_documents', record.toMap());
        imported++;
      }
    });
    return Gstr2bImportResult(imported, duplicates);
  }

  static Future<String> reconcilePurchaseInvoice(int purchaseInvoiceId) async {
    final db = await AppDatabase.instance.database;
    return db.transaction((txn) async {
      final rows = await txn.rawQuery('''
        SELECT a.*, p.gstin AS supplier_gstin
        FROM purchase_itc_assessments a
        JOIN invoices i ON i.id = a.purchase_invoice_id
        LEFT JOIN parties p ON p.id = i.party_id
        WHERE a.purchase_invoice_id = ? LIMIT 1
      ''', [purchaseInvoiceId]);
      if (rows.isEmpty) throw StateError('Purchase ITC assessment was not found.');
      final row = rows.first;
      final gstin = (row['supplier_gstin'] as String? ?? '').trim().toUpperCase();
      final candidates = gstin.isEmpty ? <Map<String, Object?>>[] : await txn.query(
        'gstr2b_documents',
        where: 'upper(trim(supplier_gstin)) = ? AND upper(trim(invoice_number)) = ? AND invoice_date = ? AND return_period = ?',
        whereArgs: [
          gstin,
          (row['supplier_invoice_number'] as String).trim().toUpperCase(),
          _dateOnly(row['supplier_invoice_date'] as String),
          row['return_period'],
        ],
        limit: 1,
      );
      var status = 'not_in_statement';
      int? documentId;
      String? reference;
      if (candidates.isNotEmpty) {
        final c = candidates.first;
        final statement = Gstr2bImportRecord(
          supplierGstin: c['supplier_gstin'] as String,
          invoiceNumber: c['invoice_number'] as String,
          invoiceDate: c['invoice_date'] as String,
          returnPeriod: c['return_period'] as String,
          taxableValue: (c['taxable_value'] as num).toDouble(),
          igst: (c['igst'] as num).toDouble(), cgst: (c['cgst'] as num).toDouble(),
          sgst: (c['sgst'] as num).toDouble(), cess: (c['cess'] as num).toDouble(),
          sourceReference: c['source_reference'] as String?,
        );
        final tax = Gstr3bTaxAmounts(
          igst: (row['igst'] as num).toDouble(), cgst: (row['cgst'] as num).toDouble(),
          sgst: (row['sgst'] as num).toDouble(), cess: (row['cess'] as num).toDouble(),
        );
        status = Gstr2bReconciliationMatcher.matches(
          statement: statement, supplierGstin: gstin,
          invoiceNumber: row['supplier_invoice_number'] as String,
          invoiceDate: row['supplier_invoice_date'] as String,
          returnPeriod: row['return_period'] as String,
          taxableValue: (row['taxable_value'] as num).toDouble(), tax: tax,
        ) ? 'matched' : 'not_matched';
        documentId = c['id'] as int;
        reference = c['source_reference'] as String?;
      }
      await txn.update('purchase_itc_assessments', {
        'gstr2b_status': status, 'gstr2b_document_id': documentId,
        'gstr2b_reference': reference,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      }, where: 'purchase_invoice_id = ?', whereArgs: [purchaseInvoiceId]);
      return status;
    });
  }

  static Future<Map<String, int>> reconcilePeriod(String returnPeriod) async {
    if (!RegExp(r'^\d{4}-(0[1-9]|1[0-2])$').hasMatch(returnPeriod)) {
      throw const FormatException('Return period must use YYYY-MM format.');
    }
    final db = await AppDatabase.instance.database;
    final rows = await db.query('purchase_itc_assessments',
      columns: ['purchase_invoice_id'], where: 'return_period = ?',
      whereArgs: [returnPeriod], orderBy: 'purchase_invoice_id');
    final result = <String, int>{'matched': 0, 'not_matched': 0, 'not_in_statement': 0};
    for (final row in rows) {
      final status = await reconcilePurchaseInvoice(row['purchase_invoice_id'] as int);
      result[status] = (result[status] ?? 0) + 1;
    }
    return result;
  }

  static Future<int> addAdjustment({
    required String documentReference, required String returnPeriod,
    required Gstr3bItcTreatment treatment, required Gstr3bTaxAmounts tax,
    String? notes,
  }) async {
    const allowed = {
      Gstr3bItcTreatment.reversalRules38_42_43And17_5,
      Gstr3bItcTreatment.reversalOther,
      Gstr3bItcTreatment.reclaimedPreviousReversal,
    };
    if (documentReference.trim().isEmpty ||
        !RegExp(r'^\d{4}-(0[1-9]|1[0-2])$').hasMatch(returnPeriod) ||
        !tax.isValid || !allowed.contains(treatment)) {
      throw const FormatException('ITC adjustment details are incomplete or invalid.');
    }
    final db = await AppDatabase.instance.database;
    return db.insert('gst_itc_adjustments', {
      'document_reference': documentReference.trim(), 'return_period': returnPeriod,
      'treatment': treatment.name, 'igst': tax.igst, 'cgst': tax.cgst,
      'sgst': tax.sgst, 'cess': tax.cess, 'notes': notes,
    });
  }

  static Future<List<Map<String, Object?>>> listPeriodReviewItems(String returnPeriod) async {
    if (!RegExp(r'^\d{4}-(0[1-9]|1[0-2])$').hasMatch(returnPeriod)) {
      throw const FormatException('Return period must use YYYY-MM format.');
    }
    final db = await AppDatabase.instance.database;
    return db.rawQuery('''
      SELECT a.purchase_invoice_id, a.supplier_invoice_number,
             a.supplier_invoice_date, a.category, a.treatment,
             a.gstr2b_status, a.taxable_value, a.igst, a.cgst, a.sgst, a.cess,
             p.name AS supplier_name, p.gstin AS supplier_gstin
      FROM purchase_itc_assessments a
      JOIN invoices i ON i.id = a.purchase_invoice_id
      LEFT JOIN parties p ON p.id = i.party_id
      WHERE a.return_period = ?
        AND (a.treatment = 'pendingReview' OR a.gstr2b_status != 'matched')
      ORDER BY a.supplier_invoice_date, a.supplier_invoice_number
    ''', [returnPeriod]);
  }

  static Future<List<Map<String, Object?>>> listAdjustmentAuditTrail(String returnPeriod) async {
    if (!RegExp(r'^\d{4}-(0[1-9]|1[0-2])$').hasMatch(returnPeriod)) {
      throw const FormatException('Return period must use YYYY-MM format.');
    }
    final db = await AppDatabase.instance.database;
    return db.query(
      'gst_itc_adjustment_audit',
      where: 'return_period = ?',
      whereArgs: [returnPeriod],
      orderBy: 'changed_at DESC, id DESC',
    );
  }

  static Future<Gstr3bItcSummary> summarizePeriod(String returnPeriod) async {
    if (!RegExp(r'^\d{4}-(0[1-9]|1[0-2])$').hasMatch(returnPeriod)) {
      throw const FormatException('Return period must use YYYY-MM format.');
    }
    final db = await AppDatabase.instance.database;
    final rows = await db.rawQuery('''
      SELECT a.*, p.gstin AS supplier_gstin
      FROM purchase_itc_assessments a
      JOIN invoices i ON i.id = a.purchase_invoice_id
      LEFT JOIN parties p ON p.id = i.party_id
      WHERE a.return_period = ? ORDER BY a.purchase_invoice_id
    ''', [returnPeriod]);
    final entries = <Gstr3bItcEntry>[];
    for (final row in rows) {
      final gstin = (row['supplier_gstin'] as String? ?? '').trim().toUpperCase();
      final status = row['gstr2b_status'] as String? ?? 'pending_review';
      final rawTreatment = Gstr3bItcTreatment.values.firstWhere(
        (v) => v.name == row['treatment'],
        orElse: () => Gstr3bItcTreatment.pendingReview,
      );
      final gstinValid = RegExp(r'^[0-9]{2}[A-Z]{5}[0-9]{4}[A-Z][1-9A-Z]Z[0-9A-Z]$').hasMatch(gstin);
      final treatment = rawTreatment == Gstr3bItcTreatment.ineligible
          ? rawTreatment
          : status == 'matched' && gstinValid
              ? rawTreatment
              : Gstr3bItcTreatment.pendingReview;
      entries.add(Gstr3bItcEntry(
        documentReference: '$gstin|${row['supplier_invoice_number']}|${row['supplier_invoice_date']}',
        category: Gstr3bItcCategory.values.firstWhere((v) => v.name == row['category'], orElse: () => Gstr3bItcCategory.other),
        treatment: treatment,
        tax: Gstr3bTaxAmounts(
          igst: (row['igst'] as num).toDouble(), cgst: (row['cgst'] as num).toDouble(),
          sgst: (row['sgst'] as num).toDouble(), cess: (row['cess'] as num).toDouble(),
        ),
      ));
    }
    final adjustments = await db.query('gst_itc_adjustments',
      where: 'return_period = ?', whereArgs: [returnPeriod], orderBy: 'id');
    for (final row in adjustments) {
      entries.add(Gstr3bItcEntry(
        documentReference: 'ADJ|${row['id']}|${row['document_reference']}',
        category: Gstr3bItcCategory.other,
        treatment: Gstr3bItcTreatment.values.firstWhere((v) => v.name == row['treatment']),
        tax: Gstr3bTaxAmounts(
          igst: (row['igst'] as num).toDouble(), cgst: (row['cgst'] as num).toDouble(),
          sgst: (row['sgst'] as num).toDouble(), cess: (row['cess'] as num).toDouble(),
        ),
      ));
    }
    return Gstr3bItcCalculator.summarize(entries);
  }
}


class Gstr3bRcmValidator {
  Gstr3bRcmValidator._();

  static List<String> validateLiability({
    required String returnPeriod,
    required String documentReference,
    required double taxableValue,
    required Gstr3bTaxAmounts tax,
  }) {
    final issues = <String>[];
    if (!RegExp(r'^\d{4}-(0[1-9]|1[0-2])$').hasMatch(returnPeriod)) {
      issues.add('Return period must use YYYY-MM format.');
    }
    if (documentReference.trim().isEmpty) issues.add('RCM document reference is required.');
    if (!taxableValue.isFinite || taxableValue < 0) issues.add('Taxable value must be finite and non-negative.');
    if (!tax.isValid || tax.isZero) issues.add('RCM tax must contain at least one positive, valid tax amount.');
    return List.unmodifiable(issues);
  }

  static List<String> validatePayment({
    required String paymentDate,
    required String cashLedgerReference,
    required String challanReference,
    required Gstr3bTaxAmounts tax,
  }) {
    final issues = <String>[];
    final normalizedPaymentDate = _dateOnly(paymentDate);
    if (normalizedPaymentDate == null || normalizedPaymentDate != paymentDate.trim()) {
      issues.add('Payment date must be a valid calendar date in YYYY-MM-DD format.');
    }
    if (cashLedgerReference.trim().isEmpty) issues.add('Cash ledger reference is required.');
    if (challanReference.trim().isEmpty) issues.add('Challan reference is required.');
    if (!tax.isValid || tax.isZero) issues.add('Payment must contain at least one positive, valid tax amount.');
    return List.unmodifiable(issues);
  }
}

class Gstr3bRcmRepository {
  Gstr3bRcmRepository._();

  static Future<int> addLiability({
    required String returnPeriod,
    required String documentReference,
    String? supplierName,
    required double taxableValue,
    required Gstr3bTaxAmounts tax,
    String? notes,
  }) async {
    final issues = Gstr3bRcmValidator.validateLiability(
      returnPeriod: returnPeriod,
      documentReference: documentReference,
      taxableValue: taxableValue,
      tax: tax,
    );
    if (issues.isNotEmpty) throw FormatException(issues.join(' '));
    final db = await AppDatabase.instance.database;
    return db.insert('gst_rcm_liabilities', {
      'return_period': returnPeriod,
      'document_reference': documentReference.trim(),
      'supplier_name': supplierName?.trim(),
      'taxable_value': taxableValue,
      'igst': tax.igst, 'cgst': tax.cgst, 'sgst': tax.sgst, 'cess': tax.cess,
      'notes': notes,
    });
  }

  static Future<int> recordCashPayment({
    required int liabilityId,
    required String paymentDate,
    required String cashLedgerReference,
    required String challanReference,
    required Gstr3bTaxAmounts tax,
    String? notes,
  }) async {
    final issues = Gstr3bRcmValidator.validatePayment(
      paymentDate: paymentDate,
      cashLedgerReference: cashLedgerReference,
      challanReference: challanReference,
      tax: tax,
    );
    if (issues.isNotEmpty) throw FormatException(issues.join(' '));
    final db = await AppDatabase.instance.database;
    return db.transaction((txn) async {
      final rows = await txn.query('gst_rcm_liabilities',
        where: 'id = ?', whereArgs: [liabilityId], limit: 1);
      if (rows.isEmpty) throw StateError('RCM liability was not found.');
      final liability = rows.first;
      final paidRows = await txn.rawQuery('''
        SELECT COALESCE(SUM(igst), 0) AS igst,
               COALESCE(SUM(cgst), 0) AS cgst,
               COALESCE(SUM(sgst), 0) AS sgst,
               COALESCE(SUM(cess), 0) AS cess
        FROM gst_rcm_payments WHERE liability_id = ?
      ''', [liabilityId]);
      final paid = paidRows.first;
      bool exceeds(String key, double amount) =>
          amount > ((liability[key] as num).toDouble() -
              (paid[key] as num).toDouble()) + 0.005;
      if (exceeds('igst', tax.igst) || exceeds('cgst', tax.cgst) ||
          exceeds('sgst', tax.sgst) || exceeds('cess', tax.cess)) {
        throw StateError('Payment exceeds the outstanding RCM liability for one or more tax heads.');
      }
      return txn.insert('gst_rcm_payments', {
        'liability_id': liabilityId,
        'payment_date': DateTime.parse(paymentDate).toIso8601String().substring(0, 10),
        'cash_ledger_reference': cashLedgerReference.trim(),
        'challan_reference': challanReference.trim(),
        'igst': tax.igst, 'cgst': tax.cgst, 'sgst': tax.sgst, 'cess': tax.cess,
        'notes': notes,
      });
    });
  }

  static Future<List<Map<String, Object?>>> listPeriod(String returnPeriod) async {
    if (!RegExp(r'^\d{4}-(0[1-9]|1[0-2])$').hasMatch(returnPeriod)) {
      throw const FormatException('Return period must use YYYY-MM format.');
    }
    final db = await AppDatabase.instance.database;
    return db.rawQuery('''
      SELECT l.*,
        COALESCE(p.igst_paid, 0) AS igst_paid,
        COALESCE(p.cgst_paid, 0) AS cgst_paid,
        COALESCE(p.sgst_paid, 0) AS sgst_paid,
        COALESCE(p.cess_paid, 0) AS cess_paid,
        COALESCE(p.payment_count, 0) AS payment_count,
        COALESCE(p.payment_references, '') AS payment_references
      FROM gst_rcm_liabilities l
      LEFT JOIN (
        SELECT liability_id, SUM(igst) AS igst_paid, SUM(cgst) AS cgst_paid,
          SUM(sgst) AS sgst_paid, SUM(cess) AS cess_paid, COUNT(*) AS payment_count,
          GROUP_CONCAT(payment_date || ' • ' || cash_ledger_reference || ' • ' || challan_reference, char(10)) AS payment_references
        FROM gst_rcm_payments GROUP BY liability_id
      ) p ON p.liability_id = l.id
      WHERE l.return_period = ?
      ORDER BY l.id DESC
    ''', [returnPeriod]);
  }
}

String? _dateOnly(String value) {
  final normalized = value.trim();
  if (normalized.length < 10 ||
      normalized[4] != '-' ||
      normalized[7] != '-') {
    return null;
  }
  final year = int.tryParse(normalized.substring(0, 4));
  final month = int.tryParse(normalized.substring(5, 7));
  final day = int.tryParse(normalized.substring(8, 10));
  if (year == null || month == null || day == null) return null;
  final calendarDate = DateTime.utc(year, month, day);
  if (calendarDate.year != year ||
      calendarDate.month != month ||
      calendarDate.day != day) {
    return null;
  }
  if (normalized.length > 10) {
    final separator = normalized[10];
    if (separator != 'T' && separator != 't' && separator != ' ') {
      return null;
    }
    if (DateTime.tryParse(normalized) == null) return null;
  }
  return normalized.substring(0, 10);
}
