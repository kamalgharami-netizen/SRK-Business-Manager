import 'package:flutter/material.dart';
import '../../data/local/app_database.dart';

class PurchasesPage extends StatefulWidget {
  const PurchasesPage({super.key});
  @override
  State<PurchasesPage> createState() => _PurchasesPageState();
}

class _PurchasesPageState extends State<PurchasesPage> {
  List<Map<String, Object?>> _rows = [];
  bool _loading = true;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    final db = await AppDatabase.instance.database;
    final rows = await db.rawQuery("""
      SELECT invoices.*, parties.name AS party_name
      FROM invoices LEFT JOIN parties ON parties.id = invoices.party_id
      WHERE invoices.invoice_type = 'purchase'
      ORDER BY invoices.id DESC
    """);
    if (!mounted) return;
    setState(() { _rows = rows; _loading = false; });
  }

  Future<void> _add() async {
    final db = await AppDatabase.instance.database;
    final suppliers = await db.query('parties', where: "party_type IN ('supplier','both')", orderBy: 'name');
    final products = await db.query('products', orderBy: 'name');
    if (!mounted) return;
    if (products.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Add products before recording a purchase.')));
      return;
    }
    int? supplierId;
    int? productId = products.first['id'] as int;
    final qty = TextEditingController(text: '1');
    final rate = TextEditingController(text: ((products.first['purchase_price'] as num?) ?? 0).toString());
    final gst = TextEditingController(text: ((products.first['gst_rate'] as num?) ?? 0).toString());
    final note = TextEditingController();
    final key = GlobalKey<FormState>();
    final saved = await showDialog<bool>(context: context, builder: (ctx) => StatefulBuilder(builder: (ctx, refresh) => AlertDialog(
      title: const Text('Record purchase'),
      content: SizedBox(width: 440, child: Form(key: key, child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
        DropdownButtonFormField<int>(initialValue: supplierId, decoration: const InputDecoration(labelText: 'Supplier (optional)'), items: suppliers.map((p) => DropdownMenuItem(value: p['id'] as int, child: Text(p['name'] as String))).toList(), onChanged: (v) => refresh(() => supplierId = v)),
        DropdownButtonFormField<int>(initialValue: productId, decoration: const InputDecoration(labelText: 'Product'), items: products.map((p) => DropdownMenuItem(value: p['id'] as int, child: Text(p['name'] as String))).toList(), onChanged: (v) => refresh(() { productId = v; final p = products.firstWhere((x) => x['id'] == v); rate.text = ((p['purchase_price'] as num?) ?? 0).toString(); gst.text = ((p['gst_rate'] as num?) ?? 0).toString(); })),
        TextFormField(controller: qty, decoration: const InputDecoration(labelText: 'Quantity'), keyboardType: const TextInputType.numberWithOptions(decimal: true), validator: (v) { final n = double.tryParse(v ?? ''); return n == null || n <= 0 ? 'Enter quantity greater than zero' : null; }),
        TextFormField(controller: rate, decoration: const InputDecoration(labelText: 'Purchase rate (₹)'), keyboardType: const TextInputType.numberWithOptions(decimal: true), validator: (v) { final n = double.tryParse(v ?? ''); return n == null || n < 0 ? 'Enter a valid rate' : null; }),
        TextFormField(controller: gst, decoration: const InputDecoration(labelText: 'GST (%)'), keyboardType: const TextInputType.numberWithOptions(decimal: true), validator: (v) { final n = double.tryParse(v ?? ''); return n == null || n < 0 || n > 100 ? 'Enter GST between 0 and 100' : null; }),
        TextFormField(controller: note, decoration: const InputDecoration(labelText: 'Notes')),
      ]))),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')), FilledButton(onPressed: () { if (key.currentState!.validate()) Navigator.pop(ctx, true); }, child: const Text('Save purchase'))],
    )));
    if (saved == true && productId != null) {
      final product = products.firstWhere((p) => p['id'] == productId);
      final quantity = double.parse(qty.text);
      final unitRate = double.parse(rate.text);
      final gstRate = double.parse(gst.text);
      final base = quantity * unitRate;
      final tax = base * gstRate / 100;
      final now = DateTime.now();
      await db.transaction((txn) async {
        final id = await txn.insert('invoices', {
          'invoice_number': 'PUR-${now.microsecondsSinceEpoch}',
          'invoice_type': 'purchase', 'party_id': supplierId,
          'invoice_date': now.toIso8601String(), 'subtotal': base,
          'tax_total': tax, 'grand_total': base + tax, 'amount_paid': 0,
          'status': 'unpaid', 'notes': note.text.trim(),
        });
        await txn.insert('invoice_items', {
          'invoice_id': id, 'product_id': productId,
          'description': product['name'], 'quantity': quantity,
          'unit': product['unit'] ?? 'pcs', 'rate': unitRate,
          'discount': 0, 'gst_rate': gstRate, 'tax_amount': tax,
          'line_total': base + tax,
        });
        await txn.rawUpdate('UPDATE products SET current_stock = current_stock + ?, purchase_price = ?, updated_at = ? WHERE id = ?', [quantity, unitRate, now.toIso8601String(), productId]);
      });
      await _load();
    }
    qty.dispose(); rate.dispose(); gst.dispose(); note.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Purchases')),
    floatingActionButton: FloatingActionButton.extended(onPressed: _add, icon: const Icon(Icons.add), label: const Text('Record purchase')),
    body: _loading ? const Center(child: CircularProgressIndicator()) : _rows.isEmpty
      ? const Center(child: Text('No purchases recorded yet.'))
      : ListView.separated(padding: const EdgeInsets.all(16), itemCount: _rows.length, separatorBuilder: (_, i) => const Divider(), itemBuilder: (ctx, i) {
        final row = _rows[i]; final total = (row['grand_total'] as num).toDouble();
        return ListTile(leading: const CircleAvatar(child: Icon(Icons.shopping_cart)), title: Text(row['invoice_number'] as String), subtitle: Text('${row['party_name'] ?? 'Supplier not selected'} • ${(row['invoice_date'] as String).split('T').first}'), trailing: Text('₹${total.toStringAsFixed(2)}'));
      }),
  );
}
