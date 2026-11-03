import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Read-only comparison of supplier party balances with Accounts Payable.
class SupplierLedgerReconciliation {
  SupplierLedgerReconciliation._();

  static Future<Map<String, Object?>> load(DatabaseExecutor db, {String? asOfDate}) async {
    final invoiceCutoff = asOfDate == null ? '' : ' AND invoice_date <= ?';
    final paymentCutoff = asOfDate == null ? '' : ' AND payment_date <= ?';
    final allocationCutoff = asOfDate == null ? '' : ' AND allocation_date <= ?';
    final journalCutoff = asOfDate == null ? '' : ' AND je.entry_date <= ?';
    final missingDateClause = asOfDate == null ? '' : 'AND x.tx_date <= ?';

    final openingRows = await db.rawQuery("""
      SELECT COALESCE(SUM(CASE WHEN balance_type='payable' THEN opening_balance ELSE 0 END),0) AS opening
      FROM parties
    """);
    final opening = (openingRows.single['opening'] as num).toDouble();
    final purchaseRows = await db.rawQuery("SELECT COALESCE(SUM(grand_total),0) AS total FROM invoices WHERE invoice_type='purchase'$invoiceCutoff", asOfDate == null ? [] : [asOfDate]);
    final returnRows = await db.rawQuery("SELECT COALESCE(SUM(grand_total),0) AS total FROM invoices WHERE invoice_type='purchase_return'$invoiceCutoff", asOfDate == null ? [] : [asOfDate]);
    final paymentRows = await db.rawQuery("SELECT COALESCE(SUM(amount),0) AS total FROM payments WHERE payment_type='payment' AND invoice_id IS NOT NULL$paymentCutoff", asOfDate == null ? [] : [asOfDate]);
    final allocationRows = await db.rawQuery("""
      SELECT COALESCE(SUM(a.amount),0) AS total FROM payment_allocations a
      INNER JOIN payments p ON p.id=a.payment_id
      WHERE p.payment_type='payment'$allocationCutoff
    """, asOfDate == null ? [] : [asOfDate]);

    final purchases = (purchaseRows.single['total'] as num).toDouble();
    final returns = (returnRows.single['total'] as num).toDouble();
    final linkedPayments = (paymentRows.single['total'] as num).toDouble();
    final allocations = (allocationRows.single['total'] as num).toDouble();
    final partyBalance = opening + purchases - returns - linkedPayments - allocations;

    final controlRows = await db.rawQuery("""
      SELECT COALESCE(SUM(jl.credit-jl.debit),0) AS balance
      FROM journal_lines jl
      INNER JOIN journal_entries je ON je.id=jl.journal_entry_id
      INNER JOIN accounts a ON a.id=jl.account_id
      WHERE a.account_code='2000' AND je.status='posted'
        AND je.source_type <> 'opening_balance'$journalCutoff
    """, asOfDate == null ? [] : [asOfDate]);
    // Party opening balances are stored on party records, not in this journal movement total.
    final controlBalance = opening + (controlRows.single['balance'] as num).toDouble();

    final unassignedRows = await db.rawQuery(
      "SELECT COUNT(*) AS count, COALESCE(SUM(grand_total),0) AS total FROM invoices WHERE invoice_type='purchase' AND party_id IS NULL$invoiceCutoff",
      asOfDate == null ? [] : [asOfDate],
    );
    final missingRows = await db.rawQuery("""
      SELECT COUNT(*) AS count, COALESCE(SUM(x.amount),0) AS amount
      FROM (
        SELECT id, grand_total AS amount, invoice_date AS tx_date, 'purchase_invoice' AS source_type FROM invoices WHERE invoice_type='purchase'
        UNION ALL
        SELECT id, grand_total, invoice_date, 'purchase_return' FROM invoices WHERE invoice_type='purchase_return'
        UNION ALL
        SELECT id, amount, payment_date, 'payment' FROM payments WHERE payment_type='payment' AND invoice_id IS NOT NULL
        UNION ALL
        SELECT a.id, a.amount, a.allocation_date, 'advance_allocation'
        FROM payment_allocations a INNER JOIN payments p ON p.id=a.payment_id WHERE p.payment_type='payment'
      ) x
      LEFT JOIN journal_entries je ON je.source_type=x.source_type AND je.source_id=x.id AND je.status='posted'
      WHERE je.id IS NULL $missingDateClause
    """, asOfDate == null ? [] : [asOfDate]);

    final difference = partyBalance - controlBalance;
    final unassignedCount = (unassignedRows.single['count'] as num).toInt();
    final missingCount = (missingRows.single['count'] as num).toInt();
    return {
      'opening_balance': opening,
      'purchase_total': purchases,
      'purchase_return_total': returns,
      'linked_payment_total': linkedPayments,
      'advance_allocation_total': allocations,
      'supplier_ledger_balance': partyBalance,
      'control_account_balance': controlBalance,
      'difference': difference,
      'unassigned_purchase_count': unassignedCount,
      'unassigned_purchase_total': (unassignedRows.single['total'] as num).toDouble(),
      'missing_journal_count': missingCount,
      'missing_journal_amount': (missingRows.single['amount'] as num).toDouble(),
      'is_reconciled': difference.abs() <= 0.01 && unassignedCount == 0 && missingCount == 0,
    };
  }
}
