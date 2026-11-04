import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:srk_business_manager/src/data/local/gst_ledger_reconciliation.dart';

Future<Database> _openDb() async {
  sqfliteFfiInit();
  final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
  await db.execute('''
    CREATE TABLE invoices (
      id INTEGER PRIMARY KEY, invoice_type TEXT NOT NULL,
      invoice_date TEXT NOT NULL, tax_total REAL NOT NULL,
      parent_invoice_id INTEGER
    )
  ''');
  await db.execute('''
    CREATE TABLE debit_notes (
      id INTEGER PRIMARY KEY, note_date TEXT NOT NULL,
      tax_total REAL NOT NULL, status TEXT NOT NULL
    )
  ''');
  await db.execute('''
    CREATE TABLE purchase_itc_assessments (
      purchase_invoice_id INTEGER PRIMARY KEY, treatment TEXT NOT NULL
    )
  ''');
  await db.execute('''
    CREATE TABLE accounts (
      id INTEGER PRIMARY KEY, account_code TEXT NOT NULL
    )
  ''');
  await db.execute('''
    CREATE TABLE journal_entries (
      id INTEGER PRIMARY KEY, source_type TEXT NOT NULL,
      source_id INTEGER, entry_date TEXT NOT NULL, status TEXT NOT NULL
    )
  ''');
  await db.execute('''
    CREATE TABLE journal_lines (
      id INTEGER PRIMARY KEY, journal_entry_id INTEGER NOT NULL,
      account_id INTEGER NOT NULL, debit REAL NOT NULL, credit REAL NOT NULL
    )
  ''');
  await db.insert('accounts', {'id': 1, 'account_code': '2100'});
  await db.insert('accounts', {'id': 2, 'account_code': '1300'});
  await db.insert('accounts', {'id': 3, 'account_code': '1310'});
  return db;
}

Future<void> _journal(Database db, {
  required int id, required String source, required int sourceId,
  required String date, required int accountId,
  double debit = 0, double credit = 0,
}) async {
  await db.insert('journal_entries', {
    'id': id, 'source_type': source, 'source_id': sourceId,
    'entry_date': date, 'status': 'posted',
  });
  await db.insert('journal_lines', {
    'journal_entry_id': id, 'account_id': accountId,
    'debit': debit, 'credit': credit,
  });
}

