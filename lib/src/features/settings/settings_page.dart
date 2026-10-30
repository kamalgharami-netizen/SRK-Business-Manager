import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:sqflite/sqflite.dart' show ConflictAlgorithm;

import '../../data/local/app_database.dart';
import '../../data/indian_states.dart';

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
  final _state = TextEditingController();

  bool _loading = true;
  bool _restoring = false;
  String? _backupPath;
  String? _restoreSafetyPath;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final db = await AppDatabase.instance.database;
    final rows = await db.query('app_settings');
    final values = {
      for (final row in rows)
        row['setting_key'] as String: row['setting_value'] as String
    };
    _name.text = values['company_name'] ?? '';
    _phone.text = values['company_phone'] ?? '';
    _address.text = values['company_address'] ?? '';
    _gstin.text = values['company_gstin'] ?? '';
    _state.text = values['company_state'] ?? '';
    if (!mounted) return;
    setState(() => _loading = false);
  }

  Future<void> _save() async {
    if (!IndianStates.all.contains(_state.text)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Select a valid GST registration state.')),
      );
      return;
    }
    final db = await AppDatabase.instance.database;
    final values = {
      'company_name': _name.text.trim(),
      'company_phone': _phone.text.trim(),
      'company_address': _address.text.trim(),
      'company_gstin': _gstin.text.trim().toUpperCase(),
      'company_state': _state.text.trim(),
    };
    await db.transaction((txn) async {
      for (final entry in values.entries) {
        await txn.insert(
          'app_settings',
          {'setting_key': entry.key, 'setting_value': entry.value},
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
    });
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Business profile saved on this device.')),
    );
  }

  Future<void> _backup() async {
    try {
      final path = await AppDatabase.instance.createBackup();
      if (!mounted) return;
      setState(() => _backupPath = path);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Local database backup created.')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Backup failed: $error')),
      );
    }
  }

  Future<void> _restore() async {
    if (_restoring) return;
    try {
      final selected = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['db', 'sqlite'],
        allowMultiple: false,
      );
      if (selected == null || selected.files.isEmpty) return;
      final path = selected.files.single.path;
      if (path == null || path.isEmpty) {
        throw StateError('The selected file path is not available');
      }
      if (!mounted) return;
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Restore database backup?'),
          content: const Text(
            'Restoring replaces the current local business data with the '
            'selected backup. A safety copy of the current database will be '
            'created automatically before replacement. Continue?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Restore'),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;

      setState(() => _restoring = true);
      final safetyPath = await AppDatabase.instance.restoreBackup(path);
      if (!mounted) return;
      setState(() {
        _restoreSafetyPath = safetyPath;
        _backupPath = null;
        _loading = true;
      });
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Database restored successfully.'),
          duration: Duration(seconds: 4),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Restore failed: $error')),
      );
    } finally {
      if (mounted) setState(() => _restoring = false);
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _address.dispose();
    _gstin.dispose();
    _state.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Settings & Backup')),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  Text(
                    'Business profile',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _name,
                    decoration: const InputDecoration(labelText: 'Business name'),
                  ),
                  TextField(
                    controller: _phone,
                    decoration: const InputDecoration(labelText: 'Business phone'),
                    keyboardType: TextInputType.phone,
                  ),
                  TextField(
                    controller: _gstin,
                    decoration: const InputDecoration(labelText: 'GSTIN'),
                    textCapitalization: TextCapitalization.characters,
                  ),
                  DropdownButtonFormField<String>(
                    initialValue: IndianStates.all.contains(_state.text)
                        ? _state.text
                        : null,
                    decoration: const InputDecoration(
                      labelText: 'GST registration state *',
                      helperText: 'Select the state shown in your GST registration.',
                    ),
                    items: IndianStates.all.map((state) => DropdownMenuItem<String>(
                      value: state,
                      child: Text(state),
                    )).toList(),
                    validator: (value) => value == null
                        ? 'Select GST registration state'
                        : null,
                    onChanged: (value) => _state.text = value ?? '',
                  ),
                  TextField(
                    controller: _address,
                    decoration: const InputDecoration(labelText: 'Business address'),
                    maxLines: 3,
                  ),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: _save,
                    icon: const Icon(Icons.save),
                    label: const Text('Save business profile'),
                  ),
                  const Divider(height: 36),
                  Text(
                    'Local backup',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Create a copy of the local SQLite database in the '
                    'application documents folder. Keep another copy on a '
                    'separate safe device.',
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: _backup,
                    icon: const Icon(Icons.backup),
                    label: const Text('Create database backup'),
                  ),
                  if (_backupPath != null)
                    SelectableText('Backup location: $_backupPath'),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: _restoring ? null : _restore,
                    icon: _restoring
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.restore),
                    label: Text(
                      _restoring ? 'Restoring database...' : 'Restore database backup',
                    ),
                  ),
                  if (_restoreSafetyPath != null) ...[
                    const SizedBox(height: 8),
                    const Text(
                      'Safety copy of the database before restore:',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                    SelectableText(_restoreSafetyPath!),
                  ],
                  const SizedBox(height: 24),
                  const Text(
                    'Cloud synchronisation, staff sign-in, access enforcement, '
                    'invoice numbering settings and tax configuration are not '
                    'enabled yet.',
                  ),
                ],
              ),
      );
}
