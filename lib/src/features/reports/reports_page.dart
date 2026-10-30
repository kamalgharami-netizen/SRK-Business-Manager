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

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    final db = await AppDatabase.instance.database;
    final sales = await db.rawQuery("SELECT COALESCE(SUM(grand_total),0) AS total, COALESCE(SUM(tax_total),0) AS tax, COUNT(*) AS count FROM invoices WHERE invoice_type='sale'");
    final purchases = await db.rawQuery("SELECT COALESCE(SUM(grand_total),0) AS total, COALESCE(SUM(tax_total),0) AS tax, COUNT(*) AS count FROM invoices WHERE invoice_type='purchase'");
    final expense = await db.rawQuery("SELECT COALESCE(SUM(amount),0) AS total, COUNT(*) AS count FROM expenses");
    final payments = await db.rawQuery("SELECT COALESCE(SUM(CASE WHEN payment_type='receipt' THEN amount ELSE 0 END),0) AS receipts, COALESCE(SUM(CASE WHEN payment_type='payment' THEN amount ELSE 0 END),0) AS payments FROM payments");
    final partyRows = await db.rawQuery("""
      SELECT p.id, p.name, p.party_type,
        COALESCE((SELECT SUM(i.grand_total - i.amount_paid) FROM invoices i WHERE i.party_id=p.id AND i.invoice_type='sale'),0) AS receivable,
        COALESCE((SELECT SUM(i.grand_total - i.amount_paid) FROM invoices i WHERE i.party_id=p.id AND i.invoice_type='purchase'),0) AS payable
      FROM parties p ORDER BY p.name COLLATE NOCASE
    """);
    if (!mounted) return;
    setState(() {
      _summary = {
        'sales': sales.first['total'], 'salesTax': sales.first['tax'],
        'salesCount': sales.first['count'], 'purchases': purchases.first['total'],
        'purchaseTax': purchases.first['tax'], 'purchaseCount': purchases.first['count'],
        'expenses': expense.first['total'], 'expenseCount': expense.first['count'],
        'receipts': payments.first['receipts'], 'payments': payments.first['payments'],
      };
      _rows = partyRows;
      _loading = false;
    });
  }

  double _number(String key) => (_summary[key] as num?)?.toDouble() ?? 0;
  String _money(double value) => '₹${value.toStringAsFixed(2)}';

  Widget _metric(String label, String value, IconData icon) => Card(
    child: ListTile(leading: Icon(icon), title: Text(label), trailing: Text(value, style: const TextStyle(fontWeight: FontWeight.bold))),
  );

  @override
  Widget build(BuildContext context) {
    final title = widget.reportType;
    return Scaffold(
      appBar: AppBar(title: Text(title), actions: [IconButton(tooltip: 'Refresh', onPressed: _load, icon: const Icon(Icons.refresh))]),
      body: _loading ? const Center(child: CircularProgressIndicator()) : RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text('Summary from locally recorded transactions', style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 10),
            if (title == 'GST Reports') ...[
              _metric('Sales taxable + tax total', _money(_number('sales')), Icons.point_of_sale),
              _metric('Output GST on sales', _money(_number('salesTax')), Icons.south),
              _metric('Purchase taxable + tax total', _money(_number('purchases')), Icons.shopping_cart),
              _metric('Input GST on purchases', _money(_number('purchaseTax')), Icons.north),
              _metric('Net GST (output less input)', _money(_number('salesTax') - _number('purchaseTax')), Icons.account_balance),
              const SizedBox(height: 8),
              const Text('This is a bookkeeping summary, not a GST return or filing calculation. Verify tax treatment and eligibility before filing.'),
            ] else if (title == 'Accounting & Ledgers') ...[
              _metric('Customer receipts', _money(_number('receipts')), Icons.call_received),
              _metric('Supplier / other payments', _money(_number('payments')), Icons.call_made),
              const SizedBox(height: 12),
              Text('Party outstanding balances', style: Theme.of(context).textTheme.titleMedium),
              for (final row in _rows)
                Card(child: ListTile(
                  title: Text(row['name'] as String),
                  subtitle: Text(row['party_type'] as String),
                  trailing: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [
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
          ],
        ),
      ),
    );
  }
}
