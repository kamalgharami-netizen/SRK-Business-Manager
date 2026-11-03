import 'package:flutter/material.dart';

import '../../data/local/app_database.dart';

class WarehousesPage extends StatefulWidget {
  const WarehousesPage({super.key});

  @override
  State<WarehousesPage> createState() => _WarehousesPageState();
}

class _WarehousesPageState extends State<WarehousesPage> {
  List<Map<String, Object?>> _warehouses = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final db = await AppDatabase.instance.database;
      final rows = await db.query(
        'warehouses',
        orderBy: 'is_active DESC, name COLLATE NOCASE',
      );
      if (!mounted) return;
      setState(() {
        _warehouses = rows;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _loading = false);
      _message('Could not load warehouses: $error');
    }
  }

  void _message(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  Future<void> _edit({Map<String, Object?>? warehouse}) async {
    final name = TextEditingController(
      text: warehouse?['name'] as String? ?? '',
    );
    final code = TextEditingController(
      text: warehouse?['code'] as String? ?? '',
    );
    final address = TextEditingController(
      text: warehouse?['address'] as String? ?? '',
    );
    final phone = TextEditingController(
      text: warehouse?['phone'] as String? ?? '',
    );
    final formKey = GlobalKey<FormState>();

    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(warehouse == null ? 'Add warehouse' : 'Edit warehouse'),
        content: SizedBox(
          width: 440,
          child: Form(
            key: formKey,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextFormField(
                    controller: name,
                    autofocus: true,
                    decoration: const InputDecoration(
                      labelText: 'Warehouse name *',
                      hintText: 'e.g. Main Store',
                    ),
                    validator: (value) => value == null || value.trim().isEmpty
                        ? 'Enter a warehouse name'
                        : null,
                  ),
                  TextFormField(
                    controller: code,
                    textCapitalization: TextCapitalization.characters,
                    decoration: const InputDecoration(
                      labelText: 'Warehouse code *',
                      hintText: 'e.g. WH-001',
                    ),
                    validator: (value) => value == null || value.trim().isEmpty
                        ? 'Enter a unique warehouse code'
                        : null,
                  ),
                  TextFormField(
                    controller: address,
                    decoration: const InputDecoration(labelText: 'Address'),
                    maxLines: 2,
                  ),
                  TextFormField(
                    controller: phone,
                    keyboardType: TextInputType.phone,
                    decoration: const InputDecoration(labelText: 'Phone'),
                  ),
                ],
              ),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              if (formKey.currentState!.validate()) {
                Navigator.pop(dialogContext, true);
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );

    if (saved == true) {
      try {
        final db = await AppDatabase.instance.database;
        await db.transaction((txn) async {
          final now = DateTime.now().toIso8601String();
          final syncId = warehouse == null
              ? AppDatabase.instance.createSyncId()
              : warehouse['sync_id'] as String?;
          if (syncId == null || syncId.isEmpty) {
            throw StateError('Warehouse is missing its sync identifier.');
          }
          if (warehouse == null) {
            final id = await txn.insert('warehouses', {
              'sync_id': syncId,
              'name': name.text.trim(),
              'code': code.text.trim().toUpperCase(),
              'address': address.text.trim().isEmpty ? null : address.text.trim(),
              'phone': phone.text.trim().isEmpty ? null : phone.text.trim(),
              'is_active': 1,
              'created_at': now,
              'updated_at': now,
            });
            final rows = await txn.query(
              'warehouses',
              where: 'id = ?',
              whereArgs: [id],
              limit: 1,
            );
            final payload = Map<String, dynamic>.from(rows.single)..remove('id');
            await AppDatabase.instance.enqueueSyncOperation(
              tableName: 'warehouses',
              recordId: syncId,
              operation: 'insert',
              payload: payload,
              executor: txn,
            );
          } else {
            await txn.update(
              'warehouses',
              {
                'name': name.text.trim(),
                'code': code.text.trim().toUpperCase(),
                'address': address.text.trim().isEmpty ? null : address.text.trim(),
                'phone': phone.text.trim().isEmpty ? null : phone.text.trim(),
                'updated_at': now,
              },
              where: 'id = ?',
              whereArgs: [warehouse['id']],
            );
            final rows = await txn.query(
              'warehouses',
              where: 'id = ?',
              whereArgs: [warehouse['id']],
              limit: 1,
            );
            final payload = Map<String, dynamic>.from(rows.single)..remove('id');
            await AppDatabase.instance.enqueueSyncOperation(
              tableName: 'warehouses',
              recordId: syncId,
              operation: 'update',
              payload: payload,
              executor: txn,
            );
          }
        });
        await _load();
        _message(warehouse == null ? 'Warehouse added.' : 'Warehouse updated.');
      } catch (error) {
        _message('Could not save warehouse. Check that its name and code are unique. $error');
      }
    }

    name.dispose();
    code.dispose();
    address.dispose();
    phone.dispose();
  }

  Future<void> _toggle(Map<String, Object?> warehouse) async {
    final currentlyActive = (warehouse['is_active'] as int? ?? 1) == 1;
    final syncId = warehouse['sync_id'] as String?;
    if (syncId == null || syncId.isEmpty) {
      _message('Warehouse is missing its sync identifier.');
      return;
    }
    try {
      final db = await AppDatabase.instance.database;
      await db.transaction((txn) async {
        await txn.update(
          'warehouses',
          {
            'is_active': currentlyActive ? 0 : 1,
            'updated_at': DateTime.now().toIso8601String(),
          },
          where: 'id = ?',
          whereArgs: [warehouse['id']],
        );
        final rows = await txn.query(
          'warehouses',
          where: 'id = ?',
          whereArgs: [warehouse['id']],
          limit: 1,
        );
        final payload = Map<String, dynamic>.from(rows.single)..remove('id');
        await AppDatabase.instance.enqueueSyncOperation(
          tableName: 'warehouses',
          recordId: syncId,
          operation: 'update',
          payload: payload,
          executor: txn,
        );
      });
      await _load();
    } catch (error) {
      _message('Could not update warehouse status: $error');
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Warehouse Master')),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: () => _edit(),
          icon: const Icon(Icons.add_business),
          label: const Text('Add warehouse'),
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : _warehouses.isEmpty
                ? const Center(
                    child: Padding(
                      padding: EdgeInsets.all(24),
                      child: Text(
                        'No warehouses added yet. Add your main store or warehouse to begin.',
                        textAlign: TextAlign.center,
                      ),
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: _warehouses.length,
                    separatorBuilder: (_, index) => const Divider(),
                    itemBuilder: (context, index) {
                      final warehouse = _warehouses[index];
                      final active =
                          (warehouse['is_active'] as int? ?? 1) == 1;
                      final details = [
                        warehouse['code'] as String? ?? '',
                        if ((warehouse['address'] as String? ?? '').isNotEmpty)
                          warehouse['address'] as String,
                        if ((warehouse['phone'] as String? ?? '').isNotEmpty)
                          warehouse['phone'] as String,
                        active ? 'Active' : 'Inactive',
                      ].where((part) => part.isNotEmpty).join(' • ');
                      return ListTile(
                        leading: CircleAvatar(
                          child: Icon(
                            active ? Icons.warehouse_outlined : Icons.warehouse,
                          ),
                        ),
                        title: Text(
                          warehouse['name'] as String,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        subtitle: Text(details),
                        onTap: () => _edit(warehouse: warehouse),
                        trailing: IconButton(
                          tooltip: active ? 'Deactivate' : 'Activate',
                          onPressed: () => _toggle(warehouse),
                          icon: Icon(
                            active
                                ? Icons.pause_circle_outline
                                : Icons.play_circle_outline,
                          ),
                        ),
                      );
                    },
                  ),
      );
}
