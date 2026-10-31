import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class CompanySetupPage extends StatefulWidget {
  const CompanySetupPage({super.key});

  @override
  State<CompanySetupPage> createState() => _CompanySetupPageState();
}

class _CompanySetupPageState extends State<CompanySetupPage> {
  final _name = TextEditingController();
  final _legalName = TextEditingController();
  final _gstin = TextEditingController();
  bool _busy = false;
  String? _error;

  Future<void> _createCompany() async {
    final name = _name.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Enter a business name.');
      return;
    }
    final client = Supabase.instance.client;
    final user = client.auth.currentUser;
    if (user == null) {
      setState(() => _error = 'Your session has expired. Sign in again.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final business = await client
          .from('businesses')
          .insert({
            'name': name,
            'legal_name': _legalName.text.trim().isEmpty ? null : _legalName.text.trim(),
            'gstin': _gstin.text.trim().isEmpty ? null : _gstin.text.trim().toUpperCase(),
            'created_by': user.id,
          })
          .select('id')
          .single();

      await client.from('business_members').insert({
        'business_id': business['id'],
        'user_id': user.id,
        'role': 'owner',
      });
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on PostgrestException catch (error) {
      setState(() => _error = error.message);
    } catch (error) {
      setState(() => _error = 'Unable to create business: $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _legalName.dispose();
    _gstin.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Create business'),
        content: SizedBox(
          width: 420,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: _name,
                  decoration: const InputDecoration(labelText: 'Business name *'),
                ),
                TextField(
                  controller: _legalName,
                  decoration: const InputDecoration(labelText: 'Legal name (optional)'),
                ),
                TextField(
                  controller: _gstin,
                  textCapitalization: TextCapitalization.characters,
                  decoration: const InputDecoration(labelText: 'GSTIN (optional)'),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                ],
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: _busy ? null : () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: _busy ? null : _createCompany,
            child: _busy
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('Create'),
          ),
        ],
      );
}
