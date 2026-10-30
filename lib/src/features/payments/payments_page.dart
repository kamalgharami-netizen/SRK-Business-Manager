import 'package:flutter/material.dart';
import '../../data/local/app_database.dart';

class PaymentsPage extends StatefulWidget {
  const PaymentsPage({super.key});
  @override
  State<PaymentsPage> createState() => _PaymentsPageState();
}

class _PaymentsPageState extends State<PaymentsPage> {
  List<Map<String, Object?>> _rows = [];
  bool _loading = true;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    final db = await AppDatabase.instance.database;
    final rows = await db.rawQuery('SELECT payments.*, parties.name AS party_name, invoices.invoice_number FROM payments LEFT JOIN parties ON parties.id = payments.party_id LEFT JOIN invoices ON invoices.id = payments.invoice_id ORDER BY payments.id DESC');
    if (!mounted) return;
    setState(() { _rows = rows; _loading = false; });
  }

  Future<void> _add(String type) async {
    final db = await AppDatabase.instance.database;
    final parties = await db.query('parties', where: type == 'receipt' ? "party_type IN ('customer','both')" : "party_type IN ('supplier','both')", orderBy: 'name');
    final invoices = await db.query('invoices', where: type == 'receipt' ? "invoice_type = 'sale'" : "invoice_type = 'purchase'", orderBy: 'id DESC');
    if (!mounted) return;
    int? partyId;
    int? invoiceId;
    String mode = 'cash';
    final amount = TextEditingController();
    final reference = TextEditingController();
    final notes = TextEditingController();
    final key = GlobalKey<FormState>();
    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, refresh) => AlertDialog(
          title: Text(type == 'receipt' ? 'Record receipt' : 'Record payment'),
          content: SizedBox(
            width: 420,
            child: Form(
              key: key,
              child: SingleChildScrollView(
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  DropdownButtonFormField<int>(
                    initialValue: partyId,
                    decoration: const InputDecoration(labelText: 'Party'),
                    items: parties.map((p) => DropdownMenuItem(value: p['id'] as int, child: Text(p['name'] as String))).toList(),
                    onChanged: (v) => refresh(() => partyId = v),
                  ),
                  DropdownButtonFormField<int>(
                    initialValue: invoiceId,
                    decoration: const InputDecoration(labelText: 'Link invoice (optional)'),
                    items: invoices.map((p) => DropdownMenuItem(value: p['id'] as int, child: Text(p['invoice_number'] as String))).toList(),
                    onChanged: (v) => refresh(() => invoiceId = v),
                  ),
                  TextFormField(
                    controller: amount,
                    decoration: const InputDecoration(labelText: 'Amount (₹) *'),
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    validator: (v) { final n = double.tryParse(v ?? ''); return n == null || n <= 0 ? 'Enter an amount greater than zero' : null; },
                  ),
                  DropdownButtonFormField<String>(
                    initialValue: mode,
                    decoration: const InputDecoration(labelText: 'Payment mode'),
                    items: const [
                      DropdownMenuItem(value: 'cash', child: Text('Cash')),
                      DropdownMenuItem(value: 'upi', child: Text('UPI')),
                      DropdownMenuItem(value: 'bank', child: Text('Bank transfer')),
                      DropdownMenuItem(value: 'card', child: Text('Card')),
                      DropdownMenuItem(value: 'cheque', child: Text('Cheque')),
                    ],
                    onChanged: (v) => refresh(() => mode = v ?? 'cash'),
                  ),
                  TextFormField(controller: reference, decoration: const InputDecoration(labelText: 'Reference / Transaction ID')),
                  TextFormField(controller: notes, decoration: const InputDecoration(labelText: 'Notes')),
                ]),
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            FilledButton(onPressed: () { if (key.currentState!.validate()) Navigator.pop(ctx, true); }, child: const Text('Save')),
          ],
        ),
      ),
    );
    if (saved == true) {
      final value = double.parse(amount.text);
      await db.transaction((txn) async {
        await txn.insert('payments', {
          'party_id': partyId, 'invoice_id': invoiceId, 'payment_type': type,
          'payment_date': DateTime.now().toIso8601String(), 'amount': value,
          'mode': mode, 'reference': reference.text.trim(), 'notes': notes.text.trim(),
        });
        if (invoiceId != null) {
          final found = await txn.query('invoices', where: 'id = ?', whereArgs: [invoiceId], limit: 1);
          if (found.isNotEmpty) {
            final invoice = found.first;
            final paid = ((invoice['amount_paid'] as num?) ?? 0).toDouble() + value;
            final total = ((invoice['grand_total'] as num?) ?? 0).toDouble();
            await txn.update('invoices', {'amount_paid': paid, 'status': paid >= total ? 'paid' : 'partial'}, where: 'id = ?', whereArgs: [invoiceId]);
          }
        }
      });
      await _load();
    }
    amount.dispose();
    reference.dispose();
    notes.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Receipts & Payments')),
    floatingActionButton: Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.end, children: [
        FloatingActionButton.extended(heroTag: 'receipt', onPressed: () => _add('receipt'), icon: const Icon(Icons.call_received), label: const Text('Receipt')),
        const SizedBox(height: 10),
        FloatingActionButton.extended(heroTag: 'payment', onPressed: () => _add('payment'), icon: const Icon(Icons.call_made), label: const Text('Payment')),
      ]),
    ),
    body: _loading ? const Center(child: CircularProgressIndicator()) : _rows.isEmpty
      ? const Center(child: Text('No receipts or payments recorded yet.'))
      : ListView.separated(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 150),
          itemCount: _rows.length,
          separatorBuilder: (_, i) => const Divider(),
          itemBuilder: (ctx, i) {
            final row = _rows[i];
            final receipt = row['payment_type'] == 'receipt';
            final value = (row['amount'] as num).toDouble();
            return ListTile(
              leading: CircleAvatar(child: Icon(receipt ? Icons.call_received : Icons.call_made)),
              title: Text('${receipt ? 'Receipt' : 'Payment'} • ${row['party_name'] ?? 'Unlinked party'}'),
              subtitle: Text('${row['payment_date'].toString().split('T').first} • ${row['mode']} • ${row['invoice_number'] ?? 'No invoice linked'}'),
              trailing: Text('₹${value.toStringAsFixed(2)}', style: TextStyle(fontWeight: FontWeight.w600, color: receipt ? Colors.green : Colors.red)),
            );
          },
        ),
  );
}
