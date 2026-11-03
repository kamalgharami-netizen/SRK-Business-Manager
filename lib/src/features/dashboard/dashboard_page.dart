import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../data/local/app_database.dart';
import '../../data/sync/business_sync_service.dart';

import '../accounting/accounts_page.dart';

import '../expenses/expenses_page.dart';
import '../invoices/invoices_page.dart';
import '../invoices/debit_notes_page.dart';
import '../invoices/sales_returns_page.dart';
import '../payments/payments_page.dart';
import '../purchases/purchases_page.dart';
import '../purchases/stock_control_page.dart';
import '../reports/reports_page.dart';
import '../reports/gstr3b_itc_page.dart';
import '../settings/settings_page.dart';
import '../sync/sync_status_page.dart';
import '../staff/staff_page.dart';
import '../staff/team_access_page.dart';
import '../parties/parties_page.dart';
import '../parties/party_ledger_page.dart';
import '../products/products_page.dart';
import '../inventory/warehouses_page.dart';
import '../inventory/warehouse_stock_balance_page.dart';

class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key, required this.cloudConfigured});
  final bool cloudConfigured;

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> with WidgetsBindingObserver {
  late Future<Map<String, double>> _summaryFuture;
  bool _syncing = false;
  bool _appIsResumed = true;
  bool _roleLoading = false;
  String? _businessRole;
  String? _roleError;
  Timer? _autoSyncTimer;
  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _summaryFuture = _loadSummary();
    unawaited(_loadBusinessRole());
    // Retry queued changes while the dashboard is active. A network outage
    // leaves the durable local queue untouched; the next tick retries it.
    _autoSyncTimer = Timer.periodic(const Duration(seconds: 60), (_) {
      if (_appIsResumed && mounted && widget.cloudConfigured) {
        unawaited(_syncNow(showFeedback: false));
      }
    });
    if (widget.cloudConfigured) {
      _connectivitySubscription = Connectivity().onConnectivityChanged.listen(
        (results) {
          final hasConnection = results.any(
            (result) => result != ConnectivityResult.none,
          );
          if (hasConnection && _appIsResumed && mounted) {
            unawaited(_syncNow(showFeedback: false));
          }
        },
        onError: (_) {
          // Periodic and lifecycle retries remain available if the platform
          // cannot provide connectivity events.
        },
      );
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _appIsResumed = state == AppLifecycleState.resumed;
    if (_appIsResumed && mounted && widget.cloudConfigured) {
      unawaited(_syncNow(showFeedback: false));
    }
  }

  @override
  void dispose() {
    _autoSyncTimer?.cancel();
    _connectivitySubscription?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> _loadBusinessRole() async {
    final businessId = AppDatabase.instance.activeBusinessId;
    if (!widget.cloudConfigured || businessId == null) {
      AppDatabase.instance.clearCloudBusinessRole();
      if (mounted) {
        setState(() {
          _roleLoading = false;
          _businessRole = null;
          _roleError = null;
        });
      }
      return;
    }

    if (mounted) {
      setState(() {
        _roleLoading = true;
        _roleError = null;
      });
    }
    try {
      final result = await Supabase.instance.client.rpc(
        'current_business_role',
        params: {'target_business_id': businessId},
      );
      final role = result?.toString();
      if (role == null || role.trim().isEmpty) {
        throw StateError('No membership role was returned for this business.');
      }
      AppDatabase.instance.setCloudBusinessRole(role);
      if (mounted) {
        setState(() {
          _businessRole = role.toLowerCase();
          _roleError = null;
          _roleLoading = false;
        });
      }
    } catch (error) {
      AppDatabase.instance.markCloudRoleUnavailable();
      if (mounted) {
        setState(() {
          _businessRole = null;
          _roleError = error.toString();
          _roleLoading = false;
        });
      }
    }
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

  Future<void> _syncNow({bool showFeedback = true}) async {
    final businessId = AppDatabase.instance.activeBusinessId;
    if (businessId == null || _syncing) return;
    setState(() => _syncing = true);
    try {
      final result = await BusinessSyncService(
        businessId: businessId,
      ).syncNow();
      if (!mounted || !showFeedback) return;
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
    _ModuleInfo('Sales Debit Notes', Icons.note_add),
    _ModuleInfo('Purchases', Icons.shopping_cart),
    _ModuleInfo('Purchase Returns & Stock Control', Icons.assignment_return),
    _ModuleInfo('Inventory & Stock', Icons.inventory_2),
    _ModuleInfo('Warehouse Master', Icons.warehouse_outlined),
    _ModuleInfo('Warehouse Stock Balance', Icons.warehouse),
    _ModuleInfo('Stock Valuation', Icons.price_check),
    _ModuleInfo('Trial Balance', Icons.balance),
    _ModuleInfo('Profit & Loss', Icons.analytics),
    _ModuleInfo('Balance Sheet', Icons.account_balance),
    _ModuleInfo('Customers & Suppliers', Icons.people_alt),
    _ModuleInfo('Party Ledger', Icons.menu_book),
    _ModuleInfo('Receipts & Payments', Icons.payments),
    _ModuleInfo('Expenses', Icons.receipt_long),
    _ModuleInfo('GST Reports', Icons.account_balance),
    _ModuleInfo('GSTR-3B ITC Preparation', Icons.receipt_long),
    _ModuleInfo('Accounting & Ledgers', Icons.menu_book),
    _ModuleInfo('Chart of Accounts & Opening Balances', Icons.account_balance_wallet),
    _ModuleInfo('Business Reports', Icons.analytics),
    _ModuleInfo('Staff & Permissions', Icons.admin_panel_settings),
    _ModuleInfo('Backup & Sync', Icons.cloud_sync),
    _ModuleInfo('Settings', Icons.settings),
  ];

  Future<void> _openModule(_ModuleInfo module) async {
    final Widget page = switch (module.title) {
      'Sales & Invoices' => const InvoicesPage(),
      'Sales Returns' => const SalesReturnsPage(),
      'Sales Debit Notes' => const DebitNotesPage(),
      'Purchases' => const PurchasesPage(),
      'Purchase Returns & Stock Control' => const StockControlPage(),
      'Receipts & Payments' => const PaymentsPage(),
      'Expenses' => const ExpensesPage(),
      'GST Reports' => const ReportsPage(reportType: 'GST Reports'),
      'GSTR-3B ITC Preparation' => const Gstr3bItcPage(),
      'Accounting & Ledgers' => const ReportsPage(reportType: 'Accounting & Ledgers'),
      'Chart of Accounts & Opening Balances' => const AccountsPage(),
      'Business Reports' => const ReportsPage(reportType: 'Business Reports'),
      'Staff & Permissions' => widget.cloudConfigured && AppDatabase.instance.activeBusinessId != null ? TeamAccessPage(businessId: AppDatabase.instance.activeBusinessId!) : const StaffPage(),
      'Backup & Sync' => SyncStatusPage(cloudConfigured: widget.cloudConfigured),
      'Settings' => const SettingsPage(),
      'Customers & Suppliers' => const PartiesPage(),
      'Party Ledger' => const PartyLedgerPage(),
      'Inventory & Stock' => const ProductsPage(),
      'Warehouse Master' => const WarehousesPage(),
      'Warehouse Stock Balance' => const WarehouseStockBalancePage(),
      'Stock Valuation' => const ReportsPage(reportType: 'Stock Valuation'),
      'Trial Balance' => const ReportsPage(reportType: 'Trial Balance'),
      'Profit & Loss' => const ReportsPage(reportType: 'Profit & Loss'),
      'Balance Sheet' => const ReportsPage(reportType: 'Balance Sheet'),
      _ => _ModulePlaceholderPage(module: module),
    };
    await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => page));
    if (mounted) setState(() => _summaryFuture = _loadSummary());
  }

  Widget _moduleTile(_ModuleInfo module) => Card(elevation: 3, shadowColor: const Color(0xFF173B70).withValues(alpha: .10), child: ListTile(
    dense: true, leading: CircleAvatar(child: Icon(module.icon)),
    title: Text(module.title, style: const TextStyle(fontWeight: FontWeight.w600)),
    trailing: const Icon(Icons.chevron_right), onTap: () => _openModule(module)));

  Widget _summaryCards() => FutureBuilder<Map<String, double>>(
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
        return const Padding(
          padding: EdgeInsets.all(24),
          child: Center(child: CircularProgressIndicator()),
        );
      }
      final v = snapshot.data!;
      return LayoutBuilder(builder: (context, c) {
        final w = c.maxWidth >= 1000 ? (c.maxWidth - 36) / 4 : c.maxWidth >= 560 ? (c.maxWidth - 12) / 2 : c.maxWidth;
        return Wrap(spacing: 12, runSpacing: 12, children: [
          _SummaryCard(title: 'Today Sales (Net)', value: _money(v['today_sales']!), icon: Icons.trending_up, width: w, accent: const Color(0xFF1769E0)),
          _SummaryCard(title: 'Receivables*', value: _money(v['receivables']!), icon: Icons.call_received, width: w, accent: const Color(0xFF16865B)),
          _SummaryCard(title: 'Payables*', value: _money(v['payables']!), icon: Icons.call_made, width: w, accent: const Color(0xFFB66A12)),
          _SummaryCard(title: 'Low Stock Items', value: v['low_stock']!.toStringAsFixed(0), icon: Icons.warning_amber, width: w, accent: const Color(0xFFB54747)),
        ]);
      });
    });

  Widget _content(bool desktop) => SingleChildScrollView(
    padding: EdgeInsets.fromLTRB(desktop ? 28 : 16, desktop ? 28 : 18, desktop ? 28 : 16, 34),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Business Dashboard', style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontSize: desktop ? 29 : 24, fontWeight: FontWeight.w900, color: const Color(0xFF102A56))),
          const SizedBox(height: 5),
          const Text('A clear view of your business activity and accounts'),
        ])),
        if (desktop) FilledButton.icon(onPressed: () => _openModule(modules.first), icon: const Icon(Icons.add), label: const Text('New Sale')),
      ]),
      if (widget.cloudConfigured && AppDatabase.instance.activeBusinessId != null) ...[
        const SizedBox(height: 12),
        if (_roleLoading) const LinearProgressIndicator()
        else if (_roleError != null) MaterialBanner(
          content: Text('Business role could not be verified. Cloud-business edits are blocked until access is verified. Check that Supabase migration 0008 is applied. Details: $_roleError'),
          actions: [TextButton(onPressed: _loadBusinessRole, child: const Text('Retry'))])
        else Align(alignment: Alignment.centerLeft, child: Chip(
          avatar: const Icon(Icons.verified_user, size: 18), label: Text("Access role: ${_businessRole ?? 'unknown'}"))),
      ],
      const SizedBox(height: 18),
      if (!desktop) Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFF173F7A), Color(0xFF2869C4), Color(0xFF4B8DE2)]),
          borderRadius: BorderRadius.circular(24),
          boxShadow: const [BoxShadow(color: Color(0x332457A7), blurRadius: 20, offset: Offset(0, 9))],
        ),
        child: Row(children: [
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('YOUR BUSINESS, IN CONTROL', style: TextStyle(color: Colors.white70, fontSize: 10, letterSpacing: 1.2, fontWeight: FontWeight.w800)),
            const SizedBox(height: 7),
            const Text('Everything in one place', style: TextStyle(color: Colors.white, fontSize: 19, fontWeight: FontWeight.w900)),
            const SizedBox(height: 5),
            Text(widget.cloudConfigured ? 'Cloud workspace connected' : 'Offline-first • Your data stays on this device', style: const TextStyle(color: Colors.white70, fontSize: 11)),
          ])),
          Container(width: 58, height: 58, decoration: BoxDecoration(color: Colors.white.withValues(alpha: .16), borderRadius: BorderRadius.circular(19), border: Border.all(color: Colors.white24)), child: const Icon(Icons.storefront_rounded, color: Colors.white, size: 31)),
        ]),
      ),
      const SizedBox(height: 20), _summaryCards(), const SizedBox(height: 8),
      const Text('* Receivables and payables are estimated from invoice balances, returns and party opening balances.', style: TextStyle(fontSize: 11)),
      const SizedBox(height: 26),
      Text('Quick actions', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
      const SizedBox(height: 10),
      LayoutBuilder(builder: (context, c) {
        final quick = modules.take(4).toList();
        final cols = c.maxWidth >= 700 ? 4 : c.maxWidth >= 420 ? 2 : 1;
        return GridView.builder(shrinkWrap: true, physics: const NeverScrollableScrollPhysics(), itemCount: quick.length,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: cols, crossAxisSpacing: 12, mainAxisSpacing: 12, childAspectRatio: desktop ? 2.6 : 2.3),
          itemBuilder: (context, i) { final m = quick[i]; return Card(elevation: 5, shadowColor: const Color(0xFF173B70).withValues(alpha: .10), child: InkWell(borderRadius: BorderRadius.circular(20), onTap: () => _openModule(m),
            child: Padding(padding: const EdgeInsets.all(14), child: Row(children: [
              CircleAvatar(child: Icon(m.icon)), const SizedBox(width: 10),
              Expanded(child: Text(m.title, style: const TextStyle(fontWeight: FontWeight.w700))),
              const Icon(Icons.arrow_forward_ios, size: 14)])))); });
      }),
      const SizedBox(height: 26),
      Text('All business modules', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
      const SizedBox(height: 10),
      LayoutBuilder(builder: (context, c) {
        final cols = c.maxWidth >= 1000 ? 3 : c.maxWidth >= 620 ? 2 : 1;
        return GridView.builder(shrinkWrap: true, physics: const NeverScrollableScrollPhysics(), itemCount: modules.length,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: cols, crossAxisSpacing: 10, mainAxisSpacing: 2, childAspectRatio: cols == 1 ? 6.2 : 3.8),
          itemBuilder: (context, i) => _moduleTile(modules[i]));
      }),
    ]));

  Widget _sideItem(String title, IconData icon, {bool selected = false, required VoidCallback onTap}) =>
    Padding(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
      child: Material(color: selected ? const Color(0xFF2459A6) : Colors.transparent, borderRadius: BorderRadius.circular(10),
        child: ListTile(dense: true, leading: Icon(icon, color: Colors.white, size: 19),
          title: Text(title, style: const TextStyle(color: Colors.white, fontSize: 13)), onTap: onTap)));

  Widget _sidebar() {
    Widget section(String title, List<String> moduleTitles) {
      final entries = modules.where((m) => moduleTitles.contains(m.title));
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 12, 6),
            child: Text(
              title.toUpperCase(),
              style: const TextStyle(
                color: Colors.white54,
                fontSize: 10,
                letterSpacing: 1.1,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          for (final module in entries)
            _sideItem(module.title, module.icon, onTap: () => _openModule(module)),
        ],
      );
    }

    return Container(
      width: 252,
      color: const Color(0xFF102A56),
      child: Column(
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 24, 16, 22),
            child: Row(
              children: [
                Icon(Icons.storefront, color: Colors.white, size: 30),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'SRK Business\\nManager',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 17,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const Divider(color: Colors.white24, height: 1),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.only(bottom: 12),
              children: [
                _sideItem('Dashboard', Icons.dashboard, selected: true, onTap: () {}),
                section('Sales & Purchases', [
                  'Sales & Invoices',
                  'Sales Returns',
                  'Sales Debit Notes',
                  'Purchases',
                  'Purchase Returns & Stock Control',
                  'Receipts & Payments',
                  'Expenses',
                ]),
                section('Inventory', [
                  'Inventory & Stock',
                  'Stock Valuation',
                ]),
                section('Parties', [
                  'Customers & Suppliers',
                  'Party Ledger',
                ]),
                section('Accounts & GST', [
                  'Accounting & Ledgers',
                  'Chart of Accounts & Opening Balances',
                  'Trial Balance',
                  'Profit & Loss',
                  'Balance Sheet',
                  'GST Reports',
                  'GSTR-3B ITC Preparation',
                ]),
                section('Business & Admin', [
                  'Business Reports',
                  'Staff & Permissions',
                  'Backup & Sync',
                  'Settings',
                ]),
              ],
            ),
          ),
          const Divider(color: Colors.white24, height: 1),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Icon(
                  widget.cloudConfigured ? Icons.cloud_done : Icons.cloud_off,
                  color: Colors.white70,
                  size: 18,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    widget.cloudConfigured ? 'Cloud configured' : 'Offline / local mode',
                    style: const TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, c) {
    final desktop = c.maxWidth >= 1050;
    return Scaffold(
      appBar: AppBar(title: const Text('SRK Business Manager'), actions: [
        IconButton(tooltip: 'Sync business data', onPressed: widget.cloudConfigured && !_syncing ? _syncNow : null,
          icon: _syncing ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.sync)),
        Padding(padding: const EdgeInsets.only(right: 12), child: Chip(
          avatar: Icon(widget.cloudConfigured ? Icons.cloud_done : Icons.cloud_off, size: 18),
          label: Text(widget.cloudConfigured ? 'Cloud' : 'Offline'))),
      ]),
      body: desktop ? Row(children: [_sidebar(), Expanded(child: ColoredBox(color: Theme.of(context).colorScheme.surface, child: _content(true)))]) : _content(false),
    );
  });
}

class _ModuleInfo {
  const _ModuleInfo(this.title, this.icon);
  final String title;
  final IconData icon;
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.title, required this.value, required this.icon, required this.width, required this.accent});
  final String title;
  final String value;
  final IconData icon;
  final double width;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: Card(
        elevation: 6,
        shadowColor: accent.withValues(alpha: .16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: accent.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(12)), child: Icon(icon, size: 25, color: accent)),
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
