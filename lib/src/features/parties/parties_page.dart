import 'package:flutter/material.dart';

import '../../data/local/app_database.dart';

class PartiesPage extends StatefulWidget {
  const PartiesPage({super.key});

  @override
  State<PartiesPage> createState() => _PartiesPageState();
}

class _PartiesPageState extends State<PartiesPage> {
  List<Map<String, Object?>> _parties = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadParties();
  }

  Future<void> _loadParties() async {
    final db = await AppDatabase.instance.database;
    final rows = await db.query('parties', orderBy: 'name COLLATE NOCASE');
    if (!mounted) return;
    setState(() {
      _parties = rows;
      _loading = false;
    });
  }

  Future<void> _showPartyForm({Map<String, Object?>? party}) async {
    final formKey = GlobalKey<FormState>();
    final name = TextEditingController(text: party?['name'] as String? ?? '');
    final phone = TextEditingController(text: party?['phone'] as String? ?? '');
    final email = TextEditingController(text: party?['email'] as String? ?? '');
    final address = TextEditingController(text: party?['address'] as String? ?? '');
    final gstin = TextEditingController(text: party?['gstin'] as String? ?? '');
    var type = party?['party_type'] as String? ?? 'customer';

    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(party == null ? 'Add party' : 'Edit party'),
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
                    decoration: const InputDecoration(labelText: 'Name *'),
                    validator: (value) =>
                        value == null || value.trim().isEmpty ? 'Enter a name' : null,
                  ),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<String>(
                    initialValue: type,
                    decoration: const InputDecoration(labelText: 'Party type'),
                    items: const [
                      DropdownMenuItem(value: 'customer', child: Text('Customer')),
                      DropdownMenuItem(value: 'supplier', child: Text('Supplier')),
                      DropdownMenuItem(value: 'both', child: Text('Customer & Supplier')),
                    ],
                    onChanged: (value) {
                      if (value != null) type = value;
                    },
                  ),
                  TextFormField(controller: phone, decoration: const InputDecoration(labelText: 'Phone'), keyboardType: TextInputType.phone),
                  TextFormField(controller: email, decoration: const InputDecoration(labelText: 'Email'), keyboardType: TextInputType.emailAddress),
                  TextFormField(controller: gstin, decoration: const InputDecoration(labelText: 'GSTIN'), textCapitalization: TextCapitalization.characters),
                  TextFormField(controller: address, decoration: const InputDecoration(labelText: 'Address'), maxLines: 2),
                ],
              ),
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancel')),
          FilledButton(
            onPressed: () {
              if (formKey.currentState!.validate()) Navigator.pop(dialogContext, true);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );

    if (saved == true) {
      final db = await AppDatabase.instance.database;
      final values = <String, Object?>{
        'name': name.text.trim(),
        'party_type': type,
        'phone': phone.text.trim(),
        'email': email.text.trim(),
        'address': address.text.trim(),
        'gstin': gstin.text.trim().toUpperCase(),
        'updated_at': DateTime.now().toIso8601String(),
      };
      if (party == null) {
        await db.insert('parties', values);
      } else {
        await db.update('parties', values, where: 'id = ?', whereArgs: [party['id']]);
      }
      await _loadParties();
    }

    name.dispose();
    phone.dispose();
    email.dispose();
    address.dispose();
    gstin.dispose();
  }

  Future<void> _deleteParty(Map<String, Object?> party) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete party?'),
        content: Text('Delete ' + (party['name'] as String) + ' from this device?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('Delete')),
        ],
      ),
    );
    if (confirmed != true) return;
    final db = await AppDatabase.instance.database;
    await db.delete('parties', where: 'id = ?', whereArgs: [party['id']]);
    await _loadParties();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Customers & Suppliers')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showPartyForm,
        icon: const Icon(Icons.person_add),
        label: const Text('Add party'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _parties.isEmpty
              ? const Center(child: Text('No parties added yet. Tap Add party to begin.'))
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 88),
                  itemCount: _parties.length,
                  separatorBuilder: (_, index) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final party = _parties[index];
                    final phone = party['phone'] as String? ?? '';
                    final type = (party['party_type'] as String? ?? 'customer').replaceAll('_', ' ');
                    return ListTile(
                      leading: const CircleAvatar(child: Icon(Icons.person_outline)),
                      title: Text(party['name'] as String),
                      subtitle: Text([type, phone].where((v) => v.isNotEmpty).join(' • ')),
                      onTap: () => _showPartyForm(party: party),
                      trailing: IconButton(
                        tooltip: 'Delete party',
                        icon: const Icon(Icons.delete_outline),
                        onPressed: () => _deleteParty(party),
                      ),
                    );
                  },
                ),
    );
  }
}
