import 'package:flutter/material.dart';

import '../../data/local/gst_gstr3b_itc.dart';
import '../../data/local/gst_gstr3b_itc_repository.dart';

class Gstr3bItcPage extends StatefulWidget {
  const Gstr3bItcPage({super.key});

  @override
  State<Gstr3bItcPage> createState() => _Gstr3bItcPageState();
}

class _Gstr3bItcPageState extends State<Gstr3bItcPage> {
  final _periodController = TextEditingController(
    text: _currentPeriod(),
  );
  Gstr3bItcSummary? _summary;
  List<Map<String, Object?>> _reviewItems = const [];
  bool _loading = false;
  String? _error;

  static String _currentPeriod() {
    final now = DateTime.now();
    return '${now.year}-${now.month.toString().padLeft(2, '0')}';
  }

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  @override
  void dispose() {
    _periodController.dispose();
    super.dispose();
  }

  String _money(double value) => '₹${value.toStringAsFixed(2)}';

  String _taxText(Gstr3bTaxAmounts tax) =>
      'IGST ${_money(tax.igst)} • CGST ${_money(tax.cgst)} • '
      'SGST ${_money(tax.sgst)} • Cess ${_money(tax.cess)}';

  Future<void> _refresh() async {
    final period = _periodController.text.trim();
    if (!RegExp(r'^\d{4}-(0[1-9]|1[0-2])$').hasMatch(period)) {
      setState(() => _error = 'Return period YYYY-MM ফরম্যাটে লিখুন।');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await Future.wait([
        Gstr3bItcRepository.summarizePeriod(period),
        Gstr3bItcRepository.listPeriodReviewItems(period),
      ]);
      if (!mounted) return;
      setState(() {
        _summary = results[0] as Gstr3bItcSummary;
        _reviewItems = results[1] as List<Map<String, Object?>>;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = 'GSTR-3B ITC তথ্য লোড করা যায়নি: $error');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _addAdjustment() async {
    final formKey = GlobalKey<FormState>();
    final reference = TextEditingController();
    final igst = TextEditingController(text: '0');
    final cgst = TextEditingController(text: '0');
    final sgst = TextEditingController(text: '0');
    final cess = TextEditingController(text: '0');
    final notes = TextEditingController();
    var treatment = Gstr3bItcTreatment.reversalRules38_42_43And17_5;
    String? dialogError;

    double? amount(String value) {
      final parsed = double.tryParse(value.trim());
      if (parsed == null || !parsed.isFinite || parsed < 0) return null;
      return parsed;
    }

    try {
      final saved = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => StatefulBuilder(
          builder: (context, refreshDialog) => AlertDialog(
            title: const Text('ITC Reversal / Reclaim Entry'),
            content: SizedBox(
              width: 480,
              child: SingleChildScrollView(
                child: Form(
                  key: formKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextFormField(
                        controller: reference,
                        decoration: const InputDecoration(labelText: 'Document / Adjustment Reference *'),
                        validator: (value) => (value ?? '').trim().isEmpty
                            ? 'Reference প্রয়োজন'
                            : null,
                      ),
                      DropdownButtonFormField<Gstr3bItcTreatment>(
                        initialValue: treatment,
                        decoration: const InputDecoration(labelText: 'Adjustment Type'),
                        items: const [
                          DropdownMenuItem(
                            value: Gstr3bItcTreatment.reversalRules38_42_43And17_5,
                            child: Text('Table 4(B)(1) — Rules 38/42/43 and Section 17(5)'),
                          ),
                          DropdownMenuItem(
                            value: Gstr3bItcTreatment.reversalOther,
                            child: Text('Table 4(B)(2) — Other reversals'),
                          ),
                          DropdownMenuItem(
                            value: Gstr3bItcTreatment.reclaimedPreviousReversal,
                            child: Text('Table 4(D)(1) — Reclaimed previous reversal'),
                          ),
                        ],
                        onChanged: (value) {
                          if (value != null) refreshDialog(() => treatment = value);
                        },
                      ),
                      const SizedBox(height: 8),
                      TextFormField(
                        controller: igst,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: const InputDecoration(labelText: 'IGST'),
                        validator: (value) => amount(value ?? '') == null ? 'Valid non-negative amount দিন' : null,
                      ),
                      TextFormField(
                        controller: cgst,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: const InputDecoration(labelText: 'CGST'),
                        validator: (value) => amount(value ?? '') == null ? 'Valid non-negative amount দিন' : null,
                      ),
                      TextFormField(
                        controller: sgst,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: const InputDecoration(labelText: 'SGST'),
                        validator: (value) => amount(value ?? '') == null ? 'Valid non-negative amount দিন' : null,
                      ),
                      TextFormField(
                        controller: cess,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: const InputDecoration(labelText: 'Cess'),
                        validator: (value) => amount(value ?? '') == null ? 'Valid non-negative amount দিন' : null,
                      ),
                      TextFormField(
                        controller: notes,
                        maxLines: 2,
                        decoration: const InputDecoration(labelText: 'Notes / Legal basis (optional)'),
                      ),
                      if (dialogError != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Text(dialogError!, style: const TextStyle(color: Colors.red)),
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
                onPressed: () async {
                  if (!formKey.currentState!.validate()) return;
                  final tax = Gstr3bTaxAmounts(
                    igst: amount(igst.text)!,
                    cgst: amount(cgst.text)!,
                    sgst: amount(sgst.text)!,
                    cess: amount(cess.text)!,
                  );
                  if (tax.isZero) {
                    refreshDialog(() => dialogError = 'চারটি Tax Amount-এর মধ্যে অন্তত একটি শূন্যের বেশি হতে হবে।');
                    return;
                  }
                  try {
                    await Gstr3bItcRepository.addAdjustment(
                      documentReference: reference.text,
                      returnPeriod: _periodController.text.trim(),
                      treatment: treatment,
                      tax: tax,
                      notes: notes.text.trim().isEmpty ? null : notes.text.trim(),
                    );
                    if (dialogContext.mounted) Navigator.pop(dialogContext, true);
                  } catch (error) {
                    refreshDialog(() => dialogError = 'সংরক্ষণ করা যায়নি: $error');
                  }
                },
                child: const Text('Save Adjustment'),
              ),
            ],
          ),
        ),
      );
      if (saved == true) await _refresh();
    } finally {
      reference.dispose();
      igst.dispose();
      cgst.dispose();
      sgst.dispose();
      cess.dispose();
      notes.dispose();
    }
  }

  Widget _amountRow(String title, Gstr3bTaxAmounts value) => ListTile(
    dense: true,
    title: Text(title),
    subtitle: Text(_taxText(value)),
  );

  Widget _summaryCard(Gstr3bItcSummary summary) => Card(
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Table 4(A) — ITC Available', style: Theme.of(context).textTheme.titleMedium),
          _amountRow('4(A)(1) Import of Goods', summary.importGoods),
          _amountRow('4(A)(2) Import of Services', summary.importServices),
          _amountRow('4(A)(3) Reverse Charge', summary.reverseCharge),
          _amountRow('4(A)(4) ISD', summary.inputServiceDistributor),
          _amountRow('4(A)(5) Other Eligible ITC / Reclaim', summary.other),
          const Divider(),
          _amountRow('Total 4(A)', summary.totalAvailable),
          Text('Table 4(B) — ITC Reversal', style: Theme.of(context).textTheme.titleMedium),
          _amountRow('4(B)(1) Rules 38/42/43 and Section 17(5)', summary.reversalRules),
          _amountRow('4(B)(2) Other Reversals', summary.reversalOther),
          _amountRow('Total 4(B)', summary.totalReversed),
          const Divider(),
          _amountRow('Table 4(C) — Net ITC', summary.netItc),
          Text('Table 4(D) — Other ITC Disclosure', style: Theme.of(context).textTheme.titleMedium),
          _amountRow('4(D)(1) Reclaimed ITC', summary.reclaimedPreviousReversal),
          _amountRow('4(D)(2) Ineligible ITC', summary.ineligible),
          const Divider(),
          Text(
            'Pending review: ${summary.pendingReviewCount} • Data issues: ${summary.issues.length}',
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          Text(
            summary.canPrepareDraft
                ? 'বর্তমান সংরক্ষিত তথ্যের প্রাথমিক পরীক্ষা সম্পন্ন। GST Portal-এ দাখিলের আগে মূল নথি ও GSTR-2B মিলিয়ে নিন।'
                : 'Draft প্রস্তুতির আগে Pending Review ও Data Issue সমাধান করুন।',
          ),
          for (final issue in summary.issues)
            Text(issue, style: const TextStyle(color: Colors.red)),
          const SizedBox(height: 6),
          const Text('এটি অভ্যন্তরীণ প্রস্তুতি ও হিসাব-সহায়ক স্ক্রিন; GSTN-এর সরকারি Return JSON বা সরাসরি Filing নয়। RCM tax payment এবং statutory eligibility আলাদাভাবে যাচাই করুন।'),
        ],
      ),
    ),
  );

  Widget _reviewCard() => Card(
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Review Required', style: Theme.of(context).textTheme.titleMedium),
          if (_reviewItems.isEmpty)
            const Text('এই সময়ের জন্য কোনো Pending Review / GSTR-2B mismatch রেকর্ড নেই।')
          else
            for (final row in _reviewItems)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.warning_amber_outlined, color: Colors.orange),
                title: Text('${row['supplier_invoice_number']} • ${row['supplier_name'] ?? 'Supplier'}'),
                subtitle: Text(
                  'GSTIN: ${row['supplier_gstin'] ?? 'Missing'} • '
                  'ITC: ${row['treatment']} • GSTR-2B: ${row['gstr2b_status']}',
                ),
                trailing: Text(_money((row['igst'] as num).toDouble() + (row['cgst'] as num).toDouble() + (row['sgst'] as num).toDouble() + (row['cess'] as num).toDouble())),
              ),
        ],
      ),
    ),
  );

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('GSTR-3B ITC Preparation'),
      actions: [
        IconButton(
          tooltip: 'Refresh ITC data',
          onPressed: _loading ? null : _refresh,
          icon: const Icon(Icons.refresh),
        ),
      ],
    ),
    floatingActionButton: FloatingActionButton.extended(
      onPressed: _addAdjustment,
      icon: const Icon(Icons.add),
      label: const Text('Add Reversal / Reclaim'),
    ),
    body: ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Return Period', style: Theme.of(context).textTheme.titleMedium),
                TextFormField(
                  controller: _periodController,
                  decoration: const InputDecoration(hintText: 'YYYY-MM', labelText: 'GSTR-3B Period'),
                  onFieldSubmitted: (_) => _refresh(),
                ),
                const SizedBox(height: 8),
                FilledButton.icon(
                  onPressed: _loading ? null : _refresh,
                  icon: const Icon(Icons.calculate),
                  label: const Text('Calculate Table 4'),
                ),
              ],
            ),
          ),
        ),
        if (_loading) const Center(child: Padding(
          padding: EdgeInsets.all(24), child: CircularProgressIndicator(),
        )),
        if (_error != null) Card(child: Padding(
          padding: const EdgeInsets.all(12),
          child: Text(_error!, style: const TextStyle(color: Colors.red)),
        )),
        if (_summary != null) _summaryCard(_summary!),
        _reviewCard(),
      ],
    ),
  );
}
