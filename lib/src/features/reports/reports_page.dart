import 'package:flutter/material.dart';
import '../../data/local/app_database.dart';

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
  DateTime? _startDate;
  DateTime? _endDate;

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
    final openingBalances = await db.rawQuery("""
      SELECT
        COALESCE(SUM(CASE WHEN balance_type = 'receivable' THEN opening_balance ELSE 0 END), 0) AS receivable,
        COALESCE(SUM(CASE WHEN balance_type = 'payable' THEN opening_balance ELSE 0 END), 0) AS payable
      FROM parties
    """);
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
    final currentPeriodEarnings = profitIncome - profitExpense;
    if (!mounted) return;
    setState(() {
      _summary = {
        'sales': sales.first['total'], 'salesTax': sales.first['tax'],
        'salesCgst': sales.first['cgst'], 'salesSgst': sales.first['sgst'], 'salesIgst': sales.first['igst'],
        'salesCount': sales.first['count'], 'purchases': purchases.first['total'],
        'purchaseTax': purchases.first['tax'], 'purchaseCgst': purchases.first['cgst'], 'purchaseSgst': purchases.first['sgst'], 'purchaseIgst': purchases.first['igst'], 'purchaseCount': purchases.first['count'],
        'expenses': expense.first['total'], 'expenseCount': expense.first['count'],
        'receipts': payments.first['receipts'], 'payments': payments.first['payments'],
      };
      _rows = partyRows;
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
      _loading = false;
    });
  }

  double _number(String key) => (_summary[key] as num?)?.toDouble() ?? 0;
  String _money(double value) => '₹${value.toStringAsFixed(2)}';

  Widget _metric(String label, String value, IconData icon) => Card(
    child: ListTile(leading: Icon(icon), title: Text(label),
      trailing: Text(value, style: const TextStyle(fontWeight: FontWeight.bold))),
  );

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
          if (title == 'GST Reports') ...[
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
            const Text('This Trial Balance includes posted journal entries and party opening receivable/payable balances. Cash/bank opening balances and older transactions not migrated to the accounting ledger are excluded.'),
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
            const Text('Preliminary balance sheet includes posted journal entries and party opening receivable/payable balances. It excludes cash/bank opening balances, unposted transactions, unrecorded depreciation and legacy transactions not migrated to the accounting ledger. Current earnings are added to equity for presentation. Verify balances before statutory or lending use.'),
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
            Text('Sales: ${_summary['salesCount'] ?? 0} • Purchases: ${_summary['purchaseCount'] ?? 0} • Expenses: ${_summary['expenseCount'] ?? 0}'),
            const Text('This summary uses recorded totals; it is not a complete profit-and-loss statement or statutory financial report.'),
          ],
        ]),
      ),
    );
  }
}
