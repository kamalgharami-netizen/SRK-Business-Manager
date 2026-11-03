import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Read-only comparison of customer party balances with Accounts Receivable.
class CustomerLedgerReconciliation {
  CustomerLedgerReconciliation._();

  static Future<Map<String, Object?>> load(DatabaseExecutor db, {String? asOfDate}) async {
    final invoiceCutoff = asOfDate == null ? '' : ' AND invoice_date <= ?';
    final paymentCutoff = asOfDate == null ? '' : ' AND payment_date <= ?';
    final allocationCutoff = asOfDate == null ? '' : ' AND a.allocation_date <= ?';
    final journalCutoff = asOfDate == null ? '' : ' AND je.entry_date <= ?';
    final missingDateClause = asOfDate == null ? '' : 'AND x.tx_date <= ?';
    final openingRows = asOfDate == null
        ? await db.rawQuery("SELECT COALESCE(SUM(CASE WHEN balance_type='receivable' THEN opening_balance ELSE 0 END),0) AS opening FROM parties")
        : await db.rawQuery("SELECT COALESCE(SUM(CASE WHEN balance_type='receivable' AND date(created_at) <= date(?) THEN opening_balance ELSE 0 END),0) AS opening FROM parties", [asOfDate]);
    final opening = (openingRows.single['opening'] as num).toDouble();
    final salesRows = await db.rawQuery("SELECT COALESCE(SUM(grand_total),0) AS total FROM invoices WHERE invoice_type='sale'$invoiceCutoff", asOfDate == null ? [] : [asOfDate]);
    final returnRows = await db.rawQuery("SELECT COALESCE(SUM(grand_total),0) AS total FROM invoices WHERE invoice_type='sales_return'$invoiceCutoff", asOfDate == null ? [] : [asOfDate]);
    final receiptRows = await db.rawQuery("SELECT COALESCE(SUM(amount),0) AS total FROM payments WHERE payment_type='receipt' AND invoice_id IS NOT NULL$paymentCutoff", asOfDate == null ? [] : [asOfDate]);
    final allocationRows = await db.rawQuery("SELECT COALESCE(SUM(a.amount),0) AS total FROM payment_allocations a INNER JOIN payments p ON p.id=a.payment_id WHERE p.payment_type='receipt' AND p.invoice_id IS NULL$allocationCutoff", asOfDate == null ? [] : [asOfDate]);
    final debitNotes = await db.rawQuery("SELECT COALESCE(SUM(grand_total),0) AS total FROM debit_notes WHERE status='posted'${asOfDate == null ? '' : ' AND note_date <= ?'}", asOfDate == null ? [] : [asOfDate]);
    final sales = (salesRows.single['total'] as num).toDouble();
    final returns = (returnRows.single['total'] as num).toDouble();
    final linkedReceipts = (receiptRows.single['total'] as num).toDouble();
    final advanceAllocations = (allocationRows.single['total'] as num).toDouble();
    final debitNoteTotal = (debitNotes.single['total'] as num).toDouble();
    final customerLedger = opening + sales - returns - linkedReceipts - advanceAllocations + debitNoteTotal;
    final advancePaymentRows = await db.rawQuery("SELECT COALESCE(SUM(amount),0) AS total FROM payments WHERE payment_type='receipt' AND invoice_id IS NULL$paymentCutoff", asOfDate == null ? [] : [asOfDate]);
    final customerAdvanceReceived = (advancePaymentRows.single['total'] as num).toDouble();
    final customerAdvanceLedger = customerAdvanceReceived - advanceAllocations;
    final controlRows = await db.rawQuery("SELECT COALESCE(SUM(jl.debit-jl.credit),0) AS balance FROM journal_lines jl INNER JOIN journal_entries je ON je.id=jl.journal_entry_id INNER JOIN accounts a ON a.id=jl.account_id WHERE a.account_code='1100' AND je.status='posted' AND je.source_type <> 'opening_balance'$journalCutoff", asOfDate == null ? [] : [asOfDate]);
    final controlBalance = opening + (controlRows.single['balance'] as num).toDouble();
    final unassignedRows = await db.rawQuery("SELECT COUNT(*) AS count, COALESCE(SUM(grand_total),0) AS total FROM invoices WHERE invoice_type IN ('sale','sales_return') AND party_id IS NULL$invoiceCutoff", asOfDate == null ? [] : [asOfDate]);
    final unassignedDebitNotes = await db.rawQuery("SELECT COUNT(*) AS count, COALESCE(SUM(grand_total),0) AS total FROM debit_notes WHERE status='posted' AND party_id IS NULL${asOfDate == null ? '' : ' AND note_date <= ?'}", asOfDate == null ? [] : [asOfDate]);
    final missingRows = await db.rawQuery("""
      SELECT COUNT(*) AS count, COALESCE(SUM(x.amount),0) AS amount
      FROM (
        SELECT id, grand_total AS amount, invoice_date AS tx_date, 'sales_invoice' AS source_type FROM invoices WHERE invoice_type='sale'
        UNION ALL SELECT id, grand_total, invoice_date, 'sales_return' FROM invoices WHERE invoice_type='sales_return'
        UNION ALL SELECT id, grand_total, note_date, 'sales_debit_note' FROM debit_notes WHERE status='posted'
        UNION ALL SELECT id, amount, payment_date, 'receipt' FROM payments WHERE payment_type='receipt'
        UNION ALL SELECT a.id, a.amount, a.allocation_date, 'advance_allocation' FROM payment_allocations a INNER JOIN payments p ON p.id=a.payment_id WHERE p.payment_type='receipt' AND p.invoice_id IS NULL
      ) x
      LEFT JOIN journal_entries je ON je.source_type=x.source_type AND je.source_id=x.id AND je.status='posted'
      WHERE je.id IS NULL $missingDateClause
    """, asOfDate == null ? [] : [asOfDate]);
    final advanceControlRows = await db.rawQuery("SELECT COALESCE(SUM(jl.credit-jl.debit),0) AS balance FROM journal_lines jl INNER JOIN journal_entries je ON je.id=jl.journal_entry_id INNER JOIN accounts a ON a.id=jl.account_id WHERE a.account_code='2200' AND je.status='posted'$journalCutoff", asOfDate == null ? [] : [asOfDate]);
    final customerAdvanceControl = (advanceControlRows.single['balance'] as num).toDouble();
    final advanceDifference = customerAdvanceLedger - customerAdvanceControl;
    final unassignedCount = (unassignedRows.single['count'] as num).toInt() + (unassignedDebitNotes.single['count'] as num).toInt();
    final unassignedTotal = (unassignedRows.single['total'] as num).toDouble() + (unassignedDebitNotes.single['total'] as num).toDouble();
    final missingCount = (missingRows.single['count'] as num).toInt();
    final difference = customerLedger - controlBalance;
    return {
      'opening_balance': opening, 'sales_total': sales, 'sales_return_total': returns,
      'linked_receipt_total': linkedReceipts, 'advance_allocation_total': advanceAllocations,
      'debit_note_total': debitNoteTotal, 'customer_ledger_balance': customerLedger,
      'control_account_balance': controlBalance, 'difference': difference,
      'unassigned_sales_count': unassignedCount, 'unassigned_sales_total': unassignedTotal,
      'missing_journal_count': missingCount, 'missing_journal_amount': (missingRows.single['amount'] as num).toDouble(),
      'customer_advance_received': customerAdvanceReceived, 'customer_advance_allocated': advanceAllocations,
      'customer_advance_ledger_balance': customerAdvanceLedger, 'customer_advance_control_balance': customerAdvanceControl,
      'customer_advance_difference': advanceDifference, 'is_customer_advance_reconciled': advanceDifference.abs() <= 0.01,
      'is_reconciled': difference.abs() <= 0.01 && unassignedCount == 0 && missingCount == 0,
    };
  }
}