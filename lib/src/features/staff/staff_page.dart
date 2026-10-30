import 'package:flutter/material.dart';
import '../../data/local/app_database.dart';

class StaffPage extends StatefulWidget {
  const StaffPage({super.key});
  @override
  State<StaffPage> createState() => _StaffPageState();
}
class _StaffPageState extends State<StaffPage> {
  List<Map<String, Object?>> _staff = [];
  bool _loading = true;
  @override
  void initState() { super.initState(); _load(); }
  Future<void> _load() async {
    final db = await AppDatabase.instance.database;
    final rows = await db.query('staff_members', orderBy: 'display_name COLLATE NOCASE');
    if (!mounted) return;
    setState(() { _staff = rows; _loading = false; });
  }
  Future<void> _add({Map<String, Object?>? member}) async {
    final name = TextEditingController(text: member?['display_name'] as String? ?? '');
    final phone = TextEditingController(text: member?['phone'] as String? ?? '');
    String role = member?['role'] as String? ?? 'staff';
    final key = GlobalKey<FormState>();
    final saved = await showDialog<bool>(context: context, builder: (ctx) => StatefulBuilder(builder: (ctx, refresh) => AlertDialog(
      title: Text(member == null ? 'Add staff member' : 'Edit staff member'),
      content: SizedBox(width: 400, child: Form(key: key, child: Column(mainAxisSize: MainAxisSize.min, children: [
        TextFormField(controller: name, decoration: const InputDecoration(labelText: 'Name *'), validator: (v) => v == null || v.trim().isEmpty ? 'Enter name' : null),
        TextFormField(controller: phone, decoration: const InputDecoration(labelText: 'Phone')),
        DropdownButtonFormField<String>(initialValue: role, decoration: const InputDecoration(labelText: 'Role label'), items: const [
          DropdownMenuItem(value: 'owner', child: Text('Owner')), DropdownMenuItem(value: 'manager', child: Text('Manager')), DropdownMenuItem(value: 'cashier', child: Text('Cashier')), DropdownMenuItem(value: 'staff', child: Text('Staff')),
        ], onChanged: (v) => refresh(() => role = v ?? 'staff')),
      ]))),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')), FilledButton(onPressed: () { if (key.currentState!.validate()) Navigator.pop(ctx, true); }, child: const Text('Save'))],
    )));
    if (saved == true) {
      final db = await AppDatabase.instance.database;
      final values = {'display_name': name.text.trim(), 'phone': phone.text.trim(), 'role': role};
      if (member == null) { await db.insert('staff_members', values); }
      else { await db.update('staff_members', values, where: 'id = ?', whereArgs: [member['id']]); }
      await _load();
    }
    name.dispose(); phone.dispose();
  }
  Future<void> _toggle(Map<String, Object?> member) async {
    final db = await AppDatabase.instance.database;
    final active = (member['is_active'] as int? ?? 1) == 1;
    await db.update('staff_members', {'is_active': active ? 0 : 1}, where: 'id = ?', whereArgs: [member['id']]);
    await _load();
  }
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Staff & Permissions')),
    floatingActionButton: FloatingActionButton.extended(onPressed: _add, icon: const Icon(Icons.person_add), label: const Text('Add staff')),
    body: _loading ? const Center(child: CircularProgressIndicator()) : Column(children: [
      const MaterialBanner(content: Text('Staff profiles and role labels only. Login authentication and enforced permissions are not yet enabled.'), actions: [SizedBox.shrink()]),
      Expanded(child: _staff.isEmpty ? const Center(child: Text('No staff profiles added.')) : ListView.separated(
        padding: const EdgeInsets.all(16), itemCount: _staff.length, separatorBuilder: (_, i) => const Divider(),
        itemBuilder: (ctx, i) { final m = _staff[i]; final active = (m['is_active'] as int? ?? 1) == 1; return ListTile(
          leading: CircleAvatar(child: Icon(active ? Icons.person : Icons.person_off)),
          title: Text(m['display_name'] as String), subtitle: Text('${m['role']} • ${active ? 'Active' : 'Inactive'} • ${m['phone'] ?? ''}'),
          onTap: () => _add(member: m), trailing: IconButton(tooltip: active ? 'Deactivate' : 'Activate', onPressed: () => _toggle(m), icon: Icon(active ? Icons.pause_circle_outline : Icons.play_circle_outline)),
        ); },
      )),
    ]),
  );
}
