import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import '../../data/local/app_database.dart';
import '../../data/local/supplier_ledger_reconciliation.dart';
import '../../data/local/customer_ledger_reconciliation.dart';
import '../../data/local/inventory_valuation_reconciliation.dart';
import '../../data/local/gst_ledger_reconciliation.dart';
import '../../data/local/gst_rcm_reconciliation.dart';
import '../../data/local/gst_return_readiness.dart';
import '../../data/local/gst_gstr1_classification.dart';
import '../../data/local/gst_gstr1_hsn_summary.dart';
import '../../data/local/gst_gstr1_csv_export.dart';
import '../../data/local/gst_gstr1_invoice_csv_export.dart';
import '../../data/local/gst_gstr1_credit_note_audit.dart';
import '../../data/local/gst_gstr1_debit_note_audit.dart';
import '../../data/local/purchase_return_itc_audit_csv.dart';

class ReportsPage extends StatefulWidget {
  const ReportsPage({super.key, required this.reportType});
  final String reportType;
  @override
  State<ReportsPage> createState() => _ReportsPageState();
}

class _ReportsPageState extends State<ReportsPage> {
  bool _loading = true;
  Map<String, Object?> _summary = {};
  List<Map<String, Object?>> _rows = [];
  List<Map<String, Object?>> _gstBreakdownRows = [];
  int _gstMissingHsnCount = 0;
  List<Map<String, Object?>> _stockRows = [];
  double _stockValue = 0;
  bool _stockValueHasEstimates = false;
  List<Map<String, Object?>> _journalRows = [];
  double _trialDebit = 0;
  double _trialCredit = 0;
  double _profitIncome = 0;
  double _profitExpense = 0;
  List<Map<String, Object?>> _balanceSheetRows = [];
  double _balanceAssets = 0;
  double _balanceLiabilities = 0;
  double _balanceEquity = 0;
  Map<String, Object?> _supplierReconciliation = const {};
  Map<String, Object?> _customerReconciliation = const {};
  Map<String, Object?> _inventoryReconciliation = const {};
  Map<String, Object?> _gstLedgerReconciliation = const {};
  Map<String, Object?> _gstRcmReconciliation = const {};
  DateTime? _startDate;
  DateTime? _endDate;
  bool _gstr1Checking = false;
  GstReadinessReport? _gstr1ReadinessReport;
  Gstr1ClassificationSummary? _gstr1ClassificationSummary;
  List<Gstr1HsnRateSummary> _gstr1HsnSummary = const [];
  List<Map<String, Object?>> _gstr1CreditNoteRows = const [];
  List<Map<String, Object?>> _gstr1DebitNoteRows = const [];
  List<Map<String, Object?>> _gstr1PurchaseReturnRows = const [];

  @override
  void initState() { super.initState(); _load(); }

