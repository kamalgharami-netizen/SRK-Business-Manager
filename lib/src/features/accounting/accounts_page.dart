import 'package:flutter/material.dart';

import '../../data/local/app_database.dart';

class AccountsPage extends StatefulWidget {
  const AccountsPage({super.key});

  @override
  State<AccountsPage> createState() => _AccountsPageState();
}

class _AccountsPageState extends State<AccountsPage> {
  bool _loading = true;
  bool _savingOpening = false;
  List<Map<String, Object?>> _accounts = [];
  bool _openingPosted = false;
  final Map<int, TextEditingController> _amounts = {};
  final Map<int, String> _sides = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final controller in _amounts.values) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    if (mounted) setState(() => _loading = true);
    final db = await AppDatabase.instance.database;
    final accounts = await db.query('accounts', orderBy: 'account_code COLLATE NOCASE');
    final opening = await db.query(
      'journal_entries',
      columns: ['id'],
      where: 'source_type = ? AND status = ?',
      whereArgs: ['opening_balance', 'posted'],
      limit: 1,
    );
    for (final controller in _amounts.values) {
      controller.dispose();
    }
    _amounts.clear();
    _sides.clear();
    for (final account in accounts) {
      final id = account['id'] as int;
      _amounts[id] = TextEditingController();
      _sides[id] = account['normal_balance'] as String? ?? 'debit';
    }
    if (!mounted) return;
    setState(() {
      _accounts = accounts;
      _openingPosted = opening.isNotEmpty;
      _loading = false;
    });
  }

  Future<void> _addAccount() async {
    final code = TextEditingController();
    final name = TextEditingController();
    String type = 'asset';
    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, refreshDialog) => AlertDialog(
          title: const Text('Add ledger account'),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: code,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Account code', hintText: 'e.g. 1020'),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: name,
                  decoration: const InputDecoration(labelText: 'Account name'),
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  initialValue: type,
                  decoration: const InputDecoration(labelText: 'Account type'),
                  items: const [
                    DropdownMenuItem(value: 'asset', child: Text('Asset')),
                    DropdownMenuItem(value: 'liability', child: Text('Liability')),
                    DropdownMenuItem(value: 'equity', child: Text('Equity')),
                    DropdownMenuItem(value: 'income', child: Text('Income')),
                    DropdownMenuItem(value: 'expense', child: Text('Expense')),
                  ],
                  onChanged: (value) {
                    if (value != null) refreshDialog(() => type = value);
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('Save account')),
          ],
        ),
      ),
    );

    if (result == true) {
      final accountCode = code.text.trim();
      final accountName = name.text.trim();
      if (accountCode.isEmpty || accountName.isEmpty) {
        _message('Account code and name are required.');
      } else {
        try {
          final db = await AppDatabase.instance.database;
          await db.insert('accounts', {
            'account_code': accountCode,
            'account_name': accountName,
            'account_type': type,
            'normal_balance': (type == 'asset' || type == 'expense') ? 'debit' : 'credit',
            'is_system': 0,
            'is_active': 1,
          });
          await _load();
          _message('Account added.');
        } catch (error) {
          _message('Could not add account. Check that the code is unique. $error');
        }
      }
    }
    code.dispose();
    name.dispose();
  }

  Future<void> _toggleAccount(Map<String, Object?> account) async {
    if ((account['is_system'] as num).toInt() == 1) {
      _message('System accounts cannot be deactivated.');
      return;
    }
    final db = await AppDatabase.instance.database;
    final active = (account['is_active'] as num).toInt() == 1;
    await db.update('accounts', {'is_active': active ? 0 : 1}, where: 'id = ?', whereArgs: [account['id']]);
    await _load();
  }

  Future<void> _saveOpeningBalances() async {
    if (_openingPosted) {
      _message('Opening balances have already been posted.');
      return;
    }
    final db = await AppDatabase.instance.database;
    double debitTotal = 0;
    double creditTotal = 0;
    final lines = <Map<String, Object?>>[];
    for (final account in _accounts) {
      if ((account['is_active'] as num).toInt() != 1) continue;
      final type = account['account_type'] as String;
      if (!['asset', 'liability', 'equity'].contains(type)) continue;
      // Receivable/payable control balances come from individual party records.
      // Exclude them here to prevent double-counting in Trial Balance/Balance Sheet.
      if (['1100', '2000', '3200'].contains(account['account_code'])) continue;
      final id = account['id'] as int;
      final raw = _amounts[id]?.text.trim() ?? '';
      if (raw.isEmpty) continue;
      final amount = double.tryParse(raw);
      if (amount == null || !amount.isFinite || amount <= 0) {
        _message('Enter a valid positive amount for ${account['account_name']}.');
        return;
      }
      final side = _sides[id] ?? 'debit';
      if (side == 'debit') {
        debitTotal += amount;
      } else {
        creditTotal += amount;
      }
      lines.add({
        'account_id': id,
        'description': 'Opening balance - ${account['account_name']}',
        'debit': side == 'debit' ? amount : 0.0,
        'credit': side == 'credit' ? amount : 0.0,
      });
    }
    if (lines.isEmpty) {
      _message('Enter at least one opening balance.');
      return;
    }

    final difference = (debitTotal - creditTotal).abs();
    if (difference > 0.005) {
      final equityRows = await db.query(
        'accounts',
        columns: ['id'],
        where: 'account_code = ? AND is_active = 1',
        whereArgs: ['3200'],
        limit: 1,
      );
      if (equityRows.isEmpty) {
        _message('Opening Balance Equity account is missing or inactive.');
        return;
      }
      lines.add({
        'account_id': equityRows.first['id'],
        'description': 'Balancing opening equity',
        'debit': debitTotal < creditTotal ? difference : 0.0,
        'credit': debitTotal > creditTotal ? difference : 0.0,
      });
    }

    setState(() => _savingOpening = true);
    try {
      await db.transaction((txn) async {
        final existing = await txn.query(
          'journal_entries',
          columns: ['id'],
          where: 'source_type = ? AND status = ?',
          whereArgs: ['opening_balance', 'posted'],
          limit: 1,
        );
        if (existing.isNotEmpty) throw StateError('Opening balances were already posted.');
        final entryId = await txn.insert('journal_entries', {
          'entry_number': 'OB-${DateTime.now().microsecondsSinceEpoch}',
          'entry_date': DateTime.now().toIso8601String(),
          'source_type': 'opening_balance',
          'source_id': 1,
          'memo': 'Initial business opening balances',
          'status': 'draft',
        });
        for (final line in lines) {
          await txn.insert('journal_lines', {'journal_entry_id': entryId, ...line});
        }
        await txn.update('journal_entries', {'status': 'posted'}, where: 'id = ?', whereArgs: [entryId]);
      });
      await _load();
      _message('Opening balances posted successfully.');
    } catch (error) {
      _message('Could not post opening balances: $error');
    } finally {
      if (mounted) setState(() => _savingOpening = false);
    }
  }

  void _message(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  String _typeLabel(String type) {
    switch (type) {
      case 'asset': return 'Asset';
      case 'liability': return 'Liability';
      case 'equity': return 'Equity';
      case 'income': return 'Income';
      case 'expense': return 'Expense';
      default: return type;
    }
  }

  @override
  Widget build(BuildContext context) {
    final openingAccounts = _accounts.where((account) {
      final type = account['account_type'] as String;
      return (account['is_active'] as num).toInt() == 1 &&
          ['asset', 'liability', 'equity'].contains(type) &&
          !['1100', '2000', '3200'].contains(account['account_code']);
    }).toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Chart of Accounts & Opening Balances'),
        actions: [
          IconButton(tooltip: 'Add account', onPressed: _addAccount, icon: const Icon(Icons.add)),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Chart of Accounts', style: Theme.of(context).textTheme.titleLarge),
                        const SizedBox(height: 6),
                        const Text('View standard ledger accounts and add business-specific accounts. System accounts used by automatic posting are protected.'),
                        const SizedBox(height: 12),
                        for (final account in _accounts)
                          ListTile(
                            contentPadding: EdgeInsets.zero,
                            title: Text('${account['account_code']} • ${account['account_name']}'),
                            subtitle: Text('${_typeLabel(account['account_type'] as String)} • ${(account['normal_balance'] as String).toUpperCase()} normal balance${(account['is_system'] as num).toInt() == 1 ? ' • System' : ' • Custom'}'),
                            trailing: (account['is_system'] as num).toInt() == 1
                                ? const Chip(label: Text('Protected'))
                                : Switch(
                                    value: (account['is_active'] as num).toInt() == 1,
                                    onChanged: (_) => _toggleAccount(account),
                                  ),
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Opening Balances', style: Theme.of(context).textTheme.titleLarge),
                        const SizedBox(height: 6),
                        const Text('Enter balances as on the date you start using SRK Business Manager. Cash (1000), Bank (1010), other Asset, Liability and Equity accounts are included. Enter customer receivables and supplier payables in each Party profile; their control accounts are excluded here to prevent duplicate reporting.'),
                        const SizedBox(height: 12),
                        if (_openingPosted)
                          const ListTile(
                            leading: Icon(Icons.lock, color: Colors.green),
                            title: Text('Opening balances already posted'),
                            subtitle: Text('This one-time entry is locked to prevent duplicate opening balances. Contact the administrator before making a correction.'),
                          )
                        else ...[
                          for (final account in openingAccounts)
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 5),
                              child: Row(
                                children: [
                                  Expanded(flex: 5, child: Text('${account['account_code']} • ${account['account_name']}')),
                                  Expanded(
                                    flex: 3,
                                    child: TextField(
                                      controller: _amounts[account['id'] as int],
                                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                      decoration: const InputDecoration(labelText: 'Amount', isDense: true, border: OutlineInputBorder()),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    flex: 2,
                                    child: DropdownButtonFormField<String>(
                                      initialValue: _sides[account['id'] as int],
                                      decoration: const InputDecoration(isDense: true, border: OutlineInputBorder()),
                                      items: const [
                                        DropdownMenuItem(value: 'debit', child: Text('Dr')),
                                        DropdownMenuItem(value: 'credit', child: Text('Cr')),
                                      ],
                                      onChanged: (value) {
                                        if (value != null) setState(() => _sides[account['id'] as int] = value);
                                      },
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          const SizedBox(height: 12),
                          FilledButton.icon(
                            onPressed: _savingOpening ? null : _saveOpeningBalances,
                            icon: _savingOpening
                                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                                : const Icon(Icons.account_balance_wallet),
                            label: const Text('Post opening balances'),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}
