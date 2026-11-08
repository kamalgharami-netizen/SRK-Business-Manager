import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:srk_business_manager/src/data/local/customer_ledger_reconciliation.dart';
import 'package:srk_business_manager/src/data/local/supplier_ledger_reconciliation.dart';

void main() {
  setUpAll(sqfliteFfiInit);

  late String databasePath;
  late Database db;

  Future<Database> openFixture() async {
    final database = await databaseFactoryFfi.openDatabase(databasePath);
    await database.execute('CREATE TABLE parties(id INTEGER PRIMARY KEY, opening_balance REAL, balance_type TEXT, created_at TEXT)');
    await database.execute('CREATE TABLE invoices(id INTEGER PRIMARY KEY, invoice_type TEXT, party_id INTEGER, invoice_date TEXT, grand_total REAL)');
    await database.execute('CREATE TABLE debit_notes(id INTEGER PRIMARY KEY, party_id INTEGER, note_date TEXT, grand_total REAL, status TEXT)');
    await database.execute('CREATE TABLE payments(id INTEGER PRIMARY KEY, payment_type TEXT, invoice_id INTEGER, payment_date TEXT, amount REAL)');
    await database.execute('CREATE TABLE payment_allocations(id INTEGER PRIMARY KEY, payment_id INTEGER, allocation_date TEXT, amount REAL)');
    await database.execute('CREATE TABLE accounts(id INTEGER PRIMARY KEY, account_code TEXT)');
    await database.execute('CREATE TABLE journal_entries(id INTEGER PRIMARY KEY AUTOINCREMENT, source_type TEXT, source_id INTEGER, entry_date TEXT, status TEXT)');
    await database.execute('CREATE TABLE journal_lines(id INTEGER PRIMARY KEY AUTOINCREMENT, journal_entry_id INTEGER, account_id INTEGER, debit REAL, credit REAL)');
    await database.insert('accounts', {'id': 1, 'account_code': '1100'});
    await database.insert('accounts', {'id': 2, 'account_code': '2200'});
    await database.insert('accounts', {'id': 3, 'account_code': '2000'});
    await database.insert('accounts', {'id': 4, 'account_code': '1400'});
    return database;
  }

  setUp(() async {
    databasePath = p.join(Directory.systemTemp.path,
        'srk_party_ledger_reconciliation_${DateTime.now().microsecondsSinceEpoch}.sqlite');
    db = await openFixture();
  });

  tearDown(() async {
    await db.close();
    final file = File(databasePath);
    if (await file.exists()) await file.delete();
  });

  Future<void> addJournal(String source, int sourceId, List<Map<String, Object?>> lines) async {
    final entryId = await db.insert('journal_entries', {
      'source_type': source,
      'source_id': sourceId,
      'entry_date': '2026-11-06',
      'status': 'posted',
    });
    for (final line in lines) {
      await db.insert('journal_lines', {
        'journal_entry_id': entryId,
        'account_id': line['account_id'],
        'debit': line['debit'],
        'credit': line['credit'],
      });
    }
  }

  test('customer ledger and advance control reconcile after SQLite restart', () async {
    await db.insert('parties', {'id': 1, 'opening_balance': 100, 'balance_type': 'receivable', 'created_at': '2025-12-01'});
    await db.insert('invoices', {'id': 1, 'invoice_type': 'sale', 'party_id': 1, 'invoice_date': '2026-01-01', 'grand_total': 500});
    await db.insert('invoices', {'id': 2, 'invoice_type': 'sales_return', 'party_id': 1, 'invoice_date': '2026-01-02', 'grand_total': 50});
    await db.insert('debit_notes', {'id': 1, 'party_id': 1, 'note_date': '2026-01-03', 'grand_total': 40, 'status': 'posted'});
    await db.insert('payments', {'id': 1, 'payment_type': 'receipt', 'invoice_id': 1, 'payment_date': '2026-01-04', 'amount': 100});
    await db.insert('payments', {'id': 2, 'payment_type': 'receipt', 'invoice_id': null, 'payment_date': '2026-01-05', 'amount': 30});
    await db.insert('payment_allocations', {'id': 1, 'payment_id': 2, 'allocation_date': '2026-01-06', 'amount': 20});
    await addJournal('sales_invoice', 1, [{'account_id': 1, 'debit': 500, 'credit': 0}]);
    await addJournal('sales_return', 2, [{'account_id': 1, 'debit': 0, 'credit': 50}]);
    await addJournal('sales_debit_note', 1, [{'account_id': 1, 'debit': 40, 'credit': 0}]);
    await addJournal('receipt', 1, [{'account_id': 1, 'debit': 0, 'credit': 100}]);
    await addJournal('receipt', 2, [{'account_id': 2, 'debit': 0, 'credit': 30}]);
    await addJournal('advance_allocation', 1, [
      {'account_id': 2, 'debit': 20, 'credit': 0},
      {'account_id': 1, 'debit': 0, 'credit': 20},
    ]);

    await db.close();
    db = await openFixture();

    final result = await CustomerLedgerReconciliation.load(db);
    expect(result['customer_ledger_balance'], 470);
    expect(result['control_account_balance'], 470);
    expect(result['difference'], 0);
    expect(result['customer_advance_ledger_balance'], 10);
    expect(result['customer_advance_control_balance'], 10);
    expect(result['customer_advance_difference'], 0);
    expect(result['is_customer_advance_reconciled'], isTrue);
    expect(result['is_reconciled'], isTrue);
  });

  test('supplier ledger and advance control reconcile after SQLite restart', () async {
    await db.insert('parties', {'id': 1, 'opening_balance': 100, 'balance_type': 'payable', 'created_at': '2025-12-01'});
    await db.insert('invoices', {'id': 1, 'invoice_type': 'purchase', 'party_id': 1, 'invoice_date': '2026-01-01', 'grand_total': 500});
    await db.insert('invoices', {'id': 2, 'invoice_type': 'purchase_return', 'party_id': 1, 'invoice_date': '2026-01-02', 'grand_total': 50});
    await db.insert('payments', {'id': 1, 'payment_type': 'payment', 'invoice_id': 1, 'payment_date': '2026-01-03', 'amount': 100});
    await db.insert('payments', {'id': 2, 'payment_type': 'payment', 'invoice_id': null, 'payment_date': '2026-01-04', 'amount': 30});
    await db.insert('payment_allocations', {'id': 1, 'payment_id': 2, 'allocation_date': '2026-01-05', 'amount': 20});
    await addJournal('purchase_invoice', 1, [{'account_id': 3, 'debit': 0, 'credit': 500}]);
    await addJournal('purchase_return', 2, [{'account_id': 3, 'debit': 50, 'credit': 0}]);
    await addJournal('payment', 1, [{'account_id': 3, 'debit': 100, 'credit': 0}]);
    await addJournal('payment', 2, [{'account_id': 4, 'debit': 30, 'credit': 0}]);
    await addJournal('advance_allocation', 1, [
      {'account_id': 3, 'debit': 20, 'credit': 0},
      {'account_id': 4, 'debit': 0, 'credit': 20},
    ]);

    await db.close();
    db = await openFixture();

    final result = await SupplierLedgerReconciliation.load(db);
    expect(result['supplier_ledger_balance'], 430);
    expect(result['control_account_balance'], 430);
    expect(result['difference'], 0);
    expect(result['supplier_advance_ledger_balance'], 10);
    expect(result['supplier_advance_control_balance'], 10);
    expect(result['supplier_advance_difference'], 0);
    expect(result['is_supplier_advance_reconciled'], isTrue);
    expect(result['is_reconciled'], isTrue);
  });
}
