import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:sqflite/sqflite.dart' show ConflictAlgorithm;

import '../../data/local/app_database.dart';
import '../../data/sync/business_sync_service.dart';
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
    final selectedState = _state.text.trim();
    final gstin = _gstin.text.trim().toUpperCase();
    if (gstin.isNotEmpty && !IndianStates.all.contains(selectedState)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Select a valid GST registration state.')),
      );
      return;
    }
    if (gstin.isNotEmpty && !IndianStates.gstinMatchesState(gstin, selectedState)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('GSTIN format or its State Code does not match the selected GST registration state.'),
        ),
      );
      return;
    }
    final database = AppDatabase.instance;
    final businessId = database.activeBusinessId;
    if (businessId != null && !database.canWriteCloudEntity('business_profile')) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Only the business owner or admin can change the shared business profile.'),
        ),
      );
      return;
    }
    final db = await database.database;
    final values = {
      'company_name': _name.text.trim(),
      'company_phone': _phone.text.trim(),
      'company_address': _address.text.trim(),
      'company_gstin': gstin,
      'company_state': selectedState,
    };
    await db.transaction((txn) async {
      for (final entry in values.entries) {
        await txn.insert(
          'app_settings',
          {'setting_key': entry.key, 'setting_value': entry.value},
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
      if (businessId != null) {
        await database.enqueueSyncOperation(
          tableName: 'business_profile',
          recordId: businessId,
          operation: 'update',
          payload: {'sync_id': businessId, ...values},
          executor: txn,
        );
      }
    });
    var saveMessage = 'Business profile saved on this device.';
    if (businessId != null) {
      saveMessage = 'Business profile saved locally; cloud sync is pending.';
      try {
        final result = await BusinessSyncService(businessId: businessId).syncNow();
        if (result.uploadFailures == 0) {
          saveMessage = 'Business profile saved and synchronised with the cloud.';
        }
      } catch (_) {
        // The durable local queue is retained for the next sync attempt.
      }
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(saveMessage)),
    );
  }

  Future<void> _backup() async {
    try {
      final destination = await FilePicker.platform.saveFile(
        dialogTitle: 'Choose backup location',
        fileName: 'srk-business-manager-backup.db',
        type: FileType.custom,
        allowedExtensions: ['db'],
      );
      if (destination == null || destination.trim().isEmpty) return;
      final temporaryBackup = await AppDatabase.instance.createBackup();
      final destinationFile = File(destination);
      if (await destinationFile.exists()) {
        throw StateError('A file already exists at the selected backup location.');
      }
      await File(temporaryBackup).copy(destinationFile.path);
      if (!mounted) return;
      setState(() => _backupPath = destinationFile.path);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Database backup saved to the selected location.')),
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

  Widget _settingsSection({
    required String title,
    required String subtitle,
    required IconData icon,
    required List<Widget> children,
  }) => Card(
    elevation: 5,
    shadowColor: const Color(0xFF173B70).withValues(alpha: .09),
    child: Padding(
      padding: const EdgeInsets.all(18),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            width: 44, height: 44,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFFE5EEFF), Color(0xFFF7FAFF)],
              ),
              borderRadius: BorderRadius.circular(14),
              boxShadow: const [BoxShadow(color: Color(0x182457A7), blurRadius: 9, offset: Offset(0, 3))],
            ),
            child: Icon(icon, color: const Color(0xFF2457A7)),
          ),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: Color(0xFF102A56))),
            const SizedBox(height: 3),
            Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
          ])),
        ]),
        const SizedBox(height: 18),
        ...children,
      ]),
    ),
  );

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Settings'),
      actions: [
        IconButton(
          tooltip: 'Save business profile',
          onPressed: _loading ? null : _save,
          icon: const Icon(Icons.save_outlined),
        ),
        const SizedBox(width: 8),
      ],
    ),
    body: _loading
      ? const Center(child: CircularProgressIndicator())
      : LayoutBuilder(builder: (context, constraints) {
          final horizontal = constraints.maxWidth > 720 ? 28.0 : 14.0;
          return ListView(
            padding: EdgeInsets.fromLTRB(horizontal, 18, horizontal, 36),
            children: [
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft, end: Alignment.bottomRight,
                    colors: [Color(0xFF102A56), Color(0xFF2869C4), Color(0xFF5B91DC)],
                  ),
                  borderRadius: BorderRadius.circular(23),
                  boxShadow: const [BoxShadow(color: Color(0x332457A7), blurRadius: 18, offset: Offset(0, 8))],
                ),
                child: const Row(children: [
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('WORKSPACE CONTROL CENTRE', style: TextStyle(color: Colors.white70, fontSize: 10, letterSpacing: 1.1, fontWeight: FontWeight.w800)),
                    SizedBox(height: 7),
                    Text('Business settings', style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w900)),
                    SizedBox(height: 5),
                    Text('Manage your business profile and protect your data.', style: TextStyle(color: Colors.white70, fontSize: 12)),
                  ])),
                  Icon(Icons.tune_rounded, color: Colors.white, size: 42),
                ]),
              ),
              const SizedBox(height: 16),
              _settingsSection(
                title: 'Business profile',
                subtitle: 'Identity and contact details used in your business records.',
                icon: Icons.storefront_rounded,
                children: [
                  TextField(controller: _name, textCapitalization: TextCapitalization.words, decoration: const InputDecoration(labelText: 'Business name', prefixIcon: Icon(Icons.business))),
                  const SizedBox(height: 12),
                  TextField(controller: _phone, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'Business phone', prefixIcon: Icon(Icons.phone_outlined))),
                  const SizedBox(height: 12),
                  TextField(controller: _address, maxLines: 3, decoration: const InputDecoration(labelText: 'Business address', alignLabelWithHint: true, prefixIcon: Icon(Icons.location_on_outlined))),
                  const SizedBox(height: 14),
                  SizedBox(width: double.infinity, child: FilledButton.icon(onPressed: _save, icon: const Icon(Icons.save_rounded), label: const Text('Save business profile'))),
                ],
              ),
              const SizedBox(height: 14),
              _settingsSection(
                title: 'GST registration details',
                subtitle: 'Enter GSTIN and registration state only when applicable to your business.',
                icon: Icons.receipt_long_rounded,
                children: [
                  TextField(controller: _gstin, textCapitalization: TextCapitalization.characters, decoration: const InputDecoration(labelText: 'GSTIN (optional)', prefixIcon: Icon(Icons.verified_outlined), helperText: 'Leave blank if your business does not have a GSTIN.')),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: IndianStates.all.contains(_state.text) ? _state.text : null,
                    decoration: const InputDecoration(labelText: 'GST registration state (required when GSTIN is entered)', prefixIcon: Icon(Icons.map_outlined)),
                    items: IndianStates.all.map((state) => DropdownMenuItem<String>(value: state, child: Text(state))).toList(),
                    onChanged: (value) => _state.text = value ?? '',
                  ),
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(color: const Color(0xFFFFF7E8), borderRadius: BorderRadius.circular(13), border: Border.all(color: const Color(0xFFF3D7A4))),
                    child: const Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Icon(Icons.info_outline, color: Color(0xFF9A6500), size: 19),
                      SizedBox(width: 9),
                      Expanded(child: Text('Note: an empty GSTIN field does not switch off GST calculations or GST modules. A separate GST enable/disable control must be connected to invoice and tax logic before it can safely be offered.', style: TextStyle(fontSize: 12, height: 1.4))),
                    ]),
                  ),
                  const SizedBox(height: 14),
                  SizedBox(width: double.infinity, child: OutlinedButton.icon(onPressed: _save, icon: const Icon(Icons.verified_user_outlined), label: const Text('Validate and save GST details'))),
                ],
              ),
              const SizedBox(height: 14),
              _settingsSection(
                title: 'Backup & restore',
                subtitle: 'Create a local database copy or restore from a saved backup.',
                icon: Icons.shield_outlined,
                children: [
                  const Text('Keep a backup in a separate safe location. Restoring replaces the current local database; a safety copy is created automatically first.', style: TextStyle(height: 1.45)),
                  const SizedBox(height: 14),
                  SizedBox(width: double.infinity, child: FilledButton.tonalIcon(onPressed: _backup, icon: const Icon(Icons.backup_rounded), label: const Text('Create database backup'))),
                  if (_backupPath != null) ...[
                    const SizedBox(height: 8),
                    SelectableText('Backup location: $_backupPath'),
                  ],
                  const SizedBox(height: 10),
                  SizedBox(width: double.infinity, child: OutlinedButton.icon(
                    onPressed: _restoring ? null : _restore,
                    icon: _restoring ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.restore_rounded),
                    label: Text(_restoring ? 'Restoring database...' : 'Restore database backup'),
                  )),
                  if (_restoreSafetyPath != null) ...[
                    const SizedBox(height: 10),
                    const Text('Safety copy created before restore:', style: TextStyle(fontWeight: FontWeight.w700)),
                    SelectableText(_restoreSafetyPath!),
                  ],
                ],
              ),
              const SizedBox(height: 14),
              _settingsSection(
                title: 'Cloud workspace & access',
                subtitle: 'How profile changes are handled across your connected devices.',
                icon: Icons.cloud_sync_rounded,
                children: [
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(AppDatabase.instance.activeBusinessId == null ? Icons.cloud_off : Icons.cloud_done, color: const Color(0xFF2457A7)),
                    title: Text(AppDatabase.instance.activeBusinessId == null ? 'Local business workspace' : 'Cloud business workspace'),
                    subtitle: Text(AppDatabase.instance.activeBusinessId == null ? 'This profile is saved on this device.' : 'Profile changes are queued locally and synchronised when cloud access is available.'),
                  ),
                  const Text('Only the business owner or admin can change the shared cloud business profile. Staff permissions and sync conflict resolution are managed in their respective modules.', style: TextStyle(fontSize: 12, height: 1.45)),
                ],
              ),
              const SizedBox(height: 18),
              const Center(child: Text('SRK Business Manager • Settings', style: TextStyle(color: Color(0xFF718096), fontSize: 11, fontWeight: FontWeight.w600))),
            ],
          );
        }),
  );

}
