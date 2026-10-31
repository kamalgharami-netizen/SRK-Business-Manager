import 'package:flutter/material.dart';

import '../../data/local/app_database.dart';
import '../../data/sync/business_sync_service.dart';

import '../accounting/accounts_page.dart';

import '../expenses/expenses_page.dart';
import '../invoices/invoices_page.dart';
import '../invoices/sales_returns_page.dart';
import '../payments/payments_page.dart';
import '../purchases/purchases_page.dart';
import '../purchases/stock_control_page.dart';
import '../reports/reports_page.dart';
import '../settings/settings_page.dart';
import '../sync/sync_status_page.dart';
import '../staff/staff_page.dart';
import '../parties/parties_page.dart';
import '../products/products_page.dart';

class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key, required this.cloudConfigured});
  final bool cloudConfigured;

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  late Future<Map<String, double>> _summaryFuture;
  bool _syncing = false;

  @override
  void initState() {
    super.initState();
    _summaryFuture = _loadSummary();
  }

  Future<Map<String, double>> _loadSummary() async {
    final db = await AppDatabase.instance.database;
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, now.day).toIso8601String();
    final end = DateTime(now.year, now.month, now.day + 1).toIso8601String();
    final rows = await db.rawQuery('''
      SELECT
        COALESCE((SELECT SUM(grand_total) FROM invoices
          WHERE invoice_type = 'sale' AND invoice_date >= ? AND invoice_date < ?), 0)
        - COALESCE((SELECT SUM(grand_total) FROM invoices
          WHERE invoice_type = 'sales_return' AND invoice_date >= ? AND invoice_date < ?), 0)
          AS today_sales,
        COALESCE((SELECT SUM(grand_total - amount_paid) FROM invoices
          WHERE invoice_type = 'sale'), 0)
        - COALESCE((SELECT SUM(grand_total) FROM invoices
          WHERE invoice_type = 'sales_return'), 0)
        - COALESCE((SELECT SUM(amount) FROM payments
          WHERE payment_type = 'receipt' AND invoice_id IS NULL AND party_id IS NOT NULL), 0)
        + COALESCE((SELECT SUM(opening_balance) FROM parties
          WHERE balance_type = 'receivable'), 0) AS receivables,
        COALESCE((SELECT SUM(grand_total - amount_paid) FROM invoices
          WHERE invoice_type = 'purchase'), 0)
        - COALESCE((SELECT SUM(grand_total) FROM invoices
          WHERE invoice_type = 'purchase_return'), 0)
        - COALESCE((SELECT SUM(amount) FROM payments
          WHERE payment_type = 'payment' AND invoice_id IS NULL AND party_id IS NOT NULL), 0)
        + COALESCE((SELECT SUM(opening_balance) FROM parties
          WHERE balance_type = 'payable'), 0) AS payables,
        COALESCE((SELECT COUNT(*) FROM products
          WHERE (is_service = 0 OR is_service IS NULL)
            AND low_stock_alert > 0 AND current_stock <= low_stock_alert), 0)
          AS low_stock
    ''', [start, end, start, end]);
    final row = rows.first;
    double number(String key) => (row[key] as num?)?.toDouble() ?? 0;
    return {
      'today_sales': number('today_sales'),
      'receivables': number('receivables'),
      'payables': number('payables'),
      'low_stock': number('low_stock'),
    };
  }

  Future<void> _syncNow() async {
    final businessId = AppDatabase.instance.activeBusinessId;
    if (businessId == null || _syncing) return;
    setState(() => _syncing = true);
    try {
      final result = await BusinessSyncService(
        businessId: businessId,
      ).syncNow();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Business data sync: ${result.uploaded} uploaded, '
            '${result.downloaded} downloaded, '
            '${result.uploadFailures + result.downloadFailures} failed.',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Sync unavailable; queued changes are kept. $error')),
      );
    } finally {
      if (mounted) setState(() => _syncing = false);
    }
  }

  String _money(double value) => '₹${value.toStringAsFixed(2)}';

  static const modules = <_ModuleInfo>[
    _ModuleInfo('Sales & Invoices', Icons.point_of_sale),
    _ModuleInfo('Sales Returns', Icons.assignment_return),
    _ModuleInfo('Purchases', Icons.shopping_cart),
    _ModuleInfo('Purchase Returns & Stock Control', Icons.assignment_return),
    _ModuleInfo('Inventory & Stock', Icons.inventory_2),
    _ModuleInfo('Stock Valuation', Icons.price_check),
    _ModuleInfo('Trial Balance', Icons.balance),
    _ModuleInfo('Profit & Loss', Icons.analytics),
    _ModuleInfo('Balance Sheet', Icons.account_balance),
    _ModuleInfo('Customers & Suppliers', Icons.people_alt),
    _ModuleInfo('Receipts & Payments', Icons.payments),
    _ModuleInfo('Expenses', Icons.receipt_long),
    _ModuleInfo('GST Reports', Icons.account_balance),
    _ModuleInfo('Accounting & Ledgers', Icons.menu_book),
    _ModuleInfo('Chart of Accounts & Opening Balances', Icons.account_balance_wallet),
    _ModuleInfo('Business Reports', Icons.analytics),
    _ModuleInfo('Staff & Permissions', Icons.admin_panel_settings),
    _ModuleInfo('Backup & Sync', Icons.cloud_sync),
    _ModuleInfo('Settings', Icons.settings),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('SRK Business Manager'),
        actions: [
          IconButton(
            tooltip: 'Sync business data',
            onPressed: widget.cloudConfigured && !_syncing ? _syncNow : null,
            icon: _syncing
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.sync),
          ),
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Chip(
              avatar: Icon(widget.cloudConfigured ? Icons.cloud_done : Icons.cloud_off, size: 18),
              label: Text(widget.cloudConfigured ? 'Cloud configured' : 'Demo mode'),
            ),
          ),
        ],
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final columns = constraints.maxWidth >= 1100 ? 4 : constraints.maxWidth >= 700 ? 3 : 2;
          return SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Business overview', style: Theme.of(context).textTheme.headlineMedium),
                const SizedBox(height: 6),
                Text('Your accounting and business workspace', style: Theme.of(context).textTheme.bodyMedium),
                const SizedBox(height: 20),
                FutureBuilder<Map<String, double>>(
                  future: _summaryFuture,
                  builder: (context, snapshot) {
                    if (snapshot.hasError) {
                      return Card(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Text('Could not load business overview: ${snapshot.error}'),
                        ),
                      );
                    }
                    if (!snapshot.hasData) {
                      return const Center(child: Padding(
                        padding: EdgeInsets.all(20),
                        child: CircularProgressIndicator(),
                      ));
                    }
                    final values = snapshot.data!;
                    return Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      children: [
                        _SummaryCard(title: 'Today Sales (Net)', value: _money(values['today_sales']!), icon: Icons.trending_up),
                        _SummaryCard(title: 'Receivables*', value: _money(values['receivables']!), icon: Icons.call_received),
                        _SummaryCard(title: 'Payables*', value: _money(values['payables']!), icon: Icons.call_made),
                        _SummaryCard(title: 'Low Stock Items', value: values['low_stock']!.toStringAsFixed(0), icon: Icons.warning_amber),
                      ],
                    );
                  },
                ),
                const SizedBox(height: 8),
                const Text(
                  '* Receivables and payables are estimated from invoice balances, returns and party opening balances.',
                  style: TextStyle(fontSize: 11),
                ),
                const SizedBox(height: 28),
                Text('Business modules', style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 12),
                GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: modules.length,
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: columns,
                    crossAxisSpacing: 12,
                    mainAxisSpacing: 12,
                    childAspectRatio: 2.15,
                  ),
                  itemBuilder: (context, index) {
                    final module = modules[index];
                    return Card(
                      elevation: 0,
                      child: ListTile(
                        leading: CircleAvatar(child: Icon(module.icon)),
                        title: Text(module.title, style: const TextStyle(fontWeight: FontWeight.w600)),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () async {
                          final Widget page = switch (module.title) {
                            'Sales & Invoices' => const InvoicesPage(),
                            'Sales Returns' => const SalesReturnsPage(),
                            'Purchases' => const PurchasesPage(),
                            'Purchase Returns & Stock Control' => const StockControlPage(),
                            'Receipts & Payments' => const PaymentsPage(),
                            'Expenses' => const ExpensesPage(),
                            'GST Reports' => const ReportsPage(reportType: 'GST Reports'),
                            'Accounting & Ledgers' => const ReportsPage(reportType: 'Accounting & Ledgers'),
                            'Chart of Accounts & Opening Balances' => const AccountsPage(),
                            'Business Reports' => const ReportsPage(reportType: 'Business Reports'),
                            'Staff & Permissions' => const StaffPage(),
                            'Backup & Sync' => SyncStatusPage(cloudConfigured: widget.cloudConfigured),
                            'Settings' => const SettingsPage(),
                            'Customers & Suppliers' => const PartiesPage(),
                            'Inventory & Stock' => const ProductsPage(),
                            'Stock Valuation' => const ReportsPage(reportType: 'Stock Valuation'),
                            'Trial Balance' => const ReportsPage(reportType: 'Trial Balance'),
                            'Profit & Loss' => const ReportsPage(reportType: 'Profit & Loss'),
                            'Balance Sheet' => const ReportsPage(reportType: 'Balance Sheet'),
                            _ => _ModulePlaceholderPage(module: module),
                          };
                          await Navigator.of(context).push(
                            MaterialPageRoute<void>(builder: (_) => page),
                          );
                          if (mounted) {
                            setState(() {
                              _summaryFuture = _loadSummary();
                            });
                          }
                        },
                      ),
                    );
                  },
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _ModuleInfo {
  const _ModuleInfo(this.title, this.icon);
  final String title;
  final IconData icon;
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.title, required this.value, required this.icon});
  final String title;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 220,
      child: Card(
        elevation: 0,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Icon(icon, size: 28, color: Theme.of(context).colorScheme.primary),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: Theme.of(context).textTheme.bodySmall),
                  const SizedBox(height: 4),
                  Text(value, style: Theme.of(context).textTheme.titleLarge),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ModulePlaceholderPage extends StatelessWidget {
  const _ModulePlaceholderPage({required this.module});
  final _ModuleInfo module;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(module.title)),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(module.icon, size: 56),
              const SizedBox(height: 16),
              Text(module.title, style: Theme.of(context).textTheme.headlineSmall),
              const SizedBox(height: 8),
              const Text(
                'This module is planned for a later development phase. '
                'Its database, workflows, validations and reports are not implemented yet.',
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
