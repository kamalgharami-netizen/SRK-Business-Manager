import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:srk_business_manager/src/data/local/customer_ledger_reconciliation.dart';

void main() {
  setUpAll(sqfliteFfiInit);
  Future<Database> fixture() async {
    final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    await db.execute('CREATE TABLE parties(id INTEGER PRIMARY KEY, opening_balance REAL, balance_type TEXT, created_at TEXT)');
    await db.execute('CREATE TABLE invoices(id INTEGER PRIMARY KEY, invoice_type TEXT, party_id INTEGER, invoice_date TEXT, grand_total REAL)');
    await db.execute('CREATE TABLE debit_notes(id INTEGER PRIMARY KEY, party_id INTEGER, note_date TEXT, grand_total REAL, status TEXT)');
    await db.execute('CREATE TABLE payments(id INTEGER PRIMARY KEY, payment_type TEXT, invoice_id INTEGER, payment_date TEXT, amount REAL)');
    await db.execute('CREATE TABLE payment_allocations(id INTEGER PRIMARY KEY, payment_id INTEGER, allocation_date TEXT, amount REAL)');
    await db.execute('CREATE TABLE accounts(id INTEGER PRIMARY KEY, account_code TEXT)');
    await db.execute('CREATE TABLE journal_entries(id INTEGER PRIMARY KEY, source_type TEXT, source_id INTEGER, entry_date TEXT, status TEXT)');
    await db.execute('CREATE TABLE journal_lines(id INTEGER PRIMARY KEY, journal_entry_id INTEGER, account_id INTEGER, debit REAL, credit REAL)');
    return db;
  }
  test('reconciles customer opening balance, sales, returns, debit notes, receipts and advances', () async {
    final db = await fixture();
    addTearDown(db.close);
    await db.insert('parties', {'id': 1, 'opening_balance': 100, 'balance_type': 'receivable', 'created_at': '2025-12-01'});
    await db.insert('invoices', {'id': 1, 'invoice_type': 'sale', 'party_id': 1, 'invoice_date': '2026-01-01', 'grand_total': 500});
    await db.insert('invoices', {'id': 2, 'invoice_type': 'sales_return', 'party_id': 1, 'invoice_date': '2026-01-02', 'grand_total': 50});
    await db.insert('debit_notes', {'id': 1, 'party_id': 1, 'note_date': '2026-01-03', 'grand_total': 40, 'status': 'posted'});
    await db.insert('payments', {'id': 1, 'payment_type': 'receipt', 'invoice_id': 1, 'payment_date': '2026-01-04', 'amount': 100});
    await db.insert('payments', {'id': 2, 'payment_type': 'receipt', 'invoice_id': null, 'payment_date': '2026-01-05', 'amount': 30});
    await db.insert('payment_allocations', {'id': 1, 'payment_id': 2, 'allocation_date': '2026-01-06', 'amount': 20});
    await db.insert('accounts', {'id': 1, 'account_code': '1100'});
    await db.insert('accounts', {'id': 2, 'account_code': '2200'});
    Future<void> addLines(String source, int id, List<Map<String, Object?>> lines) async {
      final entry = await db.insert('journal_entries', {'source_type': source, 'source_id': id, 'entry_date': '2026-01-07', 'status': 'posted'});
      for (final line in lines) {
        await db.insert('journal_lines', {'journal_entry_id': entry, 'account_id': line['account_id'], 'debit': line['debit'], 'credit': line['credit']});
      }
    }
    await addLines('sales_invoice', 1, [{'account_id': 1, 'debit': 500, 'credit': 0}]);
    await addLines('sales_return', 2, [{'account_id': 1, 'debit': 0, 'credit': 50}]);
    await addLines('sales_debit_note', 1, [{'account_id': 1, 'debit': 40, 'credit': 0}]);
    await addLines('receipt', 1, [{'account_id': 1, 'debit': 0, 'credit': 100}]);
    await addLines('receipt', 2, [{'account_id': 2, 'debit': 0, 'credit': 30}]);
    await addLines('advance_allocation', 1, [{'account_id': 2, 'debit': 20, 'credit': 0}, {'account_id': 1, 'debit': 0, 'credit': 20}]);
    final result = await CustomerLedgerReconciliation.load(db);
    expect(result['customer_ledger_balance'], 470);
    expect(result['control_account_balance'], 470);
    expect(result['difference'], 0);
    expect(result['customer_advance_ledger_balance'], 10);
    expect(result['customer_advance_control_balance'], 10);
    expect(result['customer_advance_difference'], 0);
    expect(result['is_customer_advance_reconciled'], true);
    expect(result['is_reconciled'], true);
  });
  test('excludes later-created opening balances from historical reports', () async {
    final db = await fixture();
    addTearDown(db.close);
    await db.insert('parties', {'id': 1, 'opening_balance': 100, 'balance_type': 'receivable', 'created_at': '2026-02-01'});
    final result = await CustomerLedgerReconciliation.load(db, asOfDate: '2026-01-31');
    expect(result['opening_balance'], 0);
    expect(result['customer_ledger_balance'], 0);
  });
  test('flags unassigned sales and missing customer journals', () async {
    final db = await fixture();
    addTearDown(db.close);
    await db.insert('invoices', {'id': 1, 'invoice_type': 'sale', 'party_id': null, 'invoice_date': '2026-01-01', 'grand_total': 250});
    final result = await CustomerLedgerReconciliation.load(db);
    expect(result['unassigned_sales_count'], 1);
    expect(result['unassigned_sales_total'], 250);
    expect(result['missing_journal_count'], 1);
    expect(result['is_reconciled'], false);
  });
}