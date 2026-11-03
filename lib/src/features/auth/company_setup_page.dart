import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../data/indian_states.dart';

class CompanySetupPage extends StatefulWidget {
  const CompanySetupPage({super.key});

  @override
  State<CompanySetupPage> createState() => _CompanySetupPageState();
}

class _CompanySetupPageState extends State<CompanySetupPage> {
  final _formKeys = List.generate(3, (_) => GlobalKey<FormState>());
  final _name = TextEditingController();
  final _legalName = TextEditingController();
  final _phone = TextEditingController();
  final _email = TextEditingController();
  final _address = TextEditingController();
  final _city = TextEditingController();
  final _district = TextEditingController();
  final _postalCode = TextEditingController();
  final _pan = TextEditingController();
  final _gstin = TextEditingController();

  static const _businessTypes = <String, String>{
    'proprietorship': 'Sole proprietorship',
    'partnership': 'Partnership',
    'llp': 'Limited liability partnership (LLP)',
    'private_limited': 'Private limited company',
    'public_limited': 'Public limited company',
    'trust': 'Trust',
    'society': 'Society',
    'other': 'Other',
  };
  static const _gstTypes = <String, String>{
    'regular': 'Regular',
    'composition': 'Composition',
    'casual': 'Casual taxable person',
    'non_resident': 'Non-resident taxable person',
    'unregistered': 'Not registered for GST',
  };

  int _step = 0;
  String? _businessType;
  String? _state;
  String? _gstType;
  bool _busy = false;
  String? _error;

  String? _optionalPattern(String value, String pattern, String message) {
    if (value.trim().isEmpty) return null;
    return RegExp(pattern).hasMatch(value.trim()) ? null : message;
  }

  Future<void> _next() async {
    if (!_formKeys[_step].currentState!.validate()) return;
    if (_step < 2) {
      setState(() { _step++; _error = null; });
      return;
    }
    await _createCompany();
  }

