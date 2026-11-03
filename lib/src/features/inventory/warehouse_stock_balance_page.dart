import 'package:flutter/material.dart';

import '../../data/local/app_database.dart';

class WarehouseStockBalancePage extends StatefulWidget {
  const WarehouseStockBalancePage({super.key});

  @override
  State<WarehouseStockBalancePage> createState() =>
      _WarehouseStockBalancePageState();
}

class _WarehouseStockBalancePageState extends State<WarehouseStockBalancePage> {
  bool _loading = true;
  String? _error;
  List<Map<String, Object?>> _warehouses = [];
  Map<String, List<Map<String, Object?>>> _balances = {};
  Map<String, Object?> _unassigned = const {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  double _number(Object? value) => (value as num?)?.toDouble() ?? 0;

  String _quantity(Object? value) => _number(value).toStringAsFixed(3);

  String _money(Object? value) => '₹${_number(value).toStringAsFixed(2)}';

  Future<void> _load() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final db = await AppDatabase.instance.database;
      final warehouseRows = await db.rawQuery('''
        SELECT
          w.sync_id,
          w.name,
          w.code,
          w.is_active,
          COALESCE(SUM(l.quantity_remaining), 0) AS total_quantity,
          COALESCE(SUM(l.quantity_remaining * l.unit_cost), 0) AS stock_value,
          COALESCE(SUM(
            CASE WHEN l.is_estimated = 1 THEN l.quantity_remaining ELSE 0 END
          ), 0) AS estimated_quantity
        FROM warehouses w
        LEFT JOIN inventory_cost_layers l
          ON l.warehouse_sync_id = w.sync_id
          AND l.quantity_remaining > 0
          AND EXISTS (
            SELECT 1 FROM products p
            WHERE p.id = l.product_id
              AND (p.is_service = 0 OR p.is_service IS NULL)
          )
        GROUP BY w.sync_id, w.name, w.code, w.is_active
        ORDER BY w.is_active DESC, w.name COLLATE NOCASE
      ''');

      final detailRows = await db.rawQuery('''
        SELECT
          l.warehouse_sync_id,
          p.id AS product_id,
          p.name AS product_name,
          p.sku,
          p.unit,
          SUM(l.quantity_remaining) AS quantity,
          SUM(l.quantity_remaining * l.unit_cost) AS stock_value,
          SUM(CASE WHEN l.is_estimated = 1
            THEN l.quantity_remaining ELSE 0 END) AS estimated_quantity
        FROM inventory_cost_layers l
        INNER JOIN warehouses w ON w.sync_id = l.warehouse_sync_id
        INNER JOIN products p ON p.id = l.product_id
        WHERE l.quantity_remaining > 0
          AND (p.is_service = 0 OR p.is_service IS NULL)
        GROUP BY l.warehouse_sync_id, p.id, p.name, p.sku, p.unit
        ORDER BY w.name COLLATE NOCASE, p.name COLLATE NOCASE
      ''');

      final unassignedRows = await db.rawQuery('''
        SELECT
          COUNT(DISTINCT l.product_id) AS product_count,
          COALESCE(SUM(l.quantity_remaining), 0) AS total_quantity,
          COALESCE(SUM(l.quantity_remaining * l.unit_cost), 0) AS stock_value
        FROM inventory_cost_layers l
        INNER JOIN products p ON p.id = l.product_id
        WHERE l.warehouse_sync_id IS NULL
          AND l.quantity_remaining > 0
          AND (p.is_service = 0 OR p.is_service IS NULL)
      ''');

      final grouped = <String, List<Map<String, Object?>>>{};
      for (final row in detailRows) {
        final id = row['warehouse_sync_id'] as String;
        (grouped[id] ??= []).add(row);
      }
      if (!mounted) return;
      setState(() {
        _warehouses = warehouseRows;
        _balances = grouped;
        _unassigned = unassignedRows.isEmpty ? const {} : unassignedRows.first;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.toString();
        _loading = false;
      });
    }
  }

  Widget _summaryCard({
    required String title,
    required String value,
    required IconData icon,
    String? subtitle,
  }) {
    return Card(
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            CircleAvatar(child: Icon(icon)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: Theme.of(context).textTheme.bodySmall),
                  const SizedBox(height: 4),
                  Text(
                    value,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 3),
                    Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _warehouseCard(Map<String, Object?> warehouse) {
    final id = warehouse['sync_id'] as String;
    final rows = _balances[id] ?? const <Map<String, Object?>>[];
    final estimated = _number(warehouse['estimated_quantity']);
    final active = (warehouse['is_active'] as num?)?.toInt() == 1;
    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 14),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.warehouse_outlined),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    '${warehouse['name']} (${warehouse['code']})',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                if (!active)
                  const Chip(
                    label: Text('Inactive'),
                    visualDensity: VisualDensity.compact,
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 20,
              runSpacing: 8,
              children: [
                Text('Total quantity: ${_quantity(warehouse['total_quantity'])}'),
                Text('Stock value: ${_money(warehouse['stock_value'])}'),
                Text('Products: ${rows.length}'),
              ],
            ),
            if (estimated > 0)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  'Includes ${_quantity(estimated)} units of estimated/migrated stock.',
                  style: TextStyle(color: Theme.of(context).colorScheme.tertiary),
                ),
              ),
            const Divider(height: 24),
            if (rows.isEmpty)
              const Text('No warehouse-assigned stock recorded.')
            else
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: DataTable(
                  columns: const [
                    DataColumn(label: Text('Product')),
                    DataColumn(label: Text('SKU')),
                    DataColumn(label: Text('Quantity'), numeric: true),
                    DataColumn(label: Text('Unit')),
                    DataColumn(label: Text('Value'), numeric: true),
                  ],
                  rows: rows.map((row) => DataRow(cells: [
                    DataCell(Text(row['product_name'] as String? ?? '')),
                    DataCell(Text(row['sku'] as String? ?? '—')),
                    DataCell(Text(_quantity(row['quantity']))),
                    DataCell(Text(row['unit'] as String? ?? '')),
                    DataCell(Text(_money(row['stock_value']))),
                  ])).toList(),
                ),
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final unassignedQty = _number(_unassigned['total_quantity']);
    final unassignedValue = _number(_unassigned['stock_value']);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Warehouse Stock Balance'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.error_outline, size: 40),
                        const SizedBox(height: 12),
                        Text('Could not load warehouse stock: $_error'),
                        const SizedBox(height: 12),
                        FilledButton.icon(
                          onPressed: _load,
                          icon: const Icon(Icons.refresh),
                          label: const Text('Retry'),
                        ),
                      ],
                    ),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      _summaryCard(
                        title: 'Unassigned / Legacy Stock',
                        value: _quantity(unassignedQty),
                        icon: Icons.inventory_2_outlined,
                        subtitle:
                            '${_unassigned['product_count'] ?? 0} products • ${_money(unassignedValue)}',
                      ),
                      if (unassignedQty > 0)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 14),
                          child: Text(
                            'This stock has no warehouse assignment. It is shown separately and is not included in any warehouse balance.',
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.error,
                            ),
                          ),
                        ),
                      if (_warehouses.isEmpty)
                        const Card(
                          child: Padding(
                            padding: EdgeInsets.all(20),
                            child: Text(
                              'No warehouses found. Create a warehouse in Warehouse Master first.',
                            ),
                          ),
                        )
                      else
                        ..._warehouses.map(_warehouseCard),
                    ],
                  ),
                ),
    );
  }
}
