import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:srk_business_manager/src/data/local/supplier_ledger_reconciliation.dart';

void main() {
  setUpAll(sqfliteFfiInit);

  Future<Database> fixture() async {
    final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    await db.execute('CREATE TABLE parties(id INTEGER PRIMARY KEY, opening_balance REAL, balance_type TEXT, created_at TEXT)');
    await db.execute('CREATE TABLE invoices(id INTEGER PRIMARY KEY, invoice_type TEXT, party_id INTEGER, invoice_date TEXT, grand_total REAL)');
    await db.execute('CREATE TABLE payments(id INTEGER PRIMARY KEY, payment_type TEXT, invoice_id INTEGER, payment_date TEXT, amount REAL)');
    await db.execute('CREATE TABLE payment_allocations(id INTEGER PRIMARY KEY, payment_id INTEGER, allocation_date TEXT, amount REAL)');
    await db.execute('CREATE TABLE accounts(id INTEGER PRIMARY KEY, account_code TEXT)');
    await db.execute('CREATE TABLE journal_entries(id INTEGER PRIMARY KEY, source_type TEXT, source_id INTEGER, entry_date TEXT, status TEXT)');
    await db.execute('CREATE TABLE journal_lines(id INTEGER PRIMARY KEY, journal_entry_id INTEGER, account_id INTEGER, debit REAL, credit REAL)');
    return db;
  }

  test('reconciles supplier opening balance, invoices, returns, payments and allocations', () async {
    final db = await fixture();
    addTearDown(db.close);
    await db.insert('parties', {'id': 1, 'opening_balance': 100, 'balance_type': 'payable', 'created_at': '2025-12-01'});
    await db.insert('invoices', {'id': 1, 'invoice_type': 'purchase', 'party_id': 1, 'invoice_date': '2026-01-01', 'grand_total': 500});
    await db.insert('invoices', {'id': 2, 'invoice_type': 'purchase_return', 'party_id': 1, 'invoice_date': '2026-01-02', 'grand_total': 50});
    await db.insert('payments', {'id': 1, 'payment_type': 'payment', 'invoice_id': 1, 'payment_date': '2026-01-03', 'amount': 100});
    await db.insert('payments', {'id': 2, 'payment_type': 'payment', 'invoice_id': null, 'payment_date': '2026-01-04', 'amount': 30});
    await db.insert('payment_allocations', {'id': 1, 'payment_id': 2, 'allocation_date': '2026-01-05', 'amount': 20});
    await db.insert('accounts', {'id': 1, 'account_code': '2000'});
    await db.insert('accounts', {'id': 2, 'account_code': '1400'});
    Future<void> addJournal(String source, int id, double debit, double credit, {int accountId = 1}) async {
      final entry = await db.insert('journal_entries', {'source_type': source, 'source_id': id, 'entry_date': '2026-01-06', 'status': 'posted'});
      await db.insert('journal_lines', {'journal_entry_id': entry, 'account_id': accountId, 'debit': debit, 'credit': credit});
    }
    await addJournal('purchase_invoice', 1, 0, 500);
    await addJournal('purchase_return', 2, 50, 0);
    await addJournal('payment', 1, 100, 0);
    // Unallocated supplier advance has a payment journal but does not reduce payable until allocated.
    await addJournal('payment', 2, 30, 0, accountId: 2);
    await addJournal('advance_allocation', 1, 0, 20, accountId: 2);
    final result = await SupplierLedgerReconciliation.load(db);
    expect(result['supplier_ledger_balance'], 430);
    expect(result['control_account_balance'], 430);
    expect(result['difference'], 0);
    expect(result['supplier_advance_ledger_balance'], 10);
    expect(result['supplier_advance_control_balance'], 10);
    expect(result['supplier_advance_difference'], 0);
    expect(result['is_supplier_advance_reconciled'], true);
    expect(result['is_reconciled'], true);
  });

  test('excludes later-created opening balances from historical reports', () async {
    final db = await fixture();
    addTearDown(db.close);
    await db.insert('parties', {'id': 1, 'opening_balance': 100, 'balance_type': 'payable', 'created_at': '2026-02-01'});
    final result = await SupplierLedgerReconciliation.load(db, asOfDate: '2026-01-31');
    expect(result['opening_balance'], 0);
    expect(result['supplier_ledger_balance'], 0);
  });

  test('flags unassigned purchase and missing journal', () async {
    final db = await fixture();
    addTearDown(db.close);
    await db.insert('invoices', {'id': 1, 'invoice_type': 'purchase', 'party_id': null, 'invoice_date': '2026-01-01', 'grand_total': 250});
    final result = await SupplierLedgerReconciliation.load(db);
    expect(result['unassigned_purchase_count'], 1);
    expect(result['unassigned_purchase_total'], 250);
    expect(result['missing_journal_count'], 1);
    expect(result['is_reconciled'], false);
  });
}
