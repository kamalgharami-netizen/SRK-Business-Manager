import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:srk_business_manager/src/data/local/accounting_service.dart';

Future<Database> _openAccountingDatabase() async {
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
  for (final code in ['1000', '1100', '1200', '2100', '4000', '5000', '5200']) {
    await db.insert('accounts', {'account_code': code, 'is_active': 1});
  }
  return db;
}

void main() {
  group('AccountingService journal validation', () {
    test('posts a balanced sales invoice including FIFO cost', () async {
      final db = await _openAccountingDatabase();
      addTearDown(db.close);

      await db.transaction((txn) => AccountingService.postSalesInvoice(
            txn,
            invoiceId: 1,
            invoiceNumber: 'INV-001',
            date: '2026-10-31',
            subtotal: 1000,
            tax: 180,
            total: 1180,
            costOfGoodsSold: 600,
          ));

      final entries = await db.query('journal_entries');
      final lines = await db.query('journal_lines');
      final debit = lines.fold<double>(
        0,
        (sum, row) => sum + (row['debit'] as num).toDouble(),
      );
      final credit = lines.fold<double>(
        0,
        (sum, row) => sum + (row['credit'] as num).toDouble(),
      );

      expect(entries, hasLength(1));
      expect(entries.single['status'], 'posted');
      expect(lines, hasLength(5));
      expect(debit, 1780);
      expect(credit, 1780);
    });

    test('rejects a sales invoice when total does not equal subtotal plus tax',
        () async {
      final db = await _openAccountingDatabase();
      addTearDown(db.close);

      await expectLater(
        db.transaction((txn) => AccountingService.postSalesInvoice(
              txn,
              invoiceId: 2,
              invoiceNumber: 'INV-002',
              date: '2026-10-31',
              subtotal: 1000,
              tax: 180,
              total: 1100,
            )),
        throwsA(isA<StateError>()),
      );

      expect(await db.query('journal_entries'), isEmpty);
      expect(await db.query('journal_lines'), isEmpty);
    });


    test('prevents duplicate posted journal entries for the same source', () async {
      final db = await _openAccountingDatabase();
      addTearDown(db.close);

      Future<void> postInvoice() => db.transaction(
            (txn) => AccountingService.postSalesInvoice(
              txn,
              invoiceId: 10,
              invoiceNumber: 'INV-010',
              date: '2026-10-31',
              subtotal: 1000,
              tax: 180,
              total: 1180,
            ),
          );

      await postInvoice();
      await expectLater(postInvoice(), throwsA(isA<StateError>()));

      final entries = await db.query('journal_entries');
      expect(entries, hasLength(1));
      expect(entries.single['status'], 'posted');
      expect(await db.query('journal_lines'), hasLength(3));
    });

    test('rejects an expense with a negative amount', () async {
      final db = await _openAccountingDatabase();
      addTearDown(db.close);

      await expectLater(
        db.transaction((txn) => AccountingService.postExpense(
              txn,
              expenseId: 3,
              date: '2026-10-31',
              category: 'Office',
              description: 'Invalid test expense',
              mode: 'cash',
              amount: -50,
            )),
        throwsA(isA<StateError>()),
      );

      expect(await db.query('journal_entries'), isEmpty);
    });
  });
}