void main() {
  group('GST ledger reconciliation', () {
    test('reconciles output GST, eligible ITC and pending ITC including returns', () async {
      final db = await _openDb();
      addTearDown(db.close);
      await db.insert('invoices', {'id': 1, 'invoice_type': 'sale', 'invoice_date': '2026-11-01', 'tax_total': 18});
      await db.insert('invoices', {'id': 2, 'invoice_type': 'sales_return', 'invoice_date': '2026-11-01', 'tax_total': 9});
      await db.insert('debit_notes', {'id': 3, 'note_date': '2026-11-01', 'tax_total': 3, 'status': 'posted'});
      await db.insert('invoices', {'id': 4, 'invoice_type': 'purchase', 'invoice_date': '2026-11-01', 'tax_total': 18});
      await db.insert('purchase_itc_assessments', {'purchase_invoice_id': 4, 'treatment': 'eligible'});
      await db.insert('invoices', {'id': 5, 'invoice_type': 'purchase_return', 'invoice_date': '2026-11-01', 'tax_total': 9, 'parent_invoice_id': 4});
      await db.insert('invoices', {'id': 6, 'invoice_type': 'purchase', 'invoice_date': '2026-11-01', 'tax_total': 5});
      await db.insert('purchase_itc_assessments', {'purchase_invoice_id': 6, 'treatment': 'pendingReview'});

      await _journal(db, id: 1, source: 'sales_invoice', sourceId: 1, date: '2026-11-01', accountId: 1, credit: 18);
      await _journal(db, id: 2, source: 'sales_return', sourceId: 2, date: '2026-11-01', accountId: 1, debit: 9);
      await _journal(db, id: 3, source: 'sales_debit_note', sourceId: 3, date: '2026-11-01', accountId: 1, credit: 3);
      await _journal(db, id: 4, source: 'purchase_invoice', sourceId: 4, date: '2026-11-01', accountId: 2, debit: 18);
      await _journal(db, id: 5, source: 'purchase_return', sourceId: 5, date: '2026-11-01', accountId: 2, credit: 9);
      await _journal(db, id: 6, source: 'purchase_invoice', sourceId: 6, date: '2026-11-01', accountId: 3, debit: 5);

      final result = await GstLedgerReconciliation.load(db);
      expect(result['output_gst_expected'], 12);
      expect(result['output_gst_control'], 12);
      expect(result['eligible_itc_expected'], 9);
      expect(result['eligible_itc_control'], 9);
      expect(result['pending_itc_expected'], 5);
      expect(result['pending_itc_control'], 5);
      expect(result['missing_journal_count'], 0);
      expect(result['is_reconciled'], isTrue);
    });

    test('flags missing journals and ledger differences without changing data', () async {
      final db = await _openDb();
      addTearDown(db.close);
      await db.insert('invoices', {'id': 1, 'invoice_type': 'sale', 'invoice_date': '2026-11-01', 'tax_total': 18});
      await _journal(db, id: 1, source: 'sales_invoice', sourceId: 1, date: '2026-11-01', accountId: 1, credit: 10);
      await db.insert('invoices', {'id': 2, 'invoice_type': 'purchase', 'invoice_date': '2026-11-01', 'tax_total': 7});
      final beforeEntries = await db.query('journal_entries');
      final result = await GstLedgerReconciliation.load(db);
      expect(result['output_gst_difference'], 8);
      expect(result['missing_journal_count'], 1);
      expect(result['missing_journal_tax'], 7);
      expect(result['missing_assessment_count'], 1);
      expect(result['is_reconciled'], isFalse);
      expect(await db.query('journal_entries'), beforeEntries);
    });

    test('excludes ineligible purchases and their returns from eligible and pending ITC', () async {
      final db = await _openDb();
      addTearDown(db.close);
      await db.insert('accounts', {'id': 4, 'account_code': '5000'});
      await db.insert('invoices', {
        'id': 10, 'invoice_type': 'purchase',
        'invoice_date': '2026-11-01', 'tax_total': 18,
      });
      await db.insert('purchase_itc_assessments', {
        'purchase_invoice_id': 10, 'treatment': 'ineligible',
      });
      await db.insert('invoices', {
        'id': 11, 'invoice_type': 'purchase_return',
        'invoice_date': '2026-11-02', 'tax_total': 6,
        'parent_invoice_id': 10,
      });
      // Both source documents have posted journals, but neither amount belongs
      // in eligible ITC (1300) or pending ITC (1310).
      await _journal(
        db, id: 10, source: 'purchase_invoice', sourceId: 10,
        date: '2026-11-01', accountId: 4, debit: 18,
      );
      await _journal(
        db, id: 11, source: 'purchase_return', sourceId: 11,
        date: '2026-11-02', accountId: 4, credit: 6,
      );

      final result = await GstLedgerReconciliation.load(db);
      expect(result['eligible_itc_expected'], 0);
      expect(result['eligible_itc_control'], 0);
      expect(result['pending_itc_expected'], 0);
      expect(result['pending_itc_control'], 0);
      expect(result['missing_assessment_count'], 0);
      expect(result['missing_journal_count'], 0);
      expect(result['is_reconciled'], isTrue);
    });

    test('applies the selected report date range to documents and journals', () async {
      final db = await _openDb();
      addTearDown(db.close);
      await db.insert('invoices', {'id': 1, 'invoice_type': 'sale', 'invoice_date': '2026-10-31', 'tax_total': 18});
      await db.insert('invoices', {'id': 2, 'invoice_type': 'sale', 'invoice_date': '2026-11-02', 'tax_total': 5});
      await _journal(db, id: 1, source: 'sales_invoice', sourceId: 1, date: '2026-10-31', accountId: 1, credit: 18);
      await _journal(db, id: 2, source: 'sales_invoice', sourceId: 2, date: '2026-11-02', accountId: 1, credit: 5);
      final result = await GstLedgerReconciliation.load(
        db, startDate: '2026-11-01', endDate: '2026-11-30',
      );
      expect(result['output_gst_expected'], 5);
      expect(result['output_gst_control'], 5);
      expect(result['missing_journal_count'], 0);
      expect(result['is_reconciled'], isTrue);
    });
  });
}