  String _date(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';

  Future<void> _pickDate({required bool isStart}) async {
    final initial = isStart
        ? (_startDate ?? _endDate ?? DateTime.now())
        : (_endDate ?? _startDate ?? DateTime.now());
    final picked = await showDatePicker(
      context: context, initialDate: initial,
      firstDate: DateTime(2000), lastDate: DateTime(2100),
    );
    if (picked == null || !mounted) return;
    setState(() {
      if (isStart) {
        _startDate = picked;
        if (_endDate != null && _endDate!.isBefore(picked)) _endDate = picked;
      } else {
        _endDate = picked;
        if (_startDate != null && picked.isBefore(_startDate!)) _startDate = picked;
      }
    });
    await _load();
  }

  Future<void> _load() async {
    if (mounted) setState(() => _loading = true);
    final db = await AppDatabase.instance.database;
    final where = <String>[];
    final args = <Object?>[];
    if (_startDate != null) {
      where.add('invoice_date >= ?');
      args.add(_date(_startDate!));
    }
    if (_endDate != null) {
      where.add('invoice_date < ?');
      args.add(_date(_endDate!.add(const Duration(days: 1))));
    }
    final dateClause = where.isEmpty ? '' : ' AND ${where.join(' AND ')}';
    final sales = await db.rawQuery(
      """
      SELECT
        COALESCE(SUM(CASE WHEN invoice_type = 'sale' THEN grand_total
                          WHEN invoice_type = 'sales_return' THEN -grand_total ELSE 0 END), 0) AS total,
        COALESCE(SUM(CASE WHEN invoice_type = 'sale' THEN tax_total
                          WHEN invoice_type = 'sales_return' THEN -tax_total ELSE 0 END), 0) AS tax,
        COALESCE(SUM(CASE WHEN invoice_type = 'sale' THEN cgst_total
                          WHEN invoice_type = 'sales_return' THEN -cgst_total ELSE 0 END), 0) AS cgst,
        COALESCE(SUM(CASE WHEN invoice_type = 'sale' THEN sgst_total
                          WHEN invoice_type = 'sales_return' THEN -sgst_total ELSE 0 END), 0) AS sgst,
        COALESCE(SUM(CASE WHEN invoice_type = 'sale' THEN igst_total
                          WHEN invoice_type = 'sales_return' THEN -igst_total ELSE 0 END), 0) AS igst,
        COUNT(CASE WHEN invoice_type = 'sale' THEN 1 END) AS count
      FROM invoices
      WHERE invoice_type IN ('sale', 'sales_return')$dateClause
      """,
      args,
    );
    final purchases = await db.rawQuery(
      """
      SELECT
        COALESCE(SUM(CASE WHEN invoice_type = 'purchase' THEN grand_total
                          WHEN invoice_type = 'purchase_return' THEN -grand_total ELSE 0 END), 0) AS total,
        COALESCE(SUM(CASE WHEN invoice_type = 'purchase' THEN tax_total
                          WHEN invoice_type = 'purchase_return' THEN -tax_total ELSE 0 END), 0) AS tax,
        COALESCE(SUM(CASE WHEN invoice_type = 'purchase' THEN cgst_total
                          WHEN invoice_type = 'purchase_return' THEN -cgst_total ELSE 0 END), 0) AS cgst,
        COALESCE(SUM(CASE WHEN invoice_type = 'purchase' THEN sgst_total
                          WHEN invoice_type = 'purchase_return' THEN -sgst_total ELSE 0 END), 0) AS sgst,
        COALESCE(SUM(CASE WHEN invoice_type = 'purchase' THEN igst_total
                          WHEN invoice_type = 'purchase_return' THEN -igst_total ELSE 0 END), 0) AS igst,
        COUNT(CASE WHEN invoice_type = 'purchase' THEN 1 END) AS count
      FROM invoices
      WHERE invoice_type IN ('purchase', 'purchase_return')$dateClause
      """,
      args,
    );
    final debitNoteDateWhere = <String>[];
    final debitNoteDateArgs = <Object?>[];
    if (_startDate != null) {
      debitNoteDateWhere.add('note_date >= ?');
      debitNoteDateArgs.add(_date(_startDate!));
    }
    if (_endDate != null) {
      debitNoteDateWhere.add('note_date < ?');
      debitNoteDateArgs.add(_date(_endDate!.add(const Duration(days: 1))));
    }
    final debitNoteDateClause = debitNoteDateWhere.isEmpty
        ? ''
        : ' AND ${debitNoteDateWhere.join(' AND ')}';
    final salesDebitNoteSummary = await db.rawQuery(
      '''
      SELECT COALESCE(SUM(grand_total), 0) AS total,
        COALESCE(SUM(taxable_value), 0) AS taxable,
        COALESCE(SUM(tax_total), 0) AS tax,
        COALESCE(SUM(cgst_total), 0) AS cgst,
        COALESCE(SUM(sgst_total), 0) AS sgst,
        COALESCE(SUM(igst_total), 0) AS igst,
        COUNT(*) AS count
      FROM debit_notes
      WHERE status = 'posted'$debitNoteDateClause
      ''',
      debitNoteDateArgs,
    );
    final gstBreakdownRows = await db.rawQuery("""
      SELECT COALESCE(NULLIF(ii.hsn_sac, ''), 'Not specified') AS hsn_sac,
        ii.gst_rate,
        COALESCE(SUM(CASE WHEN i.invoice_type = 'sale' THEN (ii.line_total - ii.tax_amount)
                          WHEN i.invoice_type = 'sales_return' THEN -(ii.line_total - ii.tax_amount) ELSE 0 END), 0) AS output_taxable,
        COALESCE(SUM(CASE WHEN i.invoice_type = 'sale' THEN ii.tax_amount
                          WHEN i.invoice_type = 'sales_return' THEN -ii.tax_amount ELSE 0 END), 0) AS output_tax,
        COALESCE(SUM(CASE WHEN i.invoice_type = 'purchase' THEN (ii.line_total - ii.tax_amount)
                          WHEN i.invoice_type = 'purchase_return' THEN -(ii.line_total - ii.tax_amount) ELSE 0 END), 0) AS input_taxable,
        COALESCE(SUM(CASE WHEN i.invoice_type = 'purchase' THEN ii.tax_amount
                          WHEN i.invoice_type = 'purchase_return' THEN -ii.tax_amount ELSE 0 END), 0) AS input_tax
      FROM invoice_items ii
      INNER JOIN invoices i ON i.id = ii.invoice_id
      WHERE i.invoice_type IN ('sale', 'sales_return', 'purchase', 'purchase_return')$dateClause
      GROUP BY COALESCE(NULLIF(ii.hsn_sac, ''), 'Not specified'), ii.gst_rate
      ORDER BY hsn_sac, ii.gst_rate
    """, args);
    final debitNoteGstRows = await db.rawQuery(
      '''
      SELECT COALESCE(NULLIF(di.hsn_sac, ''), 'Not specified') AS hsn_sac,
        di.gst_rate,
        SUM(di.taxable_value) AS output_taxable,
        SUM(di.tax_amount) AS output_tax
      FROM debit_note_items di
      INNER JOIN debit_notes d ON d.id = di.debit_note_id
      WHERE d.status = 'posted'$debitNoteDateClause
      GROUP BY COALESCE(NULLIF(di.hsn_sac, ''), 'Not specified'), di.gst_rate
      ''',
      debitNoteDateArgs,
    );
    for (final debitRow in debitNoteGstRows) {
      final index = gstBreakdownRows.indexWhere((row) =>
          row['hsn_sac'] == debitRow['hsn_sac'] &&
          (row['gst_rate'] as num).toDouble() ==
              (debitRow['gst_rate'] as num).toDouble());
      if (index < 0) {
        gstBreakdownRows.add({
          'hsn_sac': debitRow['hsn_sac'],
          'gst_rate': debitRow['gst_rate'],
          'output_taxable': debitRow['output_taxable'],
          'output_tax': debitRow['output_tax'],
          'input_taxable': 0.0,
          'input_tax': 0.0,
        });
      } else {
        final row = gstBreakdownRows[index];
        row['output_taxable'] =
            (row['output_taxable'] as num).toDouble() +
            (debitRow['output_taxable'] as num).toDouble();
        row['output_tax'] =
            (row['output_tax'] as num).toDouble() +
            (debitRow['output_tax'] as num).toDouble();
      }
    }
    final missingHsnRows = await db.rawQuery("""
      SELECT COUNT(*) AS total FROM invoice_items ii
      INNER JOIN invoices i ON i.id = ii.invoice_id
      WHERE i.invoice_type IN ('sale', 'purchase')
        AND (ii.hsn_sac IS NULL OR TRIM(ii.hsn_sac) = '')$dateClause
    """, args);
    final debitNoteMissingHsnRows = await db.rawQuery(
      '''
      SELECT COUNT(*) AS total
      FROM debit_note_items di
      INNER JOIN debit_notes d ON d.id = di.debit_note_id
      WHERE d.status = 'posted'
        AND (di.hsn_sac IS NULL OR TRIM(di.hsn_sac) = '')$debitNoteDateClause
      ''',
      debitNoteDateArgs,
    );
    final gstMissingHsnCount =
        (missingHsnRows.first['total'] as num).toInt() +
        (debitNoteMissingHsnRows.first['total'] as num).toInt();

    final expenseDateWhere = <String>[];
    final expenseDateArgs = <Object?>[];
    if (_startDate != null) {
      expenseDateWhere.add('expense_date >= ?');
      expenseDateArgs.add(_date(_startDate!));
    }
    if (_endDate != null) {
      expenseDateWhere.add('expense_date < ?');
      expenseDateArgs.add(_date(_endDate!.add(const Duration(days: 1))));
    }
    final expenseDateClause = expenseDateWhere.isEmpty
        ? ''
        : ' WHERE ${expenseDateWhere.join(' AND ')}';
    final expense = await db.rawQuery(
      'SELECT COALESCE(SUM(amount),0) AS total, COUNT(*) AS count FROM expenses$expenseDateClause',
      expenseDateArgs,
    );

    final paymentDateWhere = <String>[];
    final paymentDateArgs = <Object?>[];
    if (_startDate != null) {
      paymentDateWhere.add('payment_date >= ?');
      paymentDateArgs.add(_date(_startDate!));
    }
    if (_endDate != null) {
      paymentDateWhere.add('payment_date < ?');
      paymentDateArgs.add(_date(_endDate!.add(const Duration(days: 1))));
    }
    final paymentDateClause = paymentDateWhere.isEmpty
        ? ''
        : ' WHERE ${paymentDateWhere.join(' AND ')}';
    final payments = await db.rawQuery(
      "SELECT COALESCE(SUM(CASE WHEN payment_type='receipt' THEN amount ELSE 0 END),0) AS receipts, COALESCE(SUM(CASE WHEN payment_type='payment' THEN amount ELSE 0 END),0) AS payments FROM payments$paymentDateClause",
      paymentDateArgs,
    );
    final stockRows = await db.rawQuery("""
      SELECT p.id, p.name, p.current_stock, p.unit, p.purchase_price,
        COALESCE(c.remaining_value, 0) AS fifo_value,
        COALESCE(c.estimated_quantity, 0) AS estimated_quantity
      FROM products p
      LEFT JOIN (
        SELECT product_id, SUM(quantity_remaining * unit_cost) AS remaining_value,
          SUM(CASE WHEN is_estimated = 1 THEN quantity_remaining ELSE 0 END) AS estimated_quantity
        FROM inventory_cost_layers
        WHERE quantity_remaining > 0
        GROUP BY product_id
      ) c ON c.product_id = p.id
      WHERE (p.is_service = 0 OR p.is_service IS NULL)
        AND p.current_stock > 0
      ORDER BY p.name COLLATE NOCASE
    """);
    final stockValue = stockRows.fold<double>(
      0,
      (total, row) => total + (row['fifo_value'] as num).toDouble(),
    );
    final stockValueHasEstimates = stockRows.any(
      (row) => (row['estimated_quantity'] as num).toDouble() > 0,
    );
    final partyRows = await db.rawQuery("""
      SELECT p.id, p.name, p.party_type,
        COALESCE((SELECT SUM(i.grand_total - i.amount_paid) FROM invoices i WHERE i.party_id=p.id AND i.invoice_type='sale'),0)
          - COALESCE((SELECT SUM(i.grand_total) FROM invoices i WHERE i.party_id=p.id AND i.invoice_type='sales_return'),0)
          + COALESCE((SELECT SUM(d.grand_total) FROM debit_notes d WHERE d.party_id=p.id AND d.status='posted'),0)
          - COALESCE((SELECT SUM(pm.amount) FROM payments pm WHERE pm.party_id=p.id AND pm.payment_type='receipt' AND pm.invoice_id IS NULL),0)
          + CASE WHEN p.balance_type='receivable' THEN COALESCE(p.opening_balance,0) ELSE 0 END AS receivable,
        COALESCE((SELECT SUM(i.grand_total - i.amount_paid) FROM invoices i WHERE i.party_id=p.id AND i.invoice_type='purchase'),0)
          - COALESCE((SELECT SUM(i.grand_total) FROM invoices i WHERE i.party_id=p.id AND i.invoice_type='purchase_return'),0)
          - COALESCE((SELECT SUM(pm.amount) FROM payments pm WHERE pm.party_id=p.id AND pm.payment_type='payment' AND pm.invoice_id IS NULL),0)
          + CASE WHEN p.balance_type='payable' THEN COALESCE(p.opening_balance,0) ELSE 0 END AS payable
      FROM parties p ORDER BY p.name COLLATE NOCASE
    """);
    final journalDateWhere = <String>[];
    final journalDateArgs = <Object?>[];
    // Trial Balance and Balance Sheet are point-in-time reports: include all
    // posted entries up to the selected end date, not only movements inside
    // the selected period. Profit & Loss uses the complete selected date range.
    final pointInTimeReport = widget.reportType == 'Trial Balance' ||
        widget.reportType == 'Balance Sheet';
    if (!pointInTimeReport && _startDate != null) {
      journalDateWhere.add('je.entry_date >= ?');
      journalDateArgs.add(_date(_startDate!));
    }
    if (_endDate != null) {
      journalDateWhere.add('je.entry_date < ?');
      journalDateArgs.add(_date(_endDate!.add(const Duration(days: 1))));
    }
    final journalDateClause = journalDateWhere.isEmpty
        ? ''
        : ' AND ${journalDateWhere.join(' AND ')}';
    final journalRows = await db.rawQuery("""
      SELECT a.id, a.account_code, a.account_name, a.account_type,
        COALESCE(j.total_debit, 0) AS total_debit,
        COALESCE(j.total_credit, 0) AS total_credit
      FROM accounts a
      LEFT JOIN (
        SELECT jl.account_id, SUM(jl.debit) AS total_debit,
          SUM(jl.credit) AS total_credit
        FROM journal_lines jl
        INNER JOIN journal_entries je ON je.id = jl.journal_entry_id
        WHERE je.status = 'posted'$journalDateClause
        GROUP BY jl.account_id
      ) j ON j.account_id = a.id
      WHERE a.is_active = 1
      ORDER BY a.account_code
    """, journalDateArgs);

    // Party opening balances are stored on party records rather than journal
    // entries. Include receivables/payables and balance them through equity.
    final openingDateRows = await db.query(
      'app_settings',
      columns: ['setting_value'],
      where: 'setting_key = ?',
      whereArgs: ['opening_balance_date'],
      limit: 1,
    );
    String? openingBalanceDate = openingDateRows.isNotEmpty
        ? openingDateRows.first['setting_value'] as String
        : null;
    if (openingBalanceDate == null) {
      final legacyOpeningDate = await db.rawQuery("""
        SELECT MIN(entry_date) AS opening_date
        FROM journal_entries
        WHERE source_type = 'opening_balance' AND status = 'posted'
      """);
      final legacyValue = legacyOpeningDate.first['opening_date'] as String?;
      if (legacyValue != null) {
        openingBalanceDate = legacyValue.substring(0, 10);
      } else {
        final firstPartyOpening = await db.rawQuery("""
          SELECT MIN(created_at) AS opening_date
          FROM parties
          WHERE opening_balance > 0
        """);
        final partyValue = firstPartyOpening.first['opening_date'] as String?;
        if (partyValue != null) openingBalanceDate = partyValue.substring(0, 10);
      }
    }
    final includePartyOpeningBalances = _endDate == null ||
        openingBalanceDate == null ||
        openingBalanceDate.compareTo(_date(_endDate!)) <= 0;
    final openingBalances = includePartyOpeningBalances
        ? await db.rawQuery("""
            SELECT
              COALESCE(SUM(CASE WHEN balance_type = 'receivable' THEN opening_balance ELSE 0 END), 0) AS receivable,
              COALESCE(SUM(CASE WHEN balance_type = 'payable' THEN opening_balance ELSE 0 END), 0) AS payable
            FROM parties
          """)
        : [
            {'receivable': 0, 'payable': 0}
          ];
    final openingReceivable =
        (openingBalances.first['receivable'] as num).toDouble();
    final openingPayable =
        (openingBalances.first['payable'] as num).toDouble();

    Map<String, Object?>? accountRow(String code) {
      for (final row in journalRows) {
        if (row['account_code'] == code) return row;
      }
      return null;
    }

    void addOpeningAmount(String code, {double debit = 0, double credit = 0}) {
      final row = accountRow(code);
      if (row == null) return;
      row['total_debit'] =
          (row['total_debit'] as num).toDouble() + debit;
      row['total_credit'] =
          (row['total_credit'] as num).toDouble() + credit;
    }

    addOpeningAmount('1100', debit: openingReceivable);
    addOpeningAmount('2000', credit: openingPayable);
    final openingEquityOffset = openingReceivable - openingPayable;
    if (openingEquityOffset >= 0) {
      addOpeningAmount('3200', credit: openingEquityOffset);
    } else {
      addOpeningAmount('3200', debit: -openingEquityOffset);
    }

    double trialDebit = 0;
    double trialCredit = 0;
    double profitIncome = 0;
    double profitExpense = 0;
    double balanceAssets = 0;
    double balanceLiabilities = 0;
    double balanceEquity = 0;
    final balanceSheetRows = <Map<String, Object?>>[];
    for (final row in journalRows) {
      final debit = (row['total_debit'] as num).toDouble();
      final credit = (row['total_credit'] as num).toDouble();
      final difference = debit - credit;
      if (difference > 0) trialDebit += difference;
      if (difference < 0) trialCredit += -difference;
      if (row['account_type'] == 'income') profitIncome += -difference;
      if (row['account_type'] == 'expense') profitExpense += difference;
      final type = row['account_type'];
      final balance = type == 'asset' || type == 'expense' ? difference : -difference;
      if (type == 'asset') {
        balanceAssets += balance;
        balanceSheetRows.add({...row, 'balance': balance});
      } else if (type == 'liability') {
        balanceLiabilities += balance;
        balanceSheetRows.add({...row, 'balance': balance});
      } else if (type == 'equity') {
        balanceEquity += balance;
        balanceSheetRows.add({...row, 'balance': balance});
      }
    }
    final supplierReconciliation = await SupplierLedgerReconciliation.load(
      db,
      asOfDate: _endDate == null ? null : _date(_endDate!),
    );
    final customerReconciliation = await CustomerLedgerReconciliation.load(
      db,
      asOfDate: _endDate == null ? null : _date(_endDate!),
    );
    final inventoryReconciliation =
        await InventoryValuationReconciliation.load(db);
    final gstRcmReconciliation = await GstRcmReconciliation.load(
      db,
      startDate: _startDate == null ? null : _date(_startDate!),
      endDate: _endDate == null ? null : _date(_endDate!),
    );
    final gstLedgerReconciliation = await GstLedgerReconciliation.load(
      db,
      startDate: widget.reportType == 'GST Reports' && _startDate != null
          ? _date(_startDate!)
          : null,
      endDate: _endDate == null ? null : _date(_endDate!),
    );

    final currentPeriodEarnings = profitIncome - profitExpense;
    if (!mounted) return;
    setState(() {
      _summary = {
        'sales': (sales.first['total'] as num).toDouble() + (salesDebitNoteSummary.first['total'] as num).toDouble(),
        'salesTax': (sales.first['tax'] as num).toDouble() + (salesDebitNoteSummary.first['tax'] as num).toDouble(),
        'salesCgst': (sales.first['cgst'] as num).toDouble() + (salesDebitNoteSummary.first['cgst'] as num).toDouble(),
        'salesSgst': (sales.first['sgst'] as num).toDouble() + (salesDebitNoteSummary.first['sgst'] as num).toDouble(),
        'salesIgst': (sales.first['igst'] as num).toDouble() + (salesDebitNoteSummary.first['igst'] as num).toDouble(),
        'salesCount': sales.first['count'],
        'salesDebitNoteCount': salesDebitNoteSummary.first['count'],
        'salesDebitNoteTotal': salesDebitNoteSummary.first['total'],
        'purchases': purchases.first['total'],
        'purchaseTax': purchases.first['tax'], 'purchaseCgst': purchases.first['cgst'], 'purchaseSgst': purchases.first['sgst'], 'purchaseIgst': purchases.first['igst'], 'purchaseCount': purchases.first['count'],
        'expenses': expense.first['total'], 'expenseCount': expense.first['count'],
        'receipts': payments.first['receipts'], 'payments': payments.first['payments'],
      };
      _rows = partyRows;
      _gstBreakdownRows = gstBreakdownRows;
      _gstMissingHsnCount = gstMissingHsnCount;
      _stockRows = stockRows;
      _stockValue = stockValue;
      _stockValueHasEstimates = stockValueHasEstimates;
      _journalRows = journalRows;
      _trialDebit = trialDebit;
      _trialCredit = trialCredit;
      _profitIncome = profitIncome;
      _profitExpense = profitExpense;
      _balanceSheetRows = balanceSheetRows;
      _balanceAssets = balanceAssets;
      _balanceLiabilities = balanceLiabilities;
      _balanceEquity = balanceEquity + currentPeriodEarnings;
      _supplierReconciliation = supplierReconciliation;
      _customerReconciliation = customerReconciliation;
      _inventoryReconciliation = inventoryReconciliation;
      _gstLedgerReconciliation = gstLedgerReconciliation;
      _gstRcmReconciliation = gstRcmReconciliation;
      _loading = false;
    });
  }

  Future<void> _checkGstr1Readiness() async {
    if (_startDate == null || _endDate == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('GSTR-1 preflight-এর আগে From date এবং To date নির্বাচন করুন।')),
      );
      return;
    }
    setState(() {
      _gstr1Checking = true;
      _gstr1ReadinessReport = null;
      _gstr1ClassificationSummary = null;
      _gstr1CreditNoteRows = const [];
      _gstr1DebitNoteRows = const [];
    });
    try {
      final db = await AppDatabase.instance.database;
      final settingRows = await db.query(
        'app_settings',
        columns: ['setting_key', 'setting_value'],
        where: 'setting_key IN (?, ?)',
        whereArgs: ['company_gstin', 'company_state'],
      );
      final settings = {
        for (final row in settingRows)
          row['setting_key'] as String: row['setting_value'] as String,
      };
      final invoiceRows = await db.rawQuery(
        '''
        SELECT i.id, i.invoice_number, i.invoice_date, i.place_of_supply,
          i.grand_total, i.tax_total, i.cgst_total, i.sgst_total, i.igst_total,
          p.gstin AS party_gstin, p.state AS party_state
        FROM invoices i
        LEFT JOIN parties p ON p.id = i.party_id
        WHERE i.invoice_type = 'sale'
          AND i.invoice_date >= ? AND i.invoice_date < ?
        ORDER BY i.invoice_date, i.invoice_number
        ''',
        [_date(_startDate!), _date(_endDate!.add(const Duration(days: 1)))],
      );
      final creditNoteRows = await db.rawQuery(
        '''
        SELECT r.invoice_number AS note_number,
          o.invoice_number AS original_invoice_number,
          r.invoice_date AS note_date,
          r.subtotal AS taxable_value,
          r.tax_total AS tax_amount,
          r.grand_total AS note_value,
          r.cgst_total AS cgst_amount,
          r.sgst_total AS sgst_amount,
          r.igst_total AS igst_amount,
          CASE WHEN r.parent_invoice_id IS NULL OR o.id IS NULL
            THEN 'MISSING_ORIGINAL_INVOICE_LINK'
            ELSE 'MANUAL_GST_REVIEW_REQUIRED' END AS review_status
        FROM invoices r
        LEFT JOIN invoices o ON o.id = r.parent_invoice_id
        WHERE r.invoice_type = 'sales_return'
          AND r.invoice_date >= ? AND r.invoice_date < ?
        ORDER BY r.invoice_date, r.invoice_number
        ''',
        [_date(_startDate!), _date(_endDate!.add(const Duration(days: 1)))],
      );
      final debitNoteRows = await db.rawQuery(
        '''
        SELECT d.debit_note_number AS note_number,
          i.invoice_number AS original_invoice_number,
          d.note_date AS note_date,
          d.reason AS reason,
          p.name AS party_name,
          p.gstin AS party_gstin,
          d.place_of_supply AS place_of_supply,
          d.taxable_value AS taxable_value,
          d.tax_total AS tax_amount,
          d.grand_total AS note_value,
          d.cgst_total AS cgst_amount,
          d.sgst_total AS sgst_amount,
          d.igst_total AS igst_amount,
          CASE
            WHEN i.id IS NULL THEN 'MISSING_ORIGINAL_INVOICE_LINK'
            WHEN d.party_id IS NOT i.party_id THEN 'RECIPIENT_LINK_REVIEW_REQUIRED'
            ELSE 'MANUAL_GST_REVIEW_REQUIRED'
          END AS review_status
        FROM debit_notes d
        LEFT JOIN invoices i ON i.id = d.original_invoice_id AND i.invoice_type = 'sale'
        LEFT JOIN parties p ON p.id = d.party_id
        WHERE d.status = 'posted'
          AND d.note_date >= ? AND d.note_date < ?
        ORDER BY d.note_date, d.debit_note_number
        ''',
        [_date(_startDate!), _date(_endDate!.add(const Duration(days: 1)))],
      );
      final purchaseReturnRows = await db.rawQuery(
        '''
        SELECT r.invoice_number AS return_number,
          o.invoice_number AS original_invoice_number,
          r.invoice_date AS return_date,
          r.subtotal AS taxable_value,
          r.tax_total AS tax_amount,
          r.grand_total AS return_value,
          r.cgst_total AS cgst_amount,
          r.sgst_total AS sgst_amount,
          r.igst_total AS igst_amount,
          CASE
            WHEN r.parent_invoice_id IS NULL OR o.id IS NULL
              THEN 'MISSING_ORIGINAL_PURCHASE_LINK'
            WHEN r.party_id IS NULL OR o.party_id IS NULL OR r.party_id != o.party_id
              THEN 'PURCHASE_PARTY_LINK_REVIEW_REQUIRED'
            WHEN date(r.invoice_date) < date(o.invoice_date)
              THEN 'RETURN_DATE_PRECEDES_PURCHASE_REVIEW'
            ELSE 'MANUAL_ITC_REVERSAL_REVIEW_REQUIRED'
          END AS review_status
        FROM invoices r
        LEFT JOIN invoices o ON o.id = r.parent_invoice_id AND o.invoice_type = 'purchase'
        WHERE r.invoice_type = 'purchase_return'
          AND r.invoice_date >= ? AND r.invoice_date < ?
        ORDER BY r.invoice_date, r.invoice_number
        ''',
        [_date(_startDate!), _date(_endDate!.add(const Duration(days: 1)))],
      );
      final financialYearStartYear =
          _startDate!.month >= 4 ? _startDate!.year : _startDate!.year - 1;
      final financialYearInvoiceRows = await db.rawQuery(
        '''
        SELECT invoice_number
        FROM invoices
        WHERE invoice_type = 'sale'
          AND invoice_date >= ? AND invoice_date < ?
        ''',
        [
          _date(DateTime(financialYearStartYear, 4, 1)),
          _date(DateTime(financialYearStartYear + 1, 4, 1)),
        ],
      );
      final financialYearInvoiceNumbers = financialYearInvoiceRows
          .map((row) => row['invoice_number'] as String? ?? '')
          .toList(growable: false);
      final invoices = <Map<String, Object?>>[];
      for (final invoice in invoiceRows) {
        final itemRows = await db.rawQuery(
          '''
          SELECT hsn_sac, gst_rate, line_total, tax_amount, cgst_amount, sgst_amount, igst_amount
          FROM invoice_items
          WHERE invoice_id = ?
          ORDER BY id
          ''',
          [invoice['id']],
        );
        final taxableValue = itemRows.fold<double>(0, (sum, item) => sum + (((item['line_total'] as num?)?.toDouble() ?? 0) - ((item['tax_amount'] as num?)?.toDouble() ?? 0)));
        final taxAmount = itemRows.fold<double>(0, (sum, item) => sum + ((item['tax_amount'] as num?)?.toDouble() ?? 0));
        invoices.add({...invoice, 'items': itemRows, 'invoice_value': invoice['grand_total'], 'taxable_value': taxableValue, 'tax_amount': taxAmount});
      }
      final report = GstReturnReadiness.validateGstr1(
        supplierGstin: settings['company_gstin'] ?? '',
        supplierState: settings['company_state'] ?? '',
        periodStart: _startDate!,
        periodEnd: _endDate!,
        invoices: invoices,
        financialYearInvoiceNumbers: financialYearInvoiceNumbers,
      );
      final classification = Gstr1DomesticClassifier.classify(invoices, supplierState: settings['company_state'] ?? '', returnPeriod: DateTime(_startDate!.year, _startDate!.month));
      final hsnRows = await db.rawQuery(
        '''
        SELECT i.invoice_number, ii.hsn_sac, ii.gst_rate, ii.quantity, ii.unit,
          ii.line_total, ii.tax_amount, ii.cgst_amount, ii.sgst_amount, ii.igst_amount
        FROM invoice_items ii
        INNER JOIN invoices i ON i.id = ii.invoice_id
        WHERE i.invoice_type = 'sale'
          AND i.invoice_date >= ? AND i.invoice_date < ?
        ORDER BY i.invoice_number, ii.hsn_sac, ii.gst_rate
        ''',
        [_date(_startDate!), _date(_endDate!.add(const Duration(days: 1)))],
      );
      final categoryByInvoice = {
        for (final item in classification.invoices)
          item.invoiceNumber.toUpperCase(): switch (item.category) {
            Gstr1SupplyCategory.b2b => 'B2B',
            Gstr1SupplyCategory.b2cl || Gstr1SupplyCategory.b2cs => 'B2C',
            Gstr1SupplyCategory.review => 'REVIEW',
          },
      };
      final categorizedHsnRows = hsnRows.map((row) => {
        ...row,
        'supply_category': categoryByInvoice[
              (row['invoice_number'] as String? ?? '').trim().toUpperCase()
            ] ?? 'REVIEW',
      }).toList(growable: false);
      final hsnSummary = Gstr1HsnRateAggregator.aggregate(categorizedHsnRows);
      if (!mounted) return;
      setState(() { _gstr1ReadinessReport = report; _gstr1ClassificationSummary = classification; _gstr1HsnSummary = hsnSummary; _gstr1CreditNoteRows = creditNoteRows; _gstr1DebitNoteRows = debitNoteRows; _gstr1PurchaseReturnRows = purchaseReturnRows; });
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('GSTR-1 preflight চালানো যায়নি: $error')),
      );
    } finally {
      if (mounted) setState(() => _gstr1Checking = false);
    }
  }

  Widget _gstr1ReadinessCard() {
    final report = _gstr1ReadinessReport;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('GSTR-1 প্রস্তুতি যাচাই', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 6),
            const Text('নির্বাচিত সময়ের বিক্রয় চালানে GSTIN, তারিখ, Place of Supply, HSN/SAC এবং করের তথ্যের প্রাথমিক পরীক্ষা।'),
            const SizedBox(height: 10),
            FilledButton.icon(
              onPressed: _gstr1Checking ? null : _checkGstr1Readiness,
              icon: _gstr1Checking
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.fact_check),
              label: Text(_gstr1Checking ? 'যাচাই চলছে…' : 'GSTR-1 প্রস্তুতি যাচাই করুন'),
            ),
            if (report != null) ...[
              const SizedBox(height: 10),
              Text('ত্রুটি: ${report.errorCount} • সতর্কতা: ${report.warningCount}',
                style: const TextStyle(fontWeight: FontWeight.bold)),
              for (final issue in report.issues)
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    issue.severity == GstReadinessSeverity.error
                        ? Icons.error_outline
                        : Icons.warning_amber_outlined,
                    color: issue.severity == GstReadinessSeverity.error
                        ? Colors.red
                        : Colors.orange,
                  ),
                  title: Text(issue.message),
                  subtitle: Text(issue.code),
                ),
              Text(
                report.canPrepareDraft
                    ? 'প্রাথমিক যাচাইয়ে বাধাদানকারী ত্রুটি পাওয়া যায়নি। এটি GSTN-এ জমা দেওয়ার অনুমোদন বা ফাইলিং-রেডি রিটার্ন নয়।'
                    : 'ত্রুটিগুলি সংশোধন করে আবার যাচাই করুন। এই ফলাফল GSTN-এ জমা দেওয়ার অনুমোদন নয়।',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _gstr1ClassificationCard() {
    final summary = _gstr1ClassificationSummary;
    if (summary == null) return const SizedBox.shrink();
    final categories = <(Gstr1SupplyCategory, String)>[
      (Gstr1SupplyCategory.b2b, 'B2B — নিবন্ধিত ক্রেতা'),
      (Gstr1SupplyCategory.b2cl, 'B2CL — আন্তঃরাজ্য, ₹১ লক্ষের বেশি'),
      (Gstr1SupplyCategory.b2cs, 'B2CS — অন্যান্য অনিবন্ধিত'),
      (Gstr1SupplyCategory.review, 'পর্যালোচনা প্রয়োজন'),
    ];
    return Card(child: Padding(padding: const EdgeInsets.all(12), child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text('GSTR-1 চালান শ্রেণিবিন্যাস', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 6),
        OutlinedButton.icon(
          onPressed: summary.invoices.isEmpty ? null : _exportGstr1InvoiceCsv,
          icon: const Icon(Icons.download),
          label: const Text('চালান-ভিত্তিক CSV রপ্তানি করুন'),
        ),
        const SizedBox(height: 6),
        for (final entry in categories)
          ListTile(dense: true, contentPadding: EdgeInsets.zero,
            title: Text(entry.$2),
            subtitle: Text('চালান: ${summary.count(entry.$1)} • করযোগ্য মূল্য: ${_money(summary.taxableValue(entry.$1))} • GST: ${_money(summary.taxAmount(entry.$1))}'),
            trailing: Text(_money(summary.invoiceValue(entry.$1)), style: const TextStyle(fontWeight: FontWeight.bold)),
          ),
        const Text('এই শ্রেণিবিন্যাস কেবল সংরক্ষিত domestic sale invoice-এর প্রাথমিক B2B/B2C বিভাজন। Export, SEZ, deemed export, credit/debit note, advance, e-commerce এবং অন্যান্য বিশেষ GSTR-1 টেবিল এতে অন্তর্ভুক্ত নয়। এটি GSTN upload JSON বা filing-ready return নয়।'),
      ],
    )));
  }
  Future<void> _exportGstr1InvoiceCsv() async {
    final summary = _gstr1ClassificationSummary;
    if (summary == null || summary.invoices.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('রপ্তানির জন্য চালানের তথ্য পাওয়া যায়নি।')),
      );
      return;
    }
    try {
      final db = await AppDatabase.instance.database;
      final rows = await db.query(
        'app_settings', columns: ['setting_value'],
        where: 'setting_key = ?', whereArgs: ['company_gstin'], limit: 1,
      );
      final gstin = rows.isEmpty ? '' : (rows.first['setting_value'] as String? ?? '');
      final content = Gstr1InvoiceCsvExport.build(
        summary, supplierGstin: gstin,
        periodStart: _startDate == null ? 'শুরু থেকে' : _date(_startDate!),
        periodEnd: _endDate == null ? 'সর্বশেষ তারিখ' : _date(_endDate!),
      );
      final stamp = DateTime.now().toIso8601String().substring(0, 10);
      final savedPath = await FilePicker.platform.saveFile(
        dialogTitle: 'GSTR-1 চালান-ভিত্তিক CSV সংরক্ষণ করুন',
        fileName: 'gstr1-invoice-summary-$stamp.csv',
        type: FileType.custom, allowedExtensions: ['csv'],
        bytes: Uint8List.fromList(utf8.encode(content)),
      );
      if (!mounted || savedPath == null) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('চালান-ভিত্তিক CSV সংরক্ষণের প্রক্রিয়া সম্পন্ন হয়েছে।')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('চালান-ভিত্তিক CSV রপ্তানি করা যায়নি: $error')),
      );
    }
  }

  Future<void> _exportGstr1HsnCsv() async {
    if (_gstr1ClassificationSummary == null || _gstr1HsnSummary.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('রপ্তানির জন্য HSN/SAC সারাংশ পাওয়া যায়নি।')),
      );
      return;
    }
    try {
      final db = await AppDatabase.instance.database;
      final rows = await db.query(
        'app_settings', columns: ['setting_value'],
        where: 'setting_key = ?', whereArgs: ['company_gstin'], limit: 1,
      );
      final gstin = rows.isEmpty ? '' : (rows.first['setting_value'] as String? ?? '');
      final start = _startDate == null ? 'শুরু থেকে' : _date(_startDate!);
      final end = _endDate == null ? 'সর্বশেষ তারিখ' : _date(_endDate!);
      final content = Gstr1HsnCsvExport.build(
        _gstr1HsnSummary, supplierGstin: gstin,
        periodStart: start, periodEnd: end,
      );
      final stamp = DateTime.now().toIso8601String().substring(0, 10);
      final savedPath = await FilePicker.platform.saveFile(
        dialogTitle: 'GSTR-1 HSN/SAC CSV সংরক্ষণ করুন',
        fileName: 'gstr1-hsn-summary-$stamp.csv',
        type: FileType.custom, allowedExtensions: ['csv'],
        bytes: Uint8List.fromList(utf8.encode(content)),
      );
      if (!mounted || savedPath == null) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('CSV ফাইল সংরক্ষণের প্রক্রিয়া সম্পন্ন হয়েছে।')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('CSV রপ্তানি করা যায়নি: $error')),
      );
    }
  }

  Future<void> _exportGstr1CreditNoteAudit() async {
    if (_gstr1CreditNoteRows.isEmpty) return;
    try {
      final db = await AppDatabase.instance.database;
      final rows = await db.query(
        'app_settings', columns: ['setting_value'],
        where: 'setting_key = ?', whereArgs: ['company_gstin'], limit: 1,
      );
      final gstin = rows.isEmpty ? '' : (rows.first['setting_value'] as String? ?? '');
      final content = Gstr1CreditNoteAuditCsv.build(
        _gstr1CreditNoteRows,
        supplierGstin: gstin,
        periodStart: _date(_startDate!),
        periodEnd: _date(_endDate!),
      );
      final stamp = DateTime.now().toIso8601String().substring(0, 10);
      final savedPath = await FilePicker.platform.saveFile(
        dialogTitle: 'Credit Note audit CSV সংরক্ষণ করুন',
        fileName: 'gstr1-credit-note-audit-$stamp.csv',
        type: FileType.custom, allowedExtensions: ['csv'],
        bytes: Uint8List.fromList(utf8.encode(content)),
      );
      if (!mounted || savedPath == null) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Credit Note audit CSV সংরক্ষিত হয়েছে।')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Credit Note audit CSV রপ্তানি করা যায়নি: $error')),
      );
    }
  }

  Future<void> _exportGstr1DebitNoteAudit() async {
    if (_gstr1DebitNoteRows.isEmpty || _startDate == null || _endDate == null) return;
    try {
      final db = await AppDatabase.instance.database;
      final rows = await db.query('app_settings', columns: ['setting_value'],
        where: 'setting_key = ?', whereArgs: ['company_gstin'], limit: 1);
      final gstin = rows.isEmpty ? '' : (rows.first['setting_value'] as String? ?? '');
      final content = Gstr1DebitNoteAuditCsv.build(
        _gstr1DebitNoteRows,
        supplierGstin: gstin,
        periodStart: _date(_startDate!),
        periodEnd: _date(_endDate!),
      );
      final stamp = DateTime.now().toIso8601String().substring(0, 10);
      final savedPath = await FilePicker.platform.saveFile(
        dialogTitle: 'Sales Debit Note audit CSV সংরক্ষণ করুন',
        fileName: 'sales-debit-note-audit-$stamp.csv',
        type: FileType.custom, allowedExtensions: ['csv'],
        bytes: Uint8List.fromList(utf8.encode(content)),
      );
      if (!mounted || savedPath == null) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Sales Debit Note audit CSV সংরক্ষিত হয়েছে।')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Sales Debit Note audit CSV রপ্তানি করা যায়নি: $error')),
      );
    }
  }

  Widget _gstr1DebitNoteAuditCard() {
    if (_gstr1ClassificationSummary == null) return const SizedBox.shrink();
    return Card(child: Padding(
      padding: const EdgeInsets.all(12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text('Sales Debit Note Audit', style: Theme.of(context).textTheme.titleMedium),
        Text('নির্বাচিত সময়ে সংরক্ষিত Sales Debit Note: ${_gstr1DebitNoteRows.length}'),
        OutlinedButton.icon(
          onPressed: _gstr1DebitNoteRows.isEmpty ? null : _exportGstr1DebitNoteAudit,
          icon: const Icon(Icons.download),
          label: const Text('Debit Note Audit CSV রপ্তানি করুন'),
        ),
        for (final row in _gstr1DebitNoteRows)
          ListTile(dense: true, contentPadding: EdgeInsets.zero,
            title: Text('${row['note_number']} • ${row['review_status']}'),
            subtitle: Text('মূল Sales Invoice: ${row['original_invoice_number'] ?? 'সংযোগ নেই'} • ${row['note_date']} • ${row['party_name'] ?? 'Walk-in'} • করযোগ্য মূল্য: ${_money((row['taxable_value'] as num?)?.toDouble() ?? 0)} • GST: ${_money((row['tax_amount'] as num?)?.toDouble() ?? 0)}'),
            trailing: Text(_money((row['note_value'] as num?)?.toDouble() ?? 0)),
          ),
        const Text('এটি Debit Note-এর পৃথক management audit report। এটি GSTN Table 9B mapping, tax adjustment বা filing-ready return নয়। Original invoice, recipient details, reason, time limit এবং প্রযোজ্য GST treatment যাচাই করুন।'),
      ]),
    ));
  }

  Future<void> _exportPurchaseReturnItcAudit() async {
    if (_gstr1PurchaseReturnRows.isEmpty) return;
    try {
      final db = await AppDatabase.instance.database;
      final rows = await db.query('app_settings', columns: ['setting_value'],
        where: 'setting_key = ?', whereArgs: ['company_gstin'], limit: 1);
      final gstin = rows.isEmpty ? '' : (rows.first['setting_value'] as String? ?? '');
      final content = PurchaseReturnItcAuditCsv.build(_gstr1PurchaseReturnRows,
        recipientGstin: gstin, periodStart: _date(_startDate!), periodEnd: _date(_endDate!));
      final stamp = DateTime.now().toIso8601String().substring(0, 10);
      final savedPath = await FilePicker.platform.saveFile(
        dialogTitle: 'Purchase Return ITC audit CSV সংরক্ষণ করুন',
        fileName: 'purchase-return-itc-audit-$stamp.csv',
        type: FileType.custom, allowedExtensions: ['csv'],
        bytes: Uint8List.fromList(utf8.encode(content)));
      if (!mounted || savedPath == null) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Purchase Return ITC audit CSV সংরক্ষিত হয়েছে।')));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Purchase Return ITC audit CSV রপ্তানি করা যায়নি: $error')));
    }
  }

  Widget _purchaseReturnItcAuditCard() {
    if (_gstr1ClassificationSummary == null) return const SizedBox.shrink();
    return Card(child: Padding(padding: const EdgeInsets.all(12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text('Purchase Return / ITC Reversal Audit', style: Theme.of(context).textTheme.titleMedium),
        Text('নির্বাচিত সময়ে সংরক্ষিত Purchase Return: ${_gstr1PurchaseReturnRows.length}'),
        OutlinedButton.icon(
          onPressed: _gstr1PurchaseReturnRows.isEmpty ? null : _exportPurchaseReturnItcAudit,
          icon: const Icon(Icons.download),
          label: const Text('Purchase Return ITC Audit CSV রপ্তানি করুন')),
        for (final row in _gstr1PurchaseReturnRows)
          ListTile(dense: true, contentPadding: EdgeInsets.zero,
            title: Text("${row['return_number']} • ${row['review_status']}"),
            subtitle: Text("মূল Purchase Invoice: ${row['original_invoice_number'] ?? 'সংযোগ নেই'} • তারিখ: ${row['return_date']} • করযোগ্য মূল্য: ${_money((row['taxable_value'] as num?)?.toDouble() ?? 0)} • GST: ${_money((row['tax_amount'] as num?)?.toDouble() ?? 0)}"),
            trailing: Text(_money((row['return_value'] as num?)?.toDouble() ?? 0))),
        const Text('এটি Purchase Return ও সম্ভাব্য ITC reversal-এর audit report মাত্র। মূল Purchase Invoice, ITC claim status, supplier credit note, return reason এবং প্রযোজ্য GST বিধি যাচাই ছাড়া ITC স্বয়ংক্রিয়ভাবে reverse করা হবে না.'),
      ])));
  }

  Widget _gstr1CreditNoteAuditCard() {
    if (_gstr1ClassificationSummary == null) return const SizedBox.shrink();
    return Card(child: Padding(
      padding: const EdgeInsets.all(12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text('Sales Return / Credit Note Audit', style: Theme.of(context).textTheme.titleMedium),
        Text('নির্বাচিত সময়ে সংরক্ষিত Sales Return: ${_gstr1CreditNoteRows.length}'),
        OutlinedButton.icon(
          onPressed: _gstr1CreditNoteRows.isEmpty ? null : _exportGstr1CreditNoteAudit,
          icon: const Icon(Icons.download),
          label: const Text('Credit Note Audit CSV রপ্তানি করুন'),
        ),
        for (final row in _gstr1CreditNoteRows)
          ListTile(dense: true, contentPadding: EdgeInsets.zero,
            title: Text('${row['note_number']} • ${row['review_status']}'),
            subtitle: Text('মূল চালান: ${row['original_invoice_number'] ?? 'সংযোগ নেই'} • তারিখ: ${row['note_date']} • করযোগ্য মূল্য: ${_money((row['taxable_value'] as num?)?.toDouble() ?? 0)} • GST: ${_money((row['tax_amount'] as num?)?.toDouble() ?? 0)}'),
            trailing: Text(_money((row['note_value'] as num?)?.toDouble() ?? 0)),
          ),
        const Text('এটি Sales Return থেকে তৈরি Credit Note-এর audit report মাত্র; GSTN Table 9B upload বা tax adjustment নয়। Original invoice, reason, statutory time limit, recipient details ও applicable GST treatment যাচাই করতে হবে। Debit Note entry এই module-এ এখনও নেই।'),
      ]),
    ));
  }

  Widget _gstr1HsnSummaryCard() {
    if (_gstr1ClassificationSummary == null) return const SizedBox.shrink();
    return Card(child: Padding(padding: const EdgeInsets.all(12), child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text('HSN/SAC ও GST Rate অনুযায়ী বিক্রয় সারাংশ', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: _gstr1HsnSummary.isEmpty ? null : _exportGstr1HsnCsv,
          icon: const Icon(Icons.download),
          label: const Text('CSV ফাইল রপ্তানি করুন'),
        ),
        const SizedBox(height: 8),
        if (_gstr1HsnSummary.isEmpty)
          const Text('নির্বাচিত সময়ে কোনো বিক্রয়-লাইন পাওয়া যায়নি।')
        else
          for (final row in _gstr1HsnSummary)
            ListTile(dense: true, contentPadding: EdgeInsets.zero,
              title: Text('${row.supplyCategory} • ${row.hsnSac} • ${row.gstRate.toStringAsFixed(2)}%'),
              subtitle: Text('পরিমাণ: ${row.quantity.toStringAsFixed(2)} ${row.unit} • মোট মূল্য: ${_money(row.totalValue)} • করযোগ্য: ${_money(row.taxableValue)} • CGST: ${_money(row.cgst)} • SGST: ${_money(row.sgst)} • IGST: ${_money(row.igst)}'),
              trailing: Text(_money(row.taxAmount), style: const TextStyle(fontWeight: FontWeight.bold)),
            ),
        const Text('B2B ও B2C সরবরাহ আলাদা করে দেখানো হয়েছে। UQC এখনও স্থানীয় একক; সরকারি UQC mapping, HSN directory validation বা GSTN upload schema যাচাই করা হয়নি। REVIEW সারির গ্রাহক GSTIN যাচাই করুন। এটি প্রস্তুতিমূলক সারাংশ, filing-ready upload নয়।'),
      ],
    )));
  }

  double _number(String key) => (_summary[key] as num?)?.toDouble() ?? 0;
  String _money(double value) => '₹${value.toStringAsFixed(2)}';

  Widget _metric(String label, String value, IconData icon) => Card(
    child: ListTile(leading: Icon(icon), title: Text(label),
      trailing: Text(value, style: const TextStyle(fontWeight: FontWeight.bold))),
  );


  Widget _gstLedgerReconciliationCard() {
    final data = _gstLedgerReconciliation;
    if (data.isEmpty) return const SizedBox.shrink();
    final reconciled = data['is_reconciled'] == true;
    final missingJournals = (data['missing_journal_count'] as num?)?.toInt() ?? 0;
    final missingAssessments =
        (data['missing_assessment_count'] as num?)?.toInt() ?? 0;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            const Icon(Icons.account_balance),
            const SizedBox(width: 8),
            Expanded(child: Text('GST Ledger vs GST Control Accounts',
              style: Theme.of(context).textTheme.titleMedium)),
            Icon(reconciled ? Icons.check_circle : Icons.warning_amber_rounded,
              color: reconciled ? Colors.green : Theme.of(context).colorScheme.error),
          ]),
          const SizedBox(height: 12),
          _metric('Output GST expected from sales / returns / debit notes',
            _money((data['output_gst_expected'] as num?)?.toDouble() ?? 0), Icons.south),
          _metric('Output GST control account (2100)',
            _money((data['output_gst_control'] as num?)?.toDouble() ?? 0), Icons.account_balance_wallet),
          _metric('Output GST difference',
            _money((data['output_gst_difference'] as num?)?.toDouble() ?? 0), Icons.compare_arrows),
          const Divider(),
          _metric('Eligible Input GST expected (purchases less returns)',
            _money((data['eligible_itc_expected'] as num?)?.toDouble() ?? 0), Icons.south_west),
          _metric('Eligible Input GST control (1300)',
            _money((data['eligible_itc_control'] as num?)?.toDouble() ?? 0), Icons.account_balance),
          _metric('Eligible ITC difference',
            _money((data['eligible_itc_difference'] as num?)?.toDouble() ?? 0), Icons.compare_arrows),
          const Divider(),
          _metric('Pending ITC expected',
            _money((data['pending_itc_expected'] as num?)?.toDouble() ?? 0), Icons.pending_actions),
          _metric('Pending ITC control (1310)',
            _money((data['pending_itc_control'] as num?)?.toDouble() ?? 0), Icons.account_balance),
          _metric('Pending ITC difference',
            _money((data['pending_itc_difference'] as num?)?.toDouble() ?? 0), Icons.compare_arrows),
          if (missingJournals > 0)
            Text('Transactions without posted journal: $missingJournals • GST amount: ${_money((data['missing_journal_tax'] as num?)?.toDouble() ?? 0)}',
              style: TextStyle(color: Theme.of(context).colorScheme.error)),
          if (missingAssessments > 0)
            Text('Purchase invoices without ITC assessment: $missingAssessments',
              style: TextStyle(color: Theme.of(context).colorScheme.error)),
          const SizedBox(height: 8),
          Text(reconciled
            ? 'GST source documents and posted GST control accounts match within ₹0.01. Read-only check.'
            : 'Review differences, missing journals and missing ITC assessments. No accounting entries were changed.',
            style: Theme.of(context).textTheme.bodySmall),
          const Text('This check compares locally recorded GST totals; it does not verify GSTR-2B, GSTN portal balances or tax return filing.'),
        ]),
      ),
    );
  }

  Widget _gstRcmReconciliationCard() {
    final data = _gstRcmReconciliation;
    if (data.isEmpty) return const SizedBox.shrink();
    final reconciled = data['is_reconciled'] == true;
    final overpaid = (data['overpaid_count'] as num?)?.toInt() ?? 0;
    final unpaid = (data['unpaid_count'] as num?)?.toInt() ?? 0;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            const Icon(Icons.receipt_long),
            const SizedBox(width: 8),
            Expanded(child: Text('Reverse Charge (RCM) Liability & Payment Reconciliation',
              style: Theme.of(context).textTheme.titleMedium)),
            Icon(reconciled ? Icons.check_circle : Icons.warning_amber_rounded,
              color: reconciled ? Colors.green : Theme.of(context).colorScheme.error),
          ]),
          const SizedBox(height: 12),
          _metric('Recorded RCM liabilities', '${data['liability_count'] ?? 0}', Icons.description),
          _metric('Total RCM tax liability', _money((data['liability_total'] as num?)?.toDouble() ?? 0), Icons.account_balance),
          _metric('Challan / cash-ledger payments recorded', _money((data['paid_total'] as num?)?.toDouble() ?? 0), Icons.payments),
          _metric('Outstanding RCM liability', _money((data['outstanding_total'] as num?)?.toDouble() ?? 0), Icons.pending_actions),
          if (unpaid > 0)
            Text('Liabilities with outstanding tax: $unpaid',
              style: TextStyle(color: Theme.of(context).colorScheme.error)),
          if (overpaid > 0)
            Text('Liabilities with payments exceeding one or more tax heads: $overpaid',
              style: TextStyle(color: Theme.of(context).colorScheme.error)),
          Text('Payment records: ${data['payment_count'] ?? 0} • Audit events: ${data['audit_event_count'] ?? 0}'),
          const SizedBox(height: 8),
          const Text('Read-only comparison of locally entered RCM liability and challan references. It does not verify the GSTN electronic cash ledger, challan status or filed returns. No journal entries are created.'),
        ]),
      ),
    );
  }

  Widget _inventoryReconciliationCard() {
    final data = _inventoryReconciliation;
    if (data.isEmpty) return const SizedBox.shrink();
    final reconciled = data['is_reconciled'] == true;
    final difference = (data['difference'] as num?)?.toDouble() ?? 0;
    final mismatchCount = (data['quantity_mismatch_count'] as num?)?.toInt() ?? 0;
    final unvaluedCount = (data['unvalued_product_count'] as num?)?.toInt() ?? 0;
    final estimatedQuantity =
        (data['estimated_quantity'] as num?)?.toDouble() ?? 0;
    final legacyMigratedQuantity =
        (data['legacy_migrated_quantity'] as num?)?.toDouble() ?? 0;
    final legacyMigratedValue =
        (data['legacy_migrated_value'] as num?)?.toDouble() ?? 0;
    final legacyMigratedProductCount =
        (data['legacy_migrated_product_count'] as num?)?.toInt() ?? 0;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            const Icon(Icons.inventory_2_outlined),
            const SizedBox(width: 8),
            Expanded(child: Text('FIFO Inventory Valuation vs Inventory Control',
              style: Theme.of(context).textTheme.titleMedium)),
            Icon(reconciled ? Icons.check_circle : Icons.warning_amber_rounded,
              color: reconciled ? Colors.green : Theme.of(context).colorScheme.error),
          ]),
          const SizedBox(height: 12),
          _metric('Current FIFO stock valuation', _money((data['fifo_value'] as num?)?.toDouble() ?? 0), Icons.inventory),
          _metric('Inventory control account (1200)', _money((data['control_account_balance'] as num?)?.toDouble() ?? 0), Icons.account_balance),
          _metric('Difference (FIFO − control)', _money(difference), Icons.compare_arrows),
          const Divider(),
          Text('Products checked: ${data['product_count']}'),
          Text('Estimated FIFO quantity: ${estimatedQuantity.toStringAsFixed(3)}'),
          if (legacyMigratedProductCount > 0) ...[
            const Divider(),
            Text('Legacy migrated stock — opening-balance review required',
              style: TextStyle(color: Theme.of(context).colorScheme.error,
                fontWeight: FontWeight.w600)),
            Text('Products with legacy migration layers: $legacyMigratedProductCount'),
            Text('Legacy migrated quantity: ${legacyMigratedQuantity.toStringAsFixed(3)}'),
            Text('Estimated legacy migrated value: ${_money(legacyMigratedValue)}'),
            Text('Migration created estimated FIFO layers but did not create opening-balance journals. Check existing records before any adjustment.',
              style: Theme.of(context).textTheme.bodySmall),
          ],
          if (mismatchCount > 0)
            Text('Products with stock / FIFO quantity mismatch: $mismatchCount • total quantity difference: ${((data['quantity_mismatch_total'] as num?)?.toDouble() ?? 0).toStringAsFixed(3)}',
              style: TextStyle(color: Theme.of(context).colorScheme.error)),
          if (unvaluedCount > 0)
            Text('Products with stock but no remaining FIFO layer: $unvaluedCount',
              style: TextStyle(color: Theme.of(context).colorScheme.error)),
          const SizedBox(height: 8),
          Text(reconciled
            ? 'Current FIFO valuation matches the posted Inventory control balance within ₹0.01. No quantity mismatches found.'
            : 'Review the control-account difference, estimated layers and stock quantity mismatches. No accounting entries were changed.',
            style: Theme.of(context).textTheme.bodySmall),
          Text('Current-state reconciliation; it is not a historical valuation for the selected report end date.',
            style: Theme.of(context).textTheme.bodySmall),
        ]),
      ),
    );
  }

  Widget _customerReconciliationCard() {
    final data = _customerReconciliation;
    if (data.isEmpty) return const SizedBox.shrink();
    final reconciled = data['is_reconciled'] == true;
    final advanceReconciled = data['is_customer_advance_reconciled'] == true;
    final difference = (data['difference'] as num?)?.toDouble() ?? 0;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            const Icon(Icons.account_balance_wallet),
            const SizedBox(width: 8),
            Expanded(child: Text('Customer Ledger vs Accounts Receivable',
              style: Theme.of(context).textTheme.titleMedium)),
            Icon(reconciled ? Icons.check_circle : Icons.warning_amber_rounded,
              color: reconciled ? Colors.green : Theme.of(context).colorScheme.error),
          ]),
          const SizedBox(height: 12),
          _metric('Customer sub-ledger balance', _money((data['customer_ledger_balance'] as num?)?.toDouble() ?? 0), Icons.people),
          _metric('Accounts Receivable control (1100)', _money((data['control_account_balance'] as num?)?.toDouble() ?? 0), Icons.account_balance),
          _metric('Difference (sub-ledger − control)', _money(difference), Icons.compare_arrows),
          const Divider(),
          _metric('Customer advances outstanding (ledger)', _money((data['customer_advance_ledger_balance'] as num?)?.toDouble() ?? 0), Icons.payments),
          _metric('Customer Advances control (2200)', _money((data['customer_advance_control_balance'] as num?)?.toDouble() ?? 0), Icons.account_balance_wallet),
          _metric('Advance reconciliation difference', _money((data['customer_advance_difference'] as num?)?.toDouble() ?? 0), Icons.compare_arrows),
          Text(advanceReconciled
            ? 'Customer advances reconciled within ₹0.01 tolerance.'
            : 'Customer advance ledger and control account do not match. Review posted receipts and allocations.',
            style: TextStyle(color: advanceReconciled ? Colors.green : Theme.of(context).colorScheme.error)),
          const Divider(),
          Text('Opening customer balances: ${_money((data['opening_balance'] as num?)?.toDouble() ?? 0)}'),
          Text('Sales: ${_money((data['sales_total'] as num?)?.toDouble() ?? 0)}  •  Returns: ${_money((data['sales_return_total'] as num?)?.toDouble() ?? 0)}'),
          Text('Debit notes: ${_money((data['debit_note_total'] as num?)?.toDouble() ?? 0)}  •  Receipts: ${_money((data['linked_receipt_total'] as num?)?.toDouble() ?? 0)}  •  Advance allocations: ${_money((data['advance_allocation_total'] as num?)?.toDouble() ?? 0)}'),
          if ((data['unassigned_sales_count'] as num).toInt() > 0)
            Text('Sales / return / debit notes without customer: ${data['unassigned_sales_count']} • ${_money((data['unassigned_sales_total'] as num?)?.toDouble() ?? 0)}',
              style: TextStyle(color: Theme.of(context).colorScheme.error)),
          if ((data['missing_journal_count'] as num).toInt() > 0)
            Text('Transactions missing posted journal: ${data['missing_journal_count']} • ${_money((data['missing_journal_amount'] as num?)?.toDouble() ?? 0)}',
              style: TextStyle(color: Theme.of(context).colorScheme.error)),
          const SizedBox(height: 8),
          Text(reconciled
            ? 'Reconciled within ₹0.01 tolerance. This is a read-only control check.'
            : 'Review the difference and flagged transactions. No accounting entries were changed.',
            style: Theme.of(context).textTheme.bodySmall),
        ]),
      ),
    );
  }

  Widget _supplierReconciliationCard() {
    final data = _supplierReconciliation;
    if (data.isEmpty) return const SizedBox.shrink();
    final reconciled = data['is_reconciled'] == true;
    final difference = (data['difference'] as num?)?.toDouble() ?? 0;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            const Icon(Icons.balance),
            const SizedBox(width: 8),
            Expanded(child: Text('Supplier Ledger vs Accounts Payable',
              style: Theme.of(context).textTheme.titleMedium)),
            Icon(reconciled ? Icons.check_circle : Icons.warning_amber_rounded,
              color: reconciled ? Colors.green : Theme.of(context).colorScheme.error),
          ]),
          const SizedBox(height: 12),
          _metric('Supplier sub-ledger balance', _money((data['supplier_ledger_balance'] as num?)?.toDouble() ?? 0), Icons.people),
          _metric('Accounts Payable control (2000)', _money((data['control_account_balance'] as num?)?.toDouble() ?? 0), Icons.account_balance),
          _metric('Difference (sub-ledger − control)', _money(difference), Icons.compare_arrows),
          const Divider(),
          _metric('Supplier advances outstanding (ledger)', _money((data['supplier_advance_ledger_balance'] as num?)?.toDouble() ?? 0), Icons.payments),
          _metric('Supplier Advances control (1400)', _money((data['supplier_advance_control_balance'] as num?)?.toDouble() ?? 0), Icons.account_balance_wallet),
          _metric('Advance reconciliation difference', _money((data['supplier_advance_difference'] as num?)?.toDouble() ?? 0), Icons.compare_arrows),
          Text(data['is_supplier_advance_reconciled'] == true
            ? 'Supplier advances reconciled within ₹0.01 tolerance.'
            : 'Supplier advance ledger and control account do not match. Review posted entries and allocations.',
            style: TextStyle(color: data['is_supplier_advance_reconciled'] == true ? Colors.green : Theme.of(context).colorScheme.error)),
          const Divider(),
          Text('Opening supplier balances: ${_money((data['opening_balance'] as num?)?.toDouble() ?? 0)}'),
          Text('Purchases: ${_money((data['purchase_total'] as num?)?.toDouble() ?? 0)}  •  Returns: ${_money((data['purchase_return_total'] as num?)?.toDouble() ?? 0)}'),
          Text('Invoice payments: ${_money((data['linked_payment_total'] as num?)?.toDouble() ?? 0)}  •  Advance allocations: ${_money((data['advance_allocation_total'] as num?)?.toDouble() ?? 0)}'),
          if ((data['unassigned_purchase_count'] as num).toInt() > 0)
            Text('Purchase / return invoices without supplier: ${data['unassigned_purchase_count']} • ${_money((data['unassigned_purchase_total'] as num?)?.toDouble() ?? 0)}',
              style: TextStyle(color: Theme.of(context).colorScheme.error)),
          if ((data['missing_journal_count'] as num).toInt() > 0)
            Text('Transactions missing posted journal: ${data['missing_journal_count']} • ${_money((data['missing_journal_amount'] as num?)?.toDouble() ?? 0)}',
              style: TextStyle(color: Theme.of(context).colorScheme.error)),
          const SizedBox(height: 8),
          Text(reconciled
            ? 'Reconciled within ₹0.01 tolerance. This is a read-only control check.'
            : 'Review the difference and flagged transactions. No accounting entries were changed.',
            style: Theme.of(context).textTheme.bodySmall),
        ]),
      ),
    );
  }

  Widget _gstDateFilter({bool pointInTime = false}) => Card(
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const Text('Report date range', style: TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 8, children: [
          if (!pointInTime)
            OutlinedButton.icon(
              onPressed: () => _pickDate(isStart: true),
              icon: const Icon(Icons.calendar_today),
              label: Text(_startDate == null ? 'From date' : 'From: ${_date(_startDate!)}'),
            ),
          OutlinedButton.icon(
            onPressed: () => _pickDate(isStart: false),
            icon: const Icon(Icons.event),
            label: Text(_endDate == null ? 'To date' : 'To: ${_date(_endDate!)}'),
          ),
          TextButton.icon(
            onPressed: _startDate == null && _endDate == null ? null : () {
              setState(() { _startDate = null; _endDate = null; });
              _load();
            },
            icon: const Icon(Icons.clear), label: const Text('Clear'),
          ),
        ]),
      ]),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final title = widget.reportType;
    return Scaffold(
      appBar: AppBar(title: Text(title), actions: [
        IconButton(tooltip: 'Refresh', onPressed: _load, icon: const Icon(Icons.refresh)),
      ]),
      body: _loading ? const Center(child: CircularProgressIndicator()) : RefreshIndicator(
        onRefresh: _load,
        child: ListView(padding: const EdgeInsets.all(16), children: [
          const Text('Summary from locally recorded transactions'),
          const SizedBox(height: 10),
          if (title == 'GST Reports' || title == 'Trial Balance' ||
              title == 'Profit & Loss' || title == 'Balance Sheet') ...[
            _gstDateFilter(pointInTime: title == 'Trial Balance' || title == 'Balance Sheet'),
            const SizedBox(height: 8),
            Text(
              title == 'Trial Balance' || title == 'Balance Sheet'
                ? 'As of: ${_endDate == null ? 'Latest recorded date' : _date(_endDate!)} (opening balances included)'
                : _startDate == null && _endDate == null
                  ? 'Period: All recorded dates'
                  : 'Period: ${_startDate == null ? 'Beginning' : _date(_startDate!)} to ${_endDate == null ? 'Latest' : _date(_endDate!)}',
            ),
          ],
          if (title == 'Trial Balance' || title == 'GST Reports') ...[
            _gstLedgerReconciliationCard(),
            _gstRcmReconciliationCard(),
          ],
          if (title == 'Trial Balance') _inventoryReconciliationCard(),
          if (title == 'Trial Balance') _customerReconciliationCard(),
          if (title == 'Trial Balance') _supplierReconciliationCard(),
          if (title == 'GST Reports') ...[
            _gstr1ReadinessCard(),
            _gstr1ClassificationCard(),
            _gstr1CreditNoteAuditCard(),
            _gstr1DebitNoteAuditCard(),
            _purchaseReturnItcAuditCard(),
            _gstr1HsnSummaryCard(),
            _metric('Sales taxable + tax total', _money(_number('sales')), Icons.point_of_sale),
            _metric('Output GST on sales', _money(_number('salesTax')), Icons.south),
            _metric('Output CGST', _money(_number('salesCgst')), Icons.south),
            _metric('Output SGST', _money(_number('salesSgst')), Icons.south),
            _metric('Output IGST', _money(_number('salesIgst')), Icons.south),
            _metric('Purchase taxable + tax total', _money(_number('purchases')), Icons.shopping_cart),
            _metric('Input GST on purchases', _money(_number('purchaseTax')), Icons.north),
            _metric('Input CGST', _money(_number('purchaseCgst')), Icons.north),
            _metric('Input SGST', _money(_number('purchaseSgst')), Icons.north),
            _metric('Input IGST', _money(_number('purchaseIgst')), Icons.north),
            _metric('Net GST (output less input)', _money(_number('salesTax') - _number('purchaseTax')), Icons.account_balance),
            const SizedBox(height: 12),
            Text('HSN/SAC and GST-rate summary', style: Theme.of(context).textTheme.titleMedium),
            for (final row in _gstBreakdownRows)
              Card(child: ListTile(
                title: Text('${row['hsn_sac']} • ${(row['gst_rate'] as num).toStringAsFixed(2)}%'),
                subtitle: Text('Output taxable: ${_money((row['output_taxable'] as num).toDouble())} • Output GST: ${_money((row['output_tax'] as num).toDouble())}\\nInput taxable: ${_money((row['input_taxable'] as num).toDouble())} • Input GST: ${_money((row['input_tax'] as num).toDouble())}'),
              )),
            if (_gstMissingHsnCount > 0)
              Card(child: ListTile(leading: const Icon(Icons.warning_amber), title: const Text('Missing HSN/SAC codes'), subtitle: Text('$_gstMissingHsnCount sales/purchase line(s) in this period have no HSN/SAC code. Review before preparing statutory reports.'))),
            const SizedBox(height: 8),
            const Text('HSN/SAC codes are stored with product details and copied to new invoice items. This is a bookkeeping summary, not a GST return or filing calculation. Verify tax treatment and eligibility before filing.'),
          ] else if (title == 'Stock Valuation') ...[
            _metric('FIFO stock value', _money(_stockValue), Icons.inventory_2),
            _metric('Products with available stock', '${_stockRows.length}', Icons.category),
            const SizedBox(height: 12),
            Text('Product-wise stock valuation', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            if (_stockRows.isEmpty)
              const Card(child: Padding(
                padding: EdgeInsets.all(16),
                child: Text('No stock quantity is currently available.'),
              ))
            else
              for (final row in _stockRows)
                Card(child: ListTile(
                  title: Text(row['name'] as String),
                  subtitle: Text(
                    'Quantity: ${row['current_stock']} ${row['unit']} • FIFO value: ${_money((row['fifo_value'] as num).toDouble())}${(row['estimated_quantity'] as num).toDouble() > 0 ? ' • includes estimated opening cost' : ''}',
                  ),
                  trailing: Text(
                    _money((row['fifo_value'] as num).toDouble()),
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                )),
            const SizedBox(height: 8),
            Text(
              _stockValueHasEstimates
                  ? 'FIFO valuation uses recorded purchase costs where available. Existing stock at upgrade and any legacy fallback cost are estimated from the saved product purchase price. Purchase returns and manual stock adjustments are not yet fully reflected in FIFO cost layers.'
                  : 'FIFO valuation uses recorded purchase cost layers. Purchase returns and manual stock adjustments are not yet fully reflected in FIFO cost layers.',
            ),
          ] else if (title == 'Trial Balance') ...[
            _metric('Total debit balances', _money(_trialDebit), Icons.south),
            _metric('Total credit balances', _money(_trialCredit), Icons.north),
            _metric('Difference', _money((_trialDebit - _trialCredit).abs()), Icons.balance),
            const SizedBox(height: 12),
            Text('Account-wise balances', style: Theme.of(context).textTheme.titleMedium),
            for (final row in _journalRows) ...[
              if (((row['total_debit'] as num).toDouble() - (row['total_credit'] as num).toDouble()).abs() > 0.005)
                Card(child: ListTile(
                  title: Text('${row['account_code']} • ${row['account_name']}'),
                  subtitle: Text(row['account_type'] as String),
                  trailing: Text(
                    (row['total_debit'] as num) > (row['total_credit'] as num)
                      ? 'Dr ${_money((row['total_debit'] as num).toDouble() - (row['total_credit'] as num).toDouble())}'
                      : 'Cr ${_money((row['total_credit'] as num).toDouble() - (row['total_debit'] as num).toDouble())}',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                )),
            ],
            const Text('This Trial Balance includes posted journal entries, cash/bank and other account opening balances entered through Chart of Accounts, and party opening receivable/payable balances from Party profiles. Older transactions not migrated to the accounting ledger are excluded.'),
          ] else if (title == 'Balance Sheet') ...[
            _metric('Total assets', _money(_balanceAssets), Icons.account_balance_wallet),
            _metric('Total liabilities', _money(_balanceLiabilities), Icons.receipt_long),
            _metric('Owner equity + current earnings', _money(_balanceEquity), Icons.pie_chart),
            _metric('Liabilities + equity', _money(_balanceLiabilities + _balanceEquity), Icons.balance),
            _metric('Balance difference', _money((_balanceAssets - _balanceLiabilities - _balanceEquity).abs()), Icons.rule),
            const SizedBox(height: 12),
            Text('Assets', style: Theme.of(context).textTheme.titleMedium),
            for (final row in _balanceSheetRows)
              if (row['account_type'] == 'asset')
                Card(child: ListTile(
                  title: Text('${row['account_code']} • ${row['account_name']}'),
                  trailing: Text(_money((row['balance'] as num).toDouble())),
                )),
            Text('Liabilities', style: Theme.of(context).textTheme.titleMedium),
            for (final row in _balanceSheetRows)
              if (row['account_type'] == 'liability')
                Card(child: ListTile(
                  title: Text('${row['account_code']} • ${row['account_name']}'),
                  trailing: Text(_money((row['balance'] as num).toDouble())),
                )),
            Text('Equity', style: Theme.of(context).textTheme.titleMedium),
            for (final row in _balanceSheetRows)
              if (row['account_type'] == 'equity')
                Card(child: ListTile(
                  title: Text('${row['account_code']} • ${row['account_name']}'),
                  trailing: Text(_money((row['balance'] as num).toDouble())),
                )),
            const Text('Preliminary balance sheet includes posted journal entries, cash/bank and other account opening balances entered through Chart of Accounts, and party opening receivable/payable balances from Party profiles. It excludes unposted transactions, unrecorded depreciation and legacy transactions not migrated to the accounting ledger. Current earnings are added to equity for presentation. Verify balances before statutory or lending use.'),
          ] else if (title == 'Profit & Loss') ...[
            _metric('Recorded income', _money(_profitIncome), Icons.trending_up),
            _metric('Recorded expenses', _money(_profitExpense), Icons.receipt_long),
            _metric('Preliminary net result', _money(_profitIncome - _profitExpense), Icons.analytics),
            const SizedBox(height: 8),
            Text('Income and expense ledger accounts', style: Theme.of(context).textTheme.titleMedium),
            for (final row in _journalRows)
              if (row['account_type'] == 'income' || row['account_type'] == 'expense')
                if (((row['total_debit'] as num).toDouble() - (row['total_credit'] as num).toDouble()).abs() > 0.005)
                  Card(child: ListTile(
                    title: Text('${row['account_code']} • ${row['account_name']}'),
                    subtitle: Text(row['account_type'] as String),
                    trailing: Text(_money(
                      row['account_type'] == 'income'
                        ? (row['total_credit'] as num).toDouble() - (row['total_debit'] as num).toDouble()
                        : (row['total_debit'] as num).toDouble() - (row['total_credit'] as num).toDouble(),
                    )),
                  )),
            const Text('Preliminary report only: FIFO cost of goods sold is posted for new sales. Legacy transactions, opening balances, depreciation, purchase/sales returns and stock adjustments are not yet fully accounted for. Do not use this as a statutory financial statement.'),
          ] else if (title == 'Accounting & Ledgers') ...[
            _metric('Customer receipts', _money(_number('receipts')), Icons.call_received),
            _metric('Supplier / other payments', _money(_number('payments')), Icons.call_made),
            const SizedBox(height: 12),
            Text('Party outstanding balances', style: Theme.of(context).textTheme.titleMedium),
            for (final row in _rows)
              Card(child: ListTile(
                title: Text(row['name'] as String), subtitle: Text(row['party_type'] as String),
                trailing: Column(mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.end, children: [
                    Text('Due from: ${_money((row['receivable'] as num).toDouble())}', style: const TextStyle(fontSize: 12)),
                    Text('Due to: ${_money((row['payable'] as num).toDouble())}', style: const TextStyle(fontSize: 12)),
                  ]),
              )),
          ] else ...[
            _metric('Total sales', _money(_number('sales')), Icons.trending_up),
            _metric('Total purchases', _money(_number('purchases')), Icons.shopping_cart),
            _metric('Total expenses', _money(_number('expenses')), Icons.receipt_long),
            _metric('Receipts collected', _money(_number('receipts')), Icons.call_received),
            _metric('Payments made', _money(_number('payments')), Icons.call_made),
            _metric('Gross difference (sales - purchases - expenses)', _money(_number('sales') - _number('purchases') - _number('expenses')), Icons.analytics),
            const SizedBox(height: 8),
            Text('Sales invoices: ${_summary['salesCount'] ?? 0} • Sales debit notes: ${_summary['salesDebitNoteCount'] ?? 0} • Purchases: ${_summary['purchaseCount'] ?? 0} • Expenses: ${_summary['expenseCount'] ?? 0}'),
            const Text('This summary uses recorded totals; it is not a complete profit-and-loss statement or statutory financial report.'),
          ],
        ]),
      ),
    );
  }
}
