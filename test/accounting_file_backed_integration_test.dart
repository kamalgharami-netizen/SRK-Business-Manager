import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:srk_business_manager/src/data/local/accounting_service.dart';

void main() {
  setUpAll(sqfliteFfiInit);

  late String databasePath;
  late Database db;

  Future<Database> openFixture() async {
    final database = await databaseFactoryFfi.openDatabase(databasePath);
    await database.execute('''
      CREATE TABLE IF NOT EXISTS accounts (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        account_code TEXT NOT NULL UNIQUE,
        is_active INTEGER NOT NULL DEFAULT 1
      )
    ''');
    await database.execute('''
      CREATE TABLE IF NOT EXISTS journal_entries (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        entry_number TEXT NOT NULL,
        entry_date TEXT NOT NULL,
        source_type TEXT NOT NULL,
        source_id INTEGER NOT NULL,
        memo TEXT NOT NULL,
        status TEXT NOT NULL
      )
    ''');
    await database.execute('''
      CREATE TABLE IF NOT EXISTS journal_lines (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        journal_entry_id INTEGER NOT NULL,
        account_id INTEGER NOT NULL,
        description TEXT,
        debit REAL NOT NULL DEFAULT 0,
        credit REAL NOT NULL DEFAULT 0
      )
    ''');
    for (final code in [
      '1000', '1010', '1100', '1200', '1300', '1310', '1400',
      '2000', '2100', '2200', '3200', '4000', '5000', '5200',
    ]) {
      await database.insert(
        'accounts',
        {'account_code': code, 'is_active': 1},
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
    }
    return database;
  }

  setUp(() async {
    databasePath = p.join(
      Directory.systemTemp.path,
      'srk_accounting_integration_${DateTime.now().microsecondsSinceEpoch}.sqlite',
    );
    db = await openFixture();
  });

  tearDown(() async {
    await db.close();
    final file = File(databasePath);
    if (await file.exists()) await file.delete();
  });

  test('persists balanced mixed sales, purchase and payment journals after restart', () async {
    await db.transaction((txn) async {
      await AccountingService.postSalesInvoice(
        txn,
        invoiceId: 101,
        invoiceNumber: 'SALE-101',
        date: '2026-11-04',
        subtotal: 1000,
        tax: 180,
        total: 1180,
        costOfGoodsSold: 600,
      );
      await AccountingService.postPurchaseInvoice(
        txn,
        invoiceId: 202,
        invoiceNumber: 'PUR-202',
        date: '2026-11-04',
        subtotal: 500,
        tax: 90,
        total: 590,
        itcTreatment: 'eligible',
      );
      await AccountingService.postPayment(
        txn,
        paymentId: 303,
        date: '2026-11-04',
        paymentType: 'receipt',
        mode: 'upi',
        amount: 300,
        reference: 'RCPT-303',
      );
      await AccountingService.postExpense(
        txn,
        expenseId: 404,
        date: '2026-11-04',
        category: 'Office',
        description: 'Stationery',
        mode: 'cash',
        amount: 50,
      );
    });

    final beforeRestart = await db.rawQuery('''
      SELECT COUNT(*) AS entries,
             (SELECT COUNT(*) FROM journal_lines) AS lines,
             COALESCE(SUM(debit), 0) AS debit,
             COALESCE(SUM(credit), 0) AS credit
      FROM journal_entries je
      LEFT JOIN journal_lines jl ON jl.journal_entry_id = je.id
      WHERE je.status = 'posted'
    ''');
    expect(beforeRestart.single['entries'], 4);
    expect((beforeRestart.single['debit'] as num).toDouble(),
        closeTo((beforeRestart.single['credit'] as num).toDouble(), 0.005));

    await db.close();
    db = await openFixture();

    final persisted = await db.rawQuery('''
      SELECT je.source_type, je.source_id,
             COUNT(jl.id) AS line_count,
             COALESCE(SUM(jl.debit), 0) AS debit,
             COALESCE(SUM(jl.credit), 0) AS credit
      FROM journal_entries je
      JOIN journal_lines jl ON jl.journal_entry_id = je.id
      WHERE je.status = 'posted'
      GROUP BY je.id
      ORDER BY je.source_type
    ''');
    expect(persisted, hasLength(4));
    for (final entry in persisted) {
      expect((entry['line_count'] as int), greaterThanOrEqualTo(2));
      expect((entry['debit'] as num).toDouble(),
          closeTo((entry['credit'] as num).toDouble(), 0.005));
    }
    expect(
      persisted.map((row) => row['source_type']).toSet(),
      {'sales_invoice', 'purchase_invoice', 'receipt', 'expense'},
    );
  });

  test('rejects duplicate source posting after database reopen', () async {
    await db.transaction((txn) => AccountingService.postSalesInvoice(
      txn,
      invoiceId: 909,
      invoiceNumber: 'SALE-909',
      date: '2026-11-04',
      subtotal: 200,
      tax: 36,
      total: 236,
    ));

    await db.close();
    db = await openFixture();

    await expectLater(
      db.transaction((txn) => AccountingService.postSalesInvoice(
        txn,
        invoiceId: 909,
        invoiceNumber: 'SALE-909',
        date: '2026-11-04',
        subtotal: 200,
        tax: 36,
        total: 236,
      )),
      throwsA(isA<StateError>()),
    );
    expect(await db.query('journal_entries'), hasLength(1));
    expect(await db.query('journal_lines'), hasLength(3));
  });
}