  Future<void> _createCompany() async {
    final client = Supabase.instance.client;
    final user = client.auth.currentUser;
    if (user == null) {
      setState(() => _error = 'Your session has expired. Sign in again.');
      return;
    }
    final gstin = _gstin.text.trim().toUpperCase();
    if (gstin.isNotEmpty && (_state == null || !IndianStates.gstinMatchesState(gstin, _state!))) {
      setState(() {
        _step = 2;
        _error = 'GSTIN is invalid or its state code does not match the selected state.';
      });
      return;
    }
    final pan = _pan.text.trim().toUpperCase();
    if (pan.isNotEmpty && !RegExp(r'^[A-Z]{5}[0-9]{4}[A-Z]$').hasMatch(pan)) {
      setState(() { _step = 2; _error = 'Enter a valid PAN, or leave it blank.'; });
      return;
    }
    setState(() { _busy = true; _error = null; });
    try {
      final business = await client.from('businesses').insert({
        'name': _name.text.trim(),
        'legal_name': _legalName.text.trim().isEmpty ? null : _legalName.text.trim(),
        'business_type': _businessType,
        'phone': _phone.text.trim().isEmpty ? null : _phone.text.trim(),
        'email': _email.text.trim().isEmpty ? null : _email.text.trim().toLowerCase(),
        'address': _address.text.trim().isEmpty ? null : _address.text.trim(),
        'city': _city.text.trim().isEmpty ? null : _city.text.trim(),
        'district': _district.text.trim().isEmpty ? null : _district.text.trim(),
        'postal_code': _postalCode.text.trim().isEmpty ? null : _postalCode.text.trim(),
        'state_name': _state,
        'pan': pan.isEmpty ? null : pan,
        'gstin': gstin.isEmpty ? null : gstin,
        'state_code': gstin.isEmpty ? null : gstin.substring(0, 2),
        'gst_registration_type': _gstType,
        'created_by': user.id,
      }).select('id').single();

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
    for (final controller in [
      _name, _legalName, _phone, _email, _address, _city, _district,
      _postalCode, _pan, _gstin,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  Widget _field(TextEditingController controller, String label, {
    TextInputType? keyboardType,
    String? Function(String?)? validator,
    int maxLines = 1,
    TextCapitalization capitalization = TextCapitalization.none,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      validator: validator,
      maxLines: maxLines,
      textCapitalization: capitalization,
      decoration: InputDecoration(labelText: label),
    ),
  );

  String? _required(String? value) =>
      value == null || value.trim().isEmpty ? 'This field is required.' : null;

  @override
  Widget build(BuildContext context) => Dialog(
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 560, maxHeight: 700),
      child: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(22, 20, 12, 8),
          child: Row(children: [
            const Expanded(child: Text('Set up your business', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800))),
            IconButton(onPressed: _busy ? null : () => Navigator.pop(context, false), icon: const Icon(Icons.close)),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 22),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Step ${_step + 1} of 3  •  ${['Business identity', 'Business address', 'Tax and registration'][_step]}'),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(value: (_step + 1) / 3, minHeight: 6),
            ),
          ]),
        ),
        Expanded(
          child: Form(
            key: _formKeys[_step],
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(22, 18, 22, 12),
              child: [
                Column(children: [
                  _field(_name, 'Business / trade name *', validator: _required, capitalization: TextCapitalization.words),
                  _field(_legalName, 'Legal name (as per PAN, optional)', capitalization: TextCapitalization.words),
                  DropdownButtonFormField<String>(
                    initialValue: _businessType,
                    decoration: const InputDecoration(labelText: 'Business constitution'),
                    items: _businessTypes.entries.map((e) => DropdownMenuItem(value: e.key, child: Text(e.value))).toList(),
                    onChanged: _busy ? null : (v) => setState(() => _businessType = v),
                  ),
                  const SizedBox(height: 12),
                  _field(_phone, 'Mobile / business phone', keyboardType: TextInputType.phone,
                    validator: (v) => _optionalPattern(v ?? '', r'^[0-9+() -]{7,18}$', 'Enter a valid phone number.')),
                  _field(_email, 'Email address', keyboardType: TextInputType.emailAddress,
                    validator: (v) => _optionalPattern(v ?? '', r'^[^\s@]+@[^\s@]+\.[^\s@]+$', 'Enter a valid email address.')),
                ]),
                Column(children: [
                  _field(_address, 'Address / premises', maxLines: 3, capitalization: TextCapitalization.sentences),
                  _field(_city, 'City / town', capitalization: TextCapitalization.words),
                  _field(_district, 'District', capitalization: TextCapitalization.words),
                  _field(_postalCode, 'PIN code', keyboardType: TextInputType.number,
                    validator: (v) => _optionalPattern(v ?? '', r'^[1-9][0-9]{5}$', 'Enter a valid 6-digit PIN code.')),
                  DropdownButtonFormField<String>(
                    initialValue: _state,
                    decoration: const InputDecoration(labelText: 'State / Union Territory'),
                    items: IndianStates.all.map((s) => DropdownMenuItem(value: s, child: Text(s))).toList(),
                    onChanged: _busy ? null : (v) => setState(() => _state = v),
                  ),
                ]),
                Column(children: [
                  _field(_pan, 'PAN (optional)', capitalization: TextCapitalization.characters,
                    validator: (v) => _optionalPattern(v ?? '', r'^[A-Za-z]{5}[0-9]{4}[A-Za-z]$', 'Enter a valid PAN.')),
                  _field(_gstin, 'GSTIN (optional)', capitalization: TextCapitalization.characters,
                    validator: (v) {
                      final value = (v ?? '').trim().toUpperCase();
                      if (value.isEmpty) return null;
                      if (!RegExp(r'^[0-9]{2}[A-Z]{5}[0-9]{4}[A-Z][1-9A-Z]Z[0-9A-Z]$').hasMatch(value)) return 'Enter a valid 15-character GSTIN.';
                      if (_state == null || !IndianStates.gstinMatchesState(value, _state!)) return 'GSTIN state code must match the selected state.';
                      return null;
                    }),
                  DropdownButtonFormField<String>(
                    initialValue: _gstType,
                    decoration: const InputDecoration(labelText: 'GST registration type'),
                    items: _gstTypes.entries.map((e) => DropdownMenuItem(value: e.key, child: Text(e.value))).toList(),
                    onChanged: _busy ? null : (v) => setState(() => _gstType = v),
                  ),
                  const SizedBox(height: 12),
                  const Text('You can leave tax details blank if they do not apply. Existing invoices and records are not changed by this setup.', style: TextStyle(fontSize: 12)),
                ]),
              ][_step],
            ),
          ),
        ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 6),
            child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: Row(children: [
            TextButton(
              onPressed: _busy ? null : (_step == 0 ? () => Navigator.pop(context, false) : () => setState(() { _step--; _error = null; })),
              child: Text(_step == 0 ? 'Cancel' : 'Back'),
            ),
            const Spacer(),
            FilledButton(
              onPressed: _busy ? null : _next,
              child: _busy
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : Text(_step == 2 ? 'Create business' : 'Continue'),
            ),
          ]),
        ),
      ]),
    ),
  );
}
