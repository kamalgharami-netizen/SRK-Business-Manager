import 'dart:convert';

import 'package:flutter/material.dart';

import '../../data/local/app_database.dart';
import '../../data/local/inventory_cost_service.dart';

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
  List<Map<String, Object?>> _unassignedProducts = [];

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

      final unassignedProducts = await db.rawQuery('''
        SELECT p.id AS product_id, p.name AS product_name, p.sku, p.unit,
          SUM(l.quantity_remaining) AS quantity,
          SUM(l.quantity_remaining * l.unit_cost) AS stock_value
        FROM inventory_cost_layers l
        INNER JOIN products p ON p.id = l.product_id
        WHERE l.warehouse_sync_id IS NULL AND l.quantity_remaining > 0
          AND (p.is_service = 0 OR p.is_service IS NULL)
        GROUP BY p.id, p.name, p.sku, p.unit
        ORDER BY p.name COLLATE NOCASE
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
        _unassignedProducts = unassignedProducts;
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


  Future<void> _allocateLegacyStock(
    Map<String, Object?> product,
  ) async {
    final warehouses = _warehouses
        .where((row) => (row['is_active'] as num?)?.toInt() == 1)
        .toList(growable: false);
    if (warehouses.isEmpty) {
      _showMessage('Create an active warehouse before allocating legacy stock.');
      return;
    }
    final quantityController = TextEditingController(
      text: _quantity(product['quantity']),
    );
    String destination = warehouses.first['sync_id'] as String;
    final selected = await showDialog<Map<String, Object?>>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Allocate Legacy Stock'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(product['product_name'] as String? ?? ''),
              const SizedBox(height: 8),
              Text('Unassigned available: ${_quantity(product['quantity'])}'),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: destination,
                decoration: const InputDecoration(labelText: 'Destination warehouse'),
                items: warehouses.map((row) => DropdownMenuItem(
                  value: row['sync_id'] as String,
                  child: Text('${row['name']} (${row['code']})'),
                )).toList(),
                onChanged: (value) {
                  if (value != null) setDialogState(() => destination = value);
                },
              ),
              const SizedBox(height: 12),
              TextField(
                controller: quantityController,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  labelText: 'Quantity to allocate',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                final qty = double.tryParse(quantityController.text.trim());
                final available = _number(product['quantity']);
                if (qty == null || !qty.isFinite || qty <= 0 || qty > available + 0.000001) {
                  _showMessage('Enter a valid quantity not exceeding unassigned stock.');
                  return;
                }
                Navigator.pop(dialogContext, {
                  'warehouse_sync_id': destination,
                  'quantity': qty,
                });
              },
              child: const Text('Allocate'),
            ),
          ],
        ),
      ),
    );
    quantityController.dispose();
    if (selected == null || !mounted) return;

    try {
      final db = await AppDatabase.instance.database;
      final now = DateTime.now().toIso8601String();
      final qty = selected['quantity'] as double;
      final warehouseSyncId = selected['warehouse_sync_id'] as String;
      await db.transaction((txn) async {
        final layers = <Map<String, Object?>>[];
        await InventoryCostService.removeStockAtFifo(
          txn,
          productId: product['product_id'] as int,
          quantity: qty,
          removedAt: now,
          consumedLayers: layers,
          unassignedOnly: true,
        );
        for (final layer in layers) {
          await txn.insert('inventory_cost_layers', {
            'product_id': product['product_id'],
            'warehouse_sync_id': warehouseSyncId,
            'source_type': 'legacy_allocation',
            'source_id': null,
            'received_at': now,
            'quantity_received': layer['quantity'],
            'quantity_remaining': layer['quantity'],
            'unit_cost': layer['unit_cost'],
            'is_estimated': layer['is_estimated'],
          });
        }
        final movementId = await txn.insert('stock_movements', {
          'sync_id': AppDatabase.instance.createSyncId(),
          'product_id': product['product_id'],
          'warehouse_sync_id': warehouseSyncId,
          'movement_type': 'adjustment',
          'quantity_change': qty,
          'reference': 'ALLOC-${DateTime.now().microsecondsSinceEpoch}',
          'notes': 'Legacy/unassigned stock allocated to warehouse',
          'inventory_effect_json': jsonEncode({
            'direction': 'allocate',
            'quantity': qty,
            'layers': layers,
          }),
          'created_at': now,
        });
        await AppDatabase.instance.enqueueStockMovementSync(txn, movementId);
      });
      await _load();
      if (mounted) _showMessage('Legacy stock allocated successfully.');
    } catch (error) {
      if (mounted) _showMessage('Could not allocate legacy stock: $error');
    }
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
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
                      if (unassignedQty > 0) ...[
                        Padding(
                          padding: const EdgeInsets.only(bottom: 14),
                          child: Text(
                            'This stock has no warehouse assignment. Allocate only after verifying the physical stock location.',
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.error,
                            ),
                          ),
                        ),
                        Card(
                          elevation: 0,
                          child: Column(
                            children: _unassignedProducts.map((product) => ListTile(
                              title: Text(product['product_name'] as String? ?? ''),
                              subtitle: Text(
                                'Available: ${_quantity(product['quantity'])} • Value: ${_money(product['stock_value'])}',
                              ),
                              trailing: IconButton(
                                tooltip: 'Allocate to warehouse',
                                icon: const Icon(Icons.move_to_inbox_outlined),
                                onPressed: () => _allocateLegacyStock(product),
                              ),
                            )).toList(),
                          ),
                        ),
                      ],
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
