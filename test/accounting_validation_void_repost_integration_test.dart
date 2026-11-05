import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:srk_business_manager/src/data/local/accounting_service.dart';

void main() {
  setUpAll(sqfliteFfiInit);

  late String path;
  late Database db;

  Future<Database> openFixture() async {
    final value = await databaseFactoryFfi.openDatabase(path);
    await value.execute('''
      CREATE TABLE IF NOT EXISTS accounts (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        account_code TEXT NOT NULL UNIQUE,
        is_active INTEGER NOT NULL DEFAULT 1
      )
    ''');
    await value.execute('''
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
    await value.execute('''
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
      await value.insert(
        'accounts',
        {'account_code': code, 'is_active': 1},
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
    }
    return value;
  }

  setUp(() async {
    path = p.join(
      Directory.systemTemp.path,
      'srk_accounting_validation_${DateTime.now().microsecondsSinceEpoch}.sqlite',
    );
    db = await openFixture();
  });

  tearDown(() async {
    await db.close();
    final file = File(path);
    if (await file.exists()) await file.delete();
  });

  Future<void> postSimpleSale(int id) => db.transaction((txn) =>
      AccountingService.postSalesInvoice(
        txn,
        invoiceId: id,
        invoiceNumber: 'S-$id',
        date: '2026-11-05',
        subtotal: 100,
        tax: 0,
        total: 100,
      ));

  test('posts zero-tax sales invoice and balances the journal', () async {
    await postSimpleSale(1);
    final rows = await db.rawQuery('''
      SELECT a.account_code, jl.debit, jl.credit
      FROM journal_entries je
      JOIN journal_lines jl ON jl.journal_entry_id = je.id
      JOIN accounts a ON a.id = jl.account_id
      WHERE je.source_type = 'sales_invoice' AND je.source_id = 1
    ''');
    expect(rows, hasLength(2));
    expect(rows.map((row) => row['account_code']).toSet(), {'1100', '4000'});
    final debit = rows.fold<double>(0, (sum, row) => sum + (row['debit'] as num).toDouble());
    final credit = rows.fold<double>(0, (sum, row) => sum + (row['credit'] as num).toDouble());
    expect(debit, 100);
    expect(credit, 100);
  });

  test('allows a voided source journal to be reposted without duplicating posted entries', () async {
    await postSimpleSale(2);
    await db.update(
      'journal_entries',
      {'status': 'void'},
      where: 'source_type = ? AND source_id = ?',
      whereArgs: ['sales_invoice', 2],
    );

    await postSimpleSale(2);

    final rows = await db.query(
      'journal_entries',
      where: 'source_type = ? AND source_id = ?',
      whereArgs: ['sales_invoice', 2],
    );
    expect(rows, hasLength(2));
    expect(rows.where((row) => row['status'] == 'void'), hasLength(1));
    expect(rows.where((row) => row['status'] == 'posted'), hasLength(1));
  });

  test('rejects missing or inactive required accounts without partial writes', () async {
    await db.update(
      'accounts',
      {'is_active': 0},
      where: 'account_code = ?',
      whereArgs: ['4000'],
    );

    await expectLater(postSimpleSale(3), throwsA(isA<StateError>()));
    expect(await db.query('journal_entries'), isEmpty);
    expect(await db.query('journal_lines'), isEmpty);
  });

  test('rejects unsupported payment mode and non-finite or non-positive amounts', () async {
    Future<void> postPayment({
      required int id,
      required String mode,
      required double amount,
    }) => db.transaction((txn) => AccountingService.postPayment(
      txn,
      paymentId: id,
      date: '2026-11-05',
      paymentType: 'receipt',
      mode: mode,
      amount: amount,
      reference: 'validation',
    ));

    await expectLater(
      postPayment(id: 4, mode: 'crypto', amount: 10),
      throwsA(isA<ArgumentError>()),
    );
    await expectLater(
      postPayment(id: 5, mode: 'cash', amount: double.nan),
      throwsA(isA<ArgumentError>()),
    );
    await expectLater(
      postPayment(id: 6, mode: 'cash', amount: double.infinity),
      throwsA(isA<ArgumentError>()),
    );
    await expectLater(
      postPayment(id: 7, mode: 'cash', amount: 0),
      throwsA(isA<ArgumentError>()),
    );
    expect(await db.query('journal_entries'), isEmpty);
    expect(await db.query('journal_lines'), isEmpty);
  });

  test('rejects negative and non-finite sales values without journal writes', () async {
    Future<void> postSale({
      required int id,
      required double subtotal,
      required double tax,
      required double total,
    }) => db.transaction((txn) => AccountingService.postSalesInvoice(
      txn,
      invoiceId: id,
      invoiceNumber: 'S-$id',
      date: '2026-11-05',
      subtotal: subtotal,
      tax: tax,
      total: total,
    ));

    await expectLater(
      postSale(id: 8, subtotal: -1, tax: 0, total: 0),
      throwsA(isA<StateError>()),
    );
    await expectLater(
      postSale(id: 9, subtotal: double.infinity, tax: 0, total: double.infinity),
      throwsA(isA<StateError>()),
    );
    await expectLater(
      postSale(id: 10, subtotal: double.nan, tax: 0, total: double.nan),
      throwsA(isA<StateError>()),
    );
    expect(await db.query('journal_entries'), isEmpty);
    expect(await db.query('journal_lines'), isEmpty);
  });
}
