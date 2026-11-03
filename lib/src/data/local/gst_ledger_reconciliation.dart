import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Read-only reconciliation of GST control accounts with source documents.
class GstLedgerReconciliation {
  GstLedgerReconciliation._();

  static Future<Map<String, Object?>> load(
    DatabaseExecutor db, {
    String? startDate,
    String? endDate,
  }) async {
    final invoiceDate = _dateClause('i.invoice_date', startDate, endDate);
    final noteDate = _dateClause('dn.note_date', startDate, endDate);
    final journalDate = _dateClause('je.entry_date', startDate, endDate);

    final salesRows = await db.rawQuery('''
      SELECT
        COALESCE(SUM(CASE WHEN i.invoice_type='sale' THEN i.tax_total
          WHEN i.invoice_type='sales_return' THEN -i.tax_total ELSE 0 END),0) AS expected
      FROM invoices i
      WHERE i.invoice_type IN ('sale','sales_return')$invoiceDate
    ''', _dateArgs(startDate, endDate));
    final debitRows = await db.rawQuery('''
      SELECT COALESCE(SUM(dn.tax_total),0) AS expected
      FROM debit_notes dn WHERE dn.status='posted'$noteDate
    ''', _dateArgs(startDate, endDate));

    final purchaseRows = await db.rawQuery('''
      SELECT
        COALESCE(SUM(CASE
          WHEN i.invoice_type='purchase' AND a.treatment='eligible' THEN i.tax_total
          WHEN i.invoice_type='purchase_return' AND pa.treatment='eligible' THEN -i.tax_total
          ELSE 0 END),0) AS eligible,
        COALESCE(SUM(CASE
          WHEN i.invoice_type='purchase' AND COALESCE(a.treatment,'pendingReview') NOT IN ('eligible','ineligible') THEN i.tax_total
          WHEN i.invoice_type='purchase_return' AND COALESCE(pa.treatment,'pendingReview') NOT IN ('eligible','ineligible') THEN -i.tax_total
          ELSE 0 END),0) AS pending,
        SUM(CASE WHEN i.invoice_type='purchase' AND a.purchase_invoice_id IS NULL THEN 1 ELSE 0 END) AS missing_assessment
      FROM invoices i
      LEFT JOIN purchase_itc_assessments a
        ON a.purchase_invoice_id=i.id AND i.invoice_type='purchase'
      LEFT JOIN invoices original
        ON original.id=i.parent_invoice_id AND i.invoice_type='purchase_return'
      LEFT JOIN purchase_itc_assessments pa
        ON pa.purchase_invoice_id=original.id
      WHERE i.invoice_type IN ('purchase','purchase_return')$invoiceDate
    ''', _dateArgs(startDate, endDate));

    final outputExpected =
        (salesRows.single['expected'] as num).toDouble() +
        (debitRows.single['expected'] as num).toDouble();
    final eligibleExpected =
        (purchaseRows.single['eligible'] as num).toDouble();
    final pendingExpected =
        (purchaseRows.single['pending'] as num).toDouble();
    final missingAssessmentCount =
        (purchaseRows.single['missing_assessment'] as num?)?.toInt() ?? 0;

    Future<double> accountBalance(String code, {required bool creditNormal}) async {
      final rows = await db.rawQuery('''
        SELECT COALESCE(SUM(jl.${creditNormal ? 'credit-debit' : 'debit-credit'}),0) AS balance
        FROM journal_lines jl
        INNER JOIN journal_entries je ON je.id=jl.journal_entry_id
        INNER JOIN accounts a ON a.id=jl.account_id
        WHERE a.account_code=? AND je.status='posted'$journalDate
      ''', [code, ..._dateArgs(startDate, endDate)]);
      return (rows.single['balance'] as num).toDouble();
    }

    final outputControl = await accountBalance('2100', creditNormal: true);
    final eligibleControl = await accountBalance('1300', creditNormal: false);
    final pendingControl = await accountBalance('1310', creditNormal: false);

    final missingRows = await db.rawQuery('''
      SELECT COUNT(*) AS count, COALESCE(SUM(x.tax_amount),0) AS tax_amount
      FROM (
        SELECT id, tax_total AS tax_amount, invoice_date AS tx_date, 'sales_invoice' AS source_type
          FROM invoices WHERE invoice_type='sale'
        UNION ALL
        SELECT id, tax_total, invoice_date, 'sales_return' FROM invoices WHERE invoice_type='sales_return'
        UNION ALL
        SELECT id, tax_total, invoice_date, 'purchase_invoice' FROM invoices WHERE invoice_type='purchase'
        UNION ALL
        SELECT id, tax_total, invoice_date, 'purchase_return' FROM invoices WHERE invoice_type='purchase_return'
        UNION ALL
        SELECT id, tax_total, note_date, 'sales_debit_note' FROM debit_notes WHERE status='posted'
      ) x
      LEFT JOIN journal_entries je
        ON je.source_type=x.source_type AND je.source_id=x.id AND je.status='posted'
      WHERE je.id IS NULL ${_dateWhere('x.tx_date', startDate, endDate)}
    ''', _dateArgs(startDate, endDate));
    final missingJournalCount = (missingRows.single['count'] as num).toInt();
    final missingJournalTax =
        (missingRows.single['tax_amount'] as num).toDouble();

    final outputDifference = outputExpected - outputControl;
    final eligibleDifference = eligibleExpected - eligibleControl;
    final pendingDifference = pendingExpected - pendingControl;
    final allFinite = [
      outputExpected, eligibleExpected, pendingExpected, outputControl,
      eligibleControl, pendingControl, outputDifference, eligibleDifference,
      pendingDifference, missingJournalTax,
    ].every((value) => value.isFinite);

    return {
      'output_gst_expected': outputExpected,
      'output_gst_control': outputControl,
      'output_gst_difference': outputDifference,
      'eligible_itc_expected': eligibleExpected,
      'eligible_itc_control': eligibleControl,
      'eligible_itc_difference': eligibleDifference,
      'pending_itc_expected': pendingExpected,
      'pending_itc_control': pendingControl,
      'pending_itc_difference': pendingDifference,
      'missing_journal_count': missingJournalCount,
      'missing_journal_tax': missingJournalTax,
      'missing_assessment_count': missingAssessmentCount,
      'is_reconciled': allFinite &&
          outputDifference.abs() <= 0.01 &&
          eligibleDifference.abs() <= 0.01 &&
          pendingDifference.abs() <= 0.01 &&
          missingJournalCount == 0 &&
          missingAssessmentCount == 0,
    };
  }

  static String _dateClause(String column, String? start, String? end) =>
      _dateWhere(column, start, end);

  static String _dateWhere(String column, String? start, String? end) {
    final parts = <String>[];
    if (start != null) parts.add('$column >= ?');
    if (end != null) parts.add('$column <= ?');
    return parts.isEmpty ? '' : ' AND ${parts.join(' AND ')}';
  }

  static List<Object?> _dateArgs(String? start, String? end) => [
    if (start != null) start,
    if (end != null) end,
  ];
}
