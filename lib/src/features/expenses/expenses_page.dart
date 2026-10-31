import 'package:flutter/material.dart';
import '../../data/local/app_database.dart';
import '../../data/local/accounting_service.dart';

class ExpensesPage extends StatefulWidget {
  const ExpensesPage({super.key});
  @override
  State<ExpensesPage> createState() => _ExpensesPageState();
}

class _ExpensesPageState extends State<ExpensesPage> {
  List<Map<String, Object?>> _rows = [];
  bool _loading = true;
  @override
  void initState() { super.initState(); _load(); }
  Future<void> _load() async {
    final db = await AppDatabase.instance.database;
    final rows = await db.query('expenses', orderBy: 'expense_date DESC, id DESC');
    if (!mounted) return;
    setState(() { _rows = rows; _loading = false; });
  }

  Future<void> _add() async {
    final key = GlobalKey<FormState>();
    final category = TextEditingController(text: 'General');
    final description = TextEditingController();
    final amount = TextEditingController();
    String mode = 'cash';
    final saved = await showDialog<bool>(context: context, builder: (ctx) => StatefulBuilder(builder: (ctx, refresh) => AlertDialog(
      title: const Text('Add expense'),
      content: SizedBox(width: 420, child: Form(key: key, child: Column(mainAxisSize: MainAxisSize.min, children: [
        TextFormField(controller: category, decoration: const InputDecoration(labelText: 'Category *'), validator: (v) => v == null || v.trim().isEmpty ? 'Enter category' : null),
        TextFormField(controller: description, decoration: const InputDecoration(labelText: 'Description *'), validator: (v) => v == null || v.trim().isEmpty ? 'Enter description' : null),
        TextFormField(controller: amount, decoration: const InputDecoration(labelText: 'Amount (₹) *'), keyboardType: const TextInputType.numberWithOptions(decimal: true), validator: (v) { final n = double.tryParse(v ?? ''); return n == null || !n.isFinite || n <= 0 ? 'Enter a valid finite amount' : null; }),
        DropdownButtonFormField<String>(initialValue: mode, decoration: const InputDecoration(labelText: 'Payment mode'), items: const [DropdownMenuItem(value: 'cash', child: Text('Cash')), DropdownMenuItem(value: 'upi', child: Text('UPI')), DropdownMenuItem(value: 'bank', child: Text('Bank transfer')), DropdownMenuItem(value: 'card', child: Text('Card'))], onChanged: (v) => refresh(() => mode = v ?? 'cash')),
      ]))),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')), FilledButton(onPressed: () { if (key.currentState!.validate()) Navigator.pop(ctx, true); }, child: const Text('Save expense'))],
    )));
    if (saved == true) {
      final db = await AppDatabase.instance.database;
      await db.transaction((txn) async {
        final expenseDate = DateTime.now().toIso8601String();
        final expenseId = await txn.insert('expenses', {
          'expense_date': expenseDate,
          'category': category.text.trim(),
          'description': description.text.trim(),
          'amount': double.parse(amount.text),
          'payment_mode': mode,
        });
        await AccountingService.postExpense(
          txn,
          expenseId: expenseId,
          date: expenseDate,
          category: category.text.trim(),
          description: description.text.trim(),
          mode: mode,
          amount: double.parse(amount.text),
        );
      });
      await _load();
    }
    category.dispose(); description.dispose(); amount.dispose();
  }

  Future<void> _delete(Map<String, Object?> row) async {
    final yes = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(title: const Text('Delete expense?'), content: Text('Delete "${row['description']}"?'), actions: [
      TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
      FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Delete')),
    ]));
    if (yes != true) return;
    final db = await AppDatabase.instance.database;
    await db.transaction((txn) async {
      await AccountingService.voidSource(
        txn,
        sourceType: 'expense',
        sourceId: row['id'] as int,
      );
      await txn.delete('expenses', where: 'id = ?', whereArgs: [row['id']]);
    });
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final total = _rows.fold<double>(0, (sum, row) => sum + (row['amount'] as num).toDouble());
    return Scaffold(
      appBar: AppBar(title: const Text('Expenses')),
      floatingActionButton: FloatingActionButton.extended(onPressed: _add, icon: const Icon(Icons.add), label: const Text('Add expense')),
      body: _loading ? const Center(child: CircularProgressIndicator()) : Column(children: [
        Card(margin: const EdgeInsets.all(16), child: ListTile(leading: const Icon(Icons.account_balance_wallet_outlined), title: const Text('Recorded expenses'), trailing: Text('₹${total.toStringAsFixed(2)}', style: Theme.of(context).textTheme.titleLarge))),
        Expanded(child: _rows.isEmpty ? const Center(child: Text('No expenses recorded yet.')) : ListView.separated(padding: const EdgeInsets.fromLTRB(16, 0, 16, 88), itemCount: _rows.length, separatorBuilder: (_, i) => const Divider(), itemBuilder: (ctx, i) {
          final row = _rows[i]; final value = (row['amount'] as num).toDouble();
          return ListTile(leading: const CircleAvatar(child: Icon(Icons.receipt_long)), title: Text(row['description'] as String), subtitle: Text('${row['category']} • ${row['expense_date'].toString().split('T').first} • ${row['payment_mode']}'), trailing: Row(mainAxisSize: MainAxisSize.min, children: [Text('₹${value.toStringAsFixed(2)}'), IconButton(tooltip: 'Delete', onPressed: () => _delete(row), icon: const Icon(Icons.delete_outline))]));
        })),
      ]),
    );
  }
}
