import 'package:flutter/material.dart';
import '../../data/local/app_database.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});
  @override
  State<SettingsPage> createState() => _SettingsPageState();
}
class _SettingsPageState extends State<SettingsPage> {
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _address = TextEditingController();
  final _gstin = TextEditingController();
  bool _loading = true;
  String? _backupPath;
  @override
  void initState() { super.initState(); _load(); }
  Future<void> _load() async {
    final db = await AppDatabase.instance.database;
    final rows = await db.query('app_settings');
    final values = {for (final row in rows) row['setting_key'] as String: row['setting_value'] as String};
    _name.text = values['company_name'] ?? '';
    _phone.text = values['company_phone'] ?? '';
    _address.text = values['company_address'] ?? '';
    _gstin.text = values['company_gstin'] ?? '';
    if (!mounted) return;
    setState(() => _loading = false);
  }
  Future<void> _save() async {
    final db = await AppDatabase.instance.database;
    final values = {'company_name': _name.text.trim(), 'company_phone': _phone.text.trim(), 'company_address': _address.text.trim(), 'company_gstin': _gstin.text.trim().toUpperCase()};
    await db.transaction((txn) async {
      for (final entry in values.entries) {
        await txn.insert('app_settings', {'setting_key': entry.key, 'setting_value': entry.value}, conflictAlgorithm: ConflictAlgorithm.replace);
      }
    });
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Business profile saved on this device.')));
  }
  Future<void> _backup() async {
    try {
      final path = await AppDatabase.instance.createBackup();
      if (!mounted) return;
      setState(() => _backupPath = path);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Local database backup created.')));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Backup failed: $error')));
    }
  }
  @override
  void dispose() { _name.dispose(); _phone.dispose(); _address.dispose(); _gstin.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Settings & Backup')),
    body: _loading ? const Center(child: CircularProgressIndicator()) : ListView(padding: const EdgeInsets.all(20), children: [
      Text('Business profile', style: Theme.of(context).textTheme.titleLarge),
      const SizedBox(height: 12),
      TextField(controller: _name, decoration: const InputDecoration(labelText: 'Business name')),
      TextField(controller: _phone, decoration: const InputDecoration(labelText: 'Business phone'), keyboardType: TextInputType.phone),
      TextField(controller: _gstin, decoration: const InputDecoration(labelText: 'GSTIN'), textCapitalization: TextCapitalization.characters),
      TextField(controller: _address, decoration: const InputDecoration(labelText: 'Business address'), maxLines: 3),
      const SizedBox(height: 16),
      FilledButton.icon(onPressed: _save, icon: const Icon(Icons.save), label: const Text('Save business profile')),
      const Divider(height: 36),
      Text('Local backup', style: Theme.of(context).textTheme.titleLarge),
      const SizedBox(height: 8),
      const Text('Create a copy of the local SQLite database in the application documents folder. Keep an additional copy on a separate safe device.'),
      const SizedBox(height: 12),
      OutlinedButton.icon(onPressed: _backup, icon: const Icon(Icons.backup), label: const Text('Create database backup')),
      if (_backupPath != null) SelectableText('Backup location: $_backupPath'),
      const SizedBox(height: 24),
      const Text('Cloud synchronisation, backup restore, staff sign-in, access enforcement, invoice numbering settings and tax configuration are not enabled yet.'),
    ]),
  );
}
