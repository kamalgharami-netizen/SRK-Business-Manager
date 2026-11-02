import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:srk_business_manager/src/data/local/accounting_service.dart';

Future<Database> _openDebitNoteAccountingDatabase() async {
  sqfliteFfiInit();
  final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
  await db.execute('''
    CREATE TABLE accounts (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      account_code TEXT NOT NULL,
      is_active INTEGER NOT NULL DEFAULT 1
    )
  ''');
  await db.execute('''
    CREATE TABLE journal_entries (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      entry_number TEXT NOT NULL,
      entry_date TEXT NOT NULL,
      source_type TEXT NOT NULL,
      source_id INTEGER NOT NULL,
      memo TEXT NOT NULL,
      status TEXT NOT NULL
    )
  ''');
  await db.execute('''
    CREATE TABLE journal_lines (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      journal_entry_id INTEGER NOT NULL,
      account_id INTEGER NOT NULL,
      description TEXT,
      debit REAL NOT NULL DEFAULT 0,
      credit REAL NOT NULL DEFAULT 0
    )
  ''');
  for (final code in ['1100', '2100', '4000']) {
    await db.insert('accounts', {'account_code': code, 'is_active': 1});
  }
  return db;
}

void main() {
  group('Sales debit note accounting', () {
    test('posts receivable, revenue and output GST as a balanced journal', () async {
      final db = await _openDebitNoteAccountingDatabase();
      addTearDown(db.close);

      await db.transaction((txn) => AccountingService.postSalesDebitNote(
            txn,
            debitNoteId: 7,
            debitNoteNumber: 'DN-007',
            date: '2026-11-02',
            taxableValue: 1000,
            tax: 180,
            total: 1180,
          ));

      final entries = await db.query('journal_entries');
      final rows = await db.rawQuery('''
        SELECT a.account_code, jl.debit, jl.credit
        FROM journal_lines jl
        INNER JOIN accounts a ON a.id = jl.account_id
        ORDER BY a.account_code
      ''');
      final debit = rows.fold<double>(
        0,
        (sum, row) => sum + (row['debit'] as num).toDouble(),
      );
      final credit = rows.fold<double>(
        0,
        (sum, row) => sum + (row['credit'] as num).toDouble(),
      );

      expect(entries, hasLength(1));
      expect(entries.single['source_type'], 'sales_debit_note');
      expect(entries.single['source_id'], 7);
      expect(entries.single['status'], 'posted');
      expect(rows, hasLength(3));
      expect(rows, contains(predicate<Map<String, Object?>>(
        (row) => row['account_code'] == '1100' && row['debit'] == 1180,
      )));
      expect(rows, contains(predicate<Map<String, Object?>>(
        (row) => row['account_code'] == '4000' && row['credit'] == 1000,
      )));
      expect(rows, contains(predicate<Map<String, Object?>>(
        (row) => row['account_code'] == '2100' && row['credit'] == 180,
      )));
      expect(debit, 1180);
      expect(credit, 1180);
    });

    test('rejects totals that do not equal taxable value plus tax', () async {
      final db = await _openDebitNoteAccountingDatabase();
      addTearDown(db.close);

      await expectLater(
        db.transaction((txn) => AccountingService.postSalesDebitNote(
              txn,
              debitNoteId: 8,
              debitNoteNumber: 'DN-008',
              date: '2026-11-02',
              taxableValue: 1000,
              tax: 180,
              total: 1100,
            )),
        throwsA(isA<StateError>()),
      );

      expect(await db.query('journal_entries'), isEmpty);
      expect(await db.query('journal_lines'), isEmpty);
    });

    test('prevents duplicate journal posting for the same debit note', () async {
      final db = await _openDebitNoteAccountingDatabase();
      addTearDown(db.close);

      Future<void> post() => db.transaction(
            (txn) => AccountingService.postSalesDebitNote(
              txn,
              debitNoteId: 9,
              debitNoteNumber: 'DN-009',
              date: '2026-11-02',
              taxableValue: 1000,
              tax: 180,
              total: 1180,
            ),
          );

      await post();
      await expectLater(post(), throwsA(isA<StateError>()));

      expect(await db.query('journal_entries'), hasLength(1));
      expect(await db.query('journal_lines'), hasLength(3));
    });
  });
}
