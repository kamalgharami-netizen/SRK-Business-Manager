import 'package:flutter/material.dart';

import '../accounting/accounts_page.dart';

import '../expenses/expenses_page.dart';
import '../invoices/invoices_page.dart';
import '../payments/payments_page.dart';
import '../purchases/purchases_page.dart';
import '../purchases/stock_control_page.dart';
import '../reports/reports_page.dart';
import '../settings/settings_page.dart';
import '../staff/staff_page.dart';
import '../parties/parties_page.dart';
import '../products/products_page.dart';

class DashboardPage extends StatelessWidget {
  const DashboardPage({super.key, required this.cloudConfigured});
  final bool cloudConfigured;

  static const modules = <_ModuleInfo>[
    _ModuleInfo('Sales & Invoices', Icons.point_of_sale),
    _ModuleInfo('Purchases', Icons.shopping_cart),
    _ModuleInfo('Purchase Returns & Stock Control', Icons.assignment_return),
    _ModuleInfo('Inventory & Stock', Icons.inventory_2),
    _ModuleInfo('Stock Valuation', Icons.price_check),
    _ModuleInfo('Trial Balance', Icons.balance),
    _ModuleInfo('Profit & Loss', Icons.analytics),
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
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Chip(
              avatar: Icon(cloudConfigured ? Icons.cloud_done : Icons.cloud_off, size: 18),
              label: Text(cloudConfigured ? 'Cloud configured' : 'Demo mode'),
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
                const Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    _SummaryCard(title: 'Today Sales', value: '₹0.00', icon: Icons.trending_up),
                    _SummaryCard(title: 'Receivables', value: '₹0.00', icon: Icons.call_received),
                    _SummaryCard(title: 'Payables', value: '₹0.00', icon: Icons.call_made),
                    _SummaryCard(title: 'Low Stock Items', value: '0', icon: Icons.warning_amber),
                  ],
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
                        onTap: () {
                          final Widget page = switch (module.title) {
                            'Sales & Invoices' => const InvoicesPage(),
                            'Purchases' => const PurchasesPage(),
                            'Purchase Returns & Stock Control' => const StockControlPage(),
                            'Receipts & Payments' => const PaymentsPage(),
                            'Expenses' => const ExpensesPage(),
                            'GST Reports' => const ReportsPage(reportType: 'GST Reports'),
                            'Accounting & Ledgers' => const ReportsPage(reportType: 'Accounting & Ledgers'),
                            'Chart of Accounts & Opening Balances' => const AccountsPage(),
                            'Business Reports' => const ReportsPage(reportType: 'Business Reports'),
                            'Staff & Permissions' => const StaffPage(),
                            'Backup & Sync' => const SettingsPage(),
                            'Settings' => const SettingsPage(),
                            'Customers & Suppliers' => const PartiesPage(),
                            'Inventory & Stock' => const ProductsPage(),
                            'Stock Valuation' => const ReportsPage(reportType: 'Stock Valuation'),
                            'Trial Balance' => const ReportsPage(reportType: 'Trial Balance'),
                            'Profit & Loss' => const ReportsPage(reportType: 'Profit & Loss'),
                            _ => _ModulePlaceholderPage(module: module),
                          };
                          Navigator.of(context).push(
                            MaterialPageRoute<void>(builder: (_) => page),
                          );
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
