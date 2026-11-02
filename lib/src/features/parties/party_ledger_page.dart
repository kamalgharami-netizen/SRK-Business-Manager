import 'package:flutter/material.dart';
import '../../data/local/app_database.dart';

class PartyLedgerPage extends StatefulWidget {
  const PartyLedgerPage({super.key});
  @override
  State<PartyLedgerPage> createState() => _PartyLedgerPageState();
}

class _PartyLedgerPageState extends State<PartyLedgerPage> {
  List<Map<String, Object?>> _parties = [];
  List<Map<String, Object?>> _entries = [];
  int? _partyId;
  bool _loading = true;
  double _receivable = 0;
  double _payable = 0;
  double _customerAdvance = 0;
  double _supplierAdvance = 0;

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
      if (rows.isNotEmpty && _partyId == null) _partyId = rows.first['id'] as int;
    });
    if (_partyId != null) await _loadLedger();
  }

  Future<void> _loadLedger() async {
    final id = _partyId;
    if (id == null) return;
    setState(() => _loading = true);
    final db = await AppDatabase.instance.database;
    final partyRows = await db.query('parties', where: 'id = ?', whereArgs: [id], limit: 1);
    if (partyRows.isEmpty) {
      if (mounted) setState(() { _entries = []; _loading = false; });
      return;
    }
    final party = partyRows.first;
    var receivable = party['balance_type'] == 'receivable'
        ? ((party['opening_balance'] as num?) ?? 0).toDouble() : 0.0;
    var payable = party['balance_type'] == 'payable'
        ? ((party['opening_balance'] as num?) ?? 0).toDouble() : 0.0;
    var customerAdvance = 0.0;
    var supplierAdvance = 0.0;

    final invoices = await db.query('invoices',
      where: 'party_id = ? AND invoice_type IN (\'sale\',\'sales_return\',\'purchase\',\'purchase_return\')',
      whereArgs: [id], orderBy: 'invoice_date, id');
    final payments = await db.query('payments',
      where: 'party_id = ?', whereArgs: [id], orderBy: 'payment_date, id');

    final events = <Map<String, Object?>>[];
    for (final invoice in invoices) {
      final type = invoice['invoice_type'] as String;
      final amount = ((invoice['grand_total'] as num?) ?? 0).toDouble();
      events.add({
        'date': invoice['invoice_date'] as String,
        'reference': invoice['invoice_number'] as String,
        'description': switch (type) {
          'sale' => 'Sales invoice',
          'sales_return' => 'Sales return',
          'purchase' => 'Purchase invoice',
          _ => 'Purchase return',
        },
        'kind': type,
        'amount': amount,
        'sort': invoice['id'] as int,
      });
    }
    for (final payment in payments) {
      final type = payment['payment_type'] as String;
      events.add({
        'date': payment['payment_date'] as String,
        'reference': (payment['reference'] as String?)?.trim().isNotEmpty == true
            ? payment['reference'] : 'Payment #${payment['id']}',
        'description': type == 'receipt' ? 'Receipt' : 'Payment',
        'kind': payment['invoice_id'] == null
            ? (type == 'receipt' ? 'customer_advance' : 'supplier_advance')
            : type,
        'amount': ((payment['amount'] as num?) ?? 0).toDouble(),
        'sort': (payment['id'] as int) + 1000000000,
      });
    }
    final allocations = await db.rawQuery('''
      SELECT a.amount, a.allocation_date, a.id, p.payment_type,
             i.invoice_number
      FROM payment_allocations a
      JOIN payments p ON p.id = a.payment_id
      JOIN invoices i ON i.id = a.invoice_id
      WHERE p.party_id = ?
      ORDER BY a.allocation_date, a.id
    ''', [id]);
    for (final allocation in allocations) {
      final isCustomer = allocation['payment_type'] == 'receipt';
      events.add({
        'date': allocation['allocation_date'] as String,
        'reference': 'Allocation #${allocation['id']} • ${allocation['invoice_number']}',
        'description': isCustomer ? 'Customer advance applied' : 'Supplier advance applied',
        'kind': isCustomer ? 'customer_advance_allocation' : 'supplier_advance_allocation',
        'amount': ((allocation['amount'] as num?) ?? 0).toDouble(),
        'sort': (allocation['id'] as int) + 2000000000,
      });
    }
    events.sort((a, b) {
      final byDate = (a['date'] as String).compareTo(b['date'] as String);
      return byDate != 0 ? byDate : (a['sort'] as int).compareTo(b['sort'] as int);
    });

    final rows = <Map<String, Object?>>[
      {
        'date': '',
        'reference': 'Opening balance',
        'description': 'Opening balance',
        'receivable_change': 0.0,
        'payable_change': 0.0,
        'receivable': receivable,
        'payable': payable,
        'customer_advance': customerAdvance,
        'supplier_advance': supplierAdvance,
      }
    ];
    for (final event in events) {
      final amount = event['amount'] as double;
      switch (event['kind']) {
        case 'sale':
          receivable += amount;
        case 'sales_return':
        case 'receipt':
          receivable -= amount;
        case 'purchase':
          payable += amount;
        case 'purchase_return':
        case 'payment':
          payable -= amount;
        case 'customer_advance':
          customerAdvance += amount;
        case 'supplier_advance':
          supplierAdvance += amount;
      }
      rows.add({
        ...event,
        'receivable_change': switch (event['kind']) {
          'sale' => amount,
          'sales_return' || 'receipt' => -amount,
          _ => 0.0,
        },
        'payable_change': switch (event['kind']) {
          'purchase' => amount,
          'purchase_return' || 'payment' => -amount,
          _ => 0.0,
        },
        'customer_advance_change': event['kind'] == 'customer_advance' ? amount : 0.0,
        'supplier_advance_change': event['kind'] == 'supplier_advance' ? amount : 0.0,
        'customer_advance_allocation_change': event['kind'] == 'customer_advance_allocation' ? -amount : 0.0,\n        'supplier_advance_allocation_change': event['kind'] == 'supplier_advance_allocation' ? -amount : 0.0,
        'receivable': receivable,
        'payable': payable,
        'customer_advance': customerAdvance,
        'supplier_advance': supplierAdvance,
      });
    }
    if (!mounted) return;
    setState(() {
      _entries = rows;
      _receivable = receivable;
      _payable = payable;
      _customerAdvance = customerAdvance;
      _supplierAdvance = supplierAdvance;
      _loading = false;
    });
  }

  String _money(Object? value) => '₹${((value as num?) ?? 0).toDouble().toStringAsFixed(2)}';

  @override
  Widget build(BuildContext context) {
    final selected = _parties.where((p) => p['id'] == _partyId).firstOrNull;
    return Scaffold(
      appBar: AppBar(title: const Text('Party Ledger')),
      body: _loading && _parties.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : _parties.isEmpty
              ? const Center(child: Text('No customers or suppliers found.'))
              : RefreshIndicator(
                  onRefresh: _loadLedger,
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      DropdownButtonFormField<int>(
                        initialValue: _partyId,
                        decoration: const InputDecoration(labelText: 'Select customer / supplier', border: OutlineInputBorder()),
                        items: _parties.map((p) => DropdownMenuItem<int>(
                          value: p['id'] as int,
                          child: Text(p['name'] as String),
                        )).toList(),
                        onChanged: (value) async {
                          if (value == null) return;
                          setState(() => _partyId = value);
                          await _loadLedger();
                        },
                      ),
                      const SizedBox(height: 12),
                      if (selected != null) Text(
                        '${selected['party_type']} • ${selected['phone'] ?? ''}',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      const SizedBox(height: 12),
                      Wrap(spacing: 12, runSpacing: 12, children: [
                        _balanceCard('Receivable balance', _receivable, Icons.call_received),
                        _balanceCard('Payable balance', _payable, Icons.call_made),
                        _balanceCard('Customer advances', _customerAdvance, Icons.account_balance_wallet),
                        _balanceCard('Supplier advances', _supplierAdvance, Icons.payments),
                      ]),
                      const SizedBox(height: 16),
                      if (_loading) const LinearProgressIndicator(),
                      if (!_loading && _entries.isEmpty) const Text('No ledger transactions found.'),
                      ..._entries.map((entry) => Card(
                        elevation: 0,
                        child: ListTile(
                          title: Text(entry['description'] as String),
                          subtitle: Text([
                            if ((entry['date'] as String?)?.isNotEmpty == true) entry['date'] as String,
                            entry['reference'] as String,
                          ].join(' • ')),
                          trailing: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text('R: ${_money(entry['receivable'])}', style: const TextStyle(fontSize: 12)),
                              Text('P: ${_money(entry['payable'])}', style: const TextStyle(fontSize: 12)),
                            ],
                          ),
                        ),
                      )),
                    ],
                  ),
                ),
    );
  }

  Widget _balanceCard(String title, double amount, IconData icon) => SizedBox(
    width: 250,
    child: Card(elevation: 0, child: Padding(
      padding: const EdgeInsets.all(16),
      child: Row(children: [
        Icon(icon), const SizedBox(width: 10),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: const TextStyle(fontSize: 12)),
          Text(_money(amount), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        ])),
      ]),
    )),
  );
}
