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
  for (final code in ['1000', '1010', '1100', '1200', '1300', '1310', '1400', '2000', '2100', '2200', '3200', '4000', '5000', '5200']) {
    await db.insert('accounts', {'account_code': code, 'is_active': 1});
  }
  return db;
}

void main() {
  group('AccountingService journal validation', () {
    test('posts opening inventory against opening balance equity', () async {
      final db = await _openAccountingDatabase();
      addTearDown(db.close);

      await db.transaction((txn) => AccountingService.postOpeningInventory(
            txn,
            productId: 7,
            productName: 'Opening item',
            date: '2026-11-03',
            inventoryValue: 250,
          ));

      final entries = await db.query('journal_entries');
      final rows = await db.rawQuery('''
        SELECT a.account_code, jl.debit, jl.credit
        FROM journal_lines jl JOIN accounts a ON a.id = jl.account_id
        ORDER BY jl.id
      ''');
      expect(entries.single['source_type'], 'opening_inventory');
      expect(entries.single['source_id'], 7);
      expect(entries.single['status'], 'posted');
      expect(rows.map((row) => row['account_code']), ['1200', '3200']);
      expect(rows[0]['debit'], 250);
      expect(rows[1]['credit'], 250);
    });

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

    test('posts a balanced sales return including returned inventory cost', () async {
      final db = await _openAccountingDatabase();
      addTearDown(db.close);

      await db.transaction((txn) => AccountingService.postSalesReturn(
            txn,
            returnId: 20,
            returnNumber: 'SR-020',
            date: '2026-10-31',
            subtotal: 100,
            tax: 18,
            total: 118,
            costOfGoodsReturned: 60,
          ));

      final lines = await db.query('journal_lines');
      final debit = lines.fold<double>(0, (sum, row) => sum + (row['debit'] as num).toDouble());
      final credit = lines.fold<double>(0, (sum, row) => sum + (row['credit'] as num).toDouble());
      expect(lines, hasLength(5));
      expect(debit, 178);
      expect(credit, 178);
    });

    test('posts a balanced purchase invoice with input GST and supplier payable', () async {
      final db = await _openAccountingDatabase();
      addTearDown(db.close);

      await db.transaction((txn) => AccountingService.postPurchaseInvoice(
            txn,
            invoiceId: 30,
            invoiceNumber: 'PUR-030',
            date: '2026-10-31',
            subtotal: 1000,
            tax: 180,
            total: 1180,
            itcTreatment: 'eligible',
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
      expect(entries.single['source_type'], 'purchase_invoice');
      expect(entries.single['source_id'], 30);
      expect(entries.single['status'], 'posted');
      expect(lines, hasLength(3));
      expect(debit, 1180);
      expect(credit, 1180);
    });

    test('posts ineligible purchase GST into inventory cost, not input GST', () async {
      final db = await _openAccountingDatabase();
      addTearDown(db.close);

      await db.transaction((txn) => AccountingService.postPurchaseInvoice(
            txn,
            invoiceId: 33,
            invoiceNumber: 'PUR-033',
            date: '2026-10-31',
            subtotal: 1000,
            tax: 180,
            total: 1180,
            itcTreatment: 'ineligible',
          ));

      final lines = await db.query('journal_lines');
      expect(lines, hasLength(2));
      expect(lines[0]['debit'], 1180);
      expect(lines[0]['account_id'], 4);
      expect(lines[1]['credit'], 1180);
    });

    test('holds pending purchase GST in a separate review account', () async {
      final db = await _openAccountingDatabase();
      addTearDown(db.close);

      await db.transaction((txn) => AccountingService.postPurchaseInvoice(
            txn,
            invoiceId: 34,
            invoiceNumber: 'PUR-034',
            date: '2026-10-31',
            subtotal: 1000,
            tax: 180,
            total: 1180,
            itcTreatment: 'pendingReview',
          ));

      final lines = await db.query('journal_lines');
      expect(lines, hasLength(3));
      expect(lines[1]['account_id'], 6);
      expect(lines[1]['debit'], 180);
    });

    test('rejects a purchase invoice whose total does not equal subtotal plus tax', () async {
      final db = await _openAccountingDatabase();
      addTearDown(db.close);

      await expectLater(
        db.transaction((txn) => AccountingService.postPurchaseInvoice(
              txn,
              invoiceId: 31,
              invoiceNumber: 'PUR-031',
              date: '2026-10-31',
              subtotal: 1000,
              tax: 180,
              total: 1100,
              itcTreatment: 'eligible',
            )),
        throwsA(isA<StateError>()),
      );

      expect(await db.query('journal_entries'), isEmpty);
      expect(await db.query('journal_lines'), isEmpty);
    });

    test('prevents duplicate purchase invoice journal posting', () async {
      final db = await _openAccountingDatabase();
      addTearDown(db.close);

      Future<void> postPurchase() => db.transaction(
            (txn) => AccountingService.postPurchaseInvoice(
              txn,
              invoiceId: 32,
              invoiceNumber: 'PUR-032',
              date: '2026-10-31',
              subtotal: 500,
              tax: 90,
              total: 590,
              itcTreatment: 'eligible',
            ),
          );

      await postPurchase();
      await expectLater(postPurchase(), throwsA(isA<StateError>()));

      expect(await db.query('journal_entries'), hasLength(1));
      expect(await db.query('journal_lines'), hasLength(3));
    });

    test('reverses eligible purchase return against input GST and inventory', () async {
      final db = await _openAccountingDatabase();
      addTearDown(db.close);

      await db.transaction((txn) => AccountingService.postPurchaseReturn(
            txn,
            returnId: 21,
            returnNumber: 'PR-021',
            date: '2026-10-31',
            subtotal: 100,
            tax: 18,
            total: 118,
            itcTreatment: 'eligible',
          ));

      final rows = await db.rawQuery('''
        SELECT accounts.account_code, journal_lines.debit, journal_lines.credit
        FROM journal_lines JOIN accounts ON accounts.id = journal_lines.account_id
        ORDER BY journal_lines.id
      ''');
      expect(rows.map((row) => row['account_code']), ['2000', '1200', '1300']);
      expect(rows[0]['debit'], 118);
      expect(rows[1]['credit'], 100);
      expect(rows[2]['credit'], 18);
    });

    test('reverses ineligible purchase GST as part of inventory cost', () async {
      final db = await _openAccountingDatabase();
      addTearDown(db.close);

      await db.transaction((txn) => AccountingService.postPurchaseReturn(
            txn,
            returnId: 22,
            returnNumber: 'PR-022',
            date: '2026-10-31',
            subtotal: 100,
            tax: 18,
            total: 118,
            itcTreatment: 'ineligible',
          ));

      final rows = await db.rawQuery('''
        SELECT accounts.account_code, journal_lines.debit, journal_lines.credit
        FROM journal_lines JOIN accounts ON accounts.id = journal_lines.account_id
        ORDER BY journal_lines.id
      ''');
      expect(rows.map((row) => row['account_code']), ['2000', '1200']);
      expect(rows[0]['debit'], 118);
      expect(rows[1]['credit'], 118);
    });

    test('reverses pending-review GST from the pending input GST account', () async {
      final db = await _openAccountingDatabase();
      addTearDown(db.close);

      await db.transaction((txn) => AccountingService.postPurchaseReturn(
            txn,
            returnId: 23,
            returnNumber: 'PR-023',
            date: '2026-10-31',
            subtotal: 100,
            tax: 18,
            total: 118,
            itcTreatment: 'pendingReview',
          ));

      final rows = await db.rawQuery('''
        SELECT accounts.account_code, journal_lines.debit, journal_lines.credit
        FROM journal_lines JOIN accounts ON accounts.id = journal_lines.account_id
        ORDER BY journal_lines.id
      ''');
      expect(rows.map((row) => row['account_code']), ['2000', '1200', '1310']);
      expect(rows[0]['debit'], 118);
      expect(rows[1]['credit'], 100);
      expect(rows[2]['credit'], 18);
    });

    test('rejects invalid purchase return totals before posting', () async {
      final db = await _openAccountingDatabase();
      addTearDown(db.close);

      await expectLater(
        db.transaction((txn) => AccountingService.postPurchaseReturn(
              txn,
              returnId: 24,
              returnNumber: 'PR-024',
              date: '2026-10-31',
              subtotal: 100,
              tax: 18,
              total: 110,
              itcTreatment: 'eligible',
            )),
        throwsA(isA<StateError>()),
      );
      expect(await db.query('journal_entries'), isEmpty);
      expect(await db.query('journal_lines'), isEmpty);
    });

    test('rejects a journal line with an infinite amount', () async {
      final db = await _openAccountingDatabase();
      addTearDown(db.close);

      await expectLater(
        db.transaction((txn) => AccountingService.postExpense(
              txn,
              expenseId: 22,
              date: '2026-10-31',
              category: 'Office',
              description: 'Non-finite test expense',
              mode: 'cash',
              amount: double.infinity,
            )),
        throwsArgumentError,
      );
      expect(await db.query('journal_entries'), isEmpty);
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
        throwsArgumentError,
      );

      expect(await db.query('journal_entries'), isEmpty);
    });

    test('posts a balanced customer receipt journal', () async {
      final db = await _openAccountingDatabase();
      addTearDown(db.close);

      await db.transaction((txn) => AccountingService.postPayment(
            txn,
            paymentId: 41,
            date: '2026-10-31',
            paymentType: 'receipt',
            mode: 'upi',
            amount: 250,
            reference: 'UPI-REF-41',
          ));

      final entry = (await db.query('journal_entries')).single;
      final lines = await db.query('journal_lines');
      expect(entry['source_type'], 'receipt');
      expect(entry['source_id'], 41);
      expect(lines, hasLength(2));
      expect(lines[0]['debit'], 250);
      expect(lines[1]['credit'], 250);
    });

    test('posts an unallocated customer receipt to customer advances', () async {
      final db = await _openAccountingDatabase();
      addTearDown(db.close);

      await db.transaction((txn) => AccountingService.postPayment(
            txn,
            paymentId: 43,
            date: '2026-11-02',
            paymentType: 'receipt',
            mode: 'cash',
            amount: 500,
            reference: 'ADV-43',
            invoiceLinked: false,
          ));

      final lines = await db.rawQuery('''
        SELECT accounts.account_code, journal_lines.debit, journal_lines.credit
        FROM journal_lines JOIN accounts ON accounts.id = journal_lines.account_id
        ORDER BY journal_lines.id
      ''');
      expect(lines.map((row) => row['account_code']), ['1000', '2200']);
      expect(lines[0]['debit'], 500);
      expect(lines[1]['credit'], 500);
    });

    test('posts an unallocated supplier payment to supplier advances', () async {
      final db = await _openAccountingDatabase();
      addTearDown(db.close);

      await db.transaction((txn) => AccountingService.postPayment(
            txn,
            paymentId: 44,
            date: '2026-11-02',
            paymentType: 'payment',
            mode: 'upi',
            amount: 275,
            reference: 'ADV-44',
            invoiceLinked: false,
          ));

      final lines = await db.rawQuery('''
        SELECT accounts.account_code, journal_lines.debit, journal_lines.credit
        FROM journal_lines JOIN accounts ON accounts.id = journal_lines.account_id
        ORDER BY journal_lines.id
      ''');
      expect(lines.map((row) => row['account_code']), ['1400', '1010']);
      expect(lines[0]['debit'], 275);
      expect(lines[1]['credit'], 275);
    });

    test('rejects unsupported payment types, modes, and non-positive amounts', () async {
      final db = await _openAccountingDatabase();
      addTearDown(db.close);

      Future<void> post({String type = 'receipt', String mode = 'cash', double amount = 10}) =>
          db.transaction((txn) => AccountingService.postPayment(
                txn,
                paymentId: 45,
                date: '2026-11-02',
                paymentType: type,
                mode: mode,
                amount: amount,
                reference: null,
              ));

      await expectLater(post(type: 'refund'), throwsArgumentError);
      await expectLater(post(mode: 'crypto'), throwsArgumentError);
      await expectLater(post(amount: double.infinity), throwsArgumentError);
      await expectLater(post(amount: 0), throwsArgumentError);
      expect(await db.query('journal_entries'), isEmpty);
    });

    test('posts a balanced supplier payment journal', () async {
      final db = await _openAccountingDatabase();
      addTearDown(db.close);

      await db.transaction((txn) => AccountingService.postPayment(
            txn,
            paymentId: 42,
            date: '2026-10-31',
            paymentType: 'payment',
            mode: 'cash',
            amount: 375,
            reference: 'CASH-REF-42',
          ));

      final entry = (await db.query('journal_entries')).single;
      final lines = await db.query('journal_lines');
      expect(entry['source_type'], 'payment');
      expect(entry['source_id'], 42);
      expect(lines, hasLength(2));
      expect(lines[0]['debit'], 375);
      expect(lines[1]['credit'], 375);
    });

    test('posts a balanced customer advance allocation without cash movement', () async {
      final db = await _openAccountingDatabase();
      addTearDown(db.close);
      await db.transaction((txn) => AccountingService.postAdvanceAllocation(
        txn, allocationId: 501, date: '2026-11-02', paymentType: 'receipt', amount: 125,
      ));
      final lines = await db.rawQuery('''
        SELECT accounts.account_code, journal_lines.debit, journal_lines.credit
        FROM journal_lines JOIN accounts ON accounts.id = journal_lines.account_id
        ORDER BY journal_lines.id
      ''');
      expect(lines.map((row) => row['account_code']), ['2200', '1100']);
      expect(lines[0]['debit'], 125);
      expect(lines[1]['credit'], 125);
    });

    test('posts a balanced supplier advance allocation without bank movement', () async {
      final db = await _openAccountingDatabase();
      addTearDown(db.close);
      await db.transaction((txn) => AccountingService.postAdvanceAllocation(
        txn, allocationId: 502, date: '2026-11-02', paymentType: 'payment', amount: 90,
      ));
      final lines = await db.rawQuery('''
        SELECT accounts.account_code, journal_lines.debit, journal_lines.credit
        FROM journal_lines JOIN accounts ON accounts.id = journal_lines.account_id
        ORDER BY journal_lines.id
      ''');
      expect(lines.map((row) => row['account_code']), ['2000', '1400']);
      expect(lines[0]['debit'], 90);
      expect(lines[1]['credit'], 90);
    });

    test('prevents duplicate journal posting for the same advance allocation', () async {
      final db = await _openAccountingDatabase();
      addTearDown(db.close);
      Future<void> post() => db.transaction((txn) => AccountingService.postAdvanceAllocation(
        txn, allocationId: 503, date: '2026-11-02', paymentType: 'receipt', amount: 20,
      ));
      await post();
      await expectLater(post(), throwsA(isA<StateError>()));
      expect(await db.query('journal_entries'), hasLength(1));
    });

    test('rejects unsupported expense payment modes', () async {
      final db = await _openAccountingDatabase();
      addTearDown(db.close);

      await expectLater(
        db.transaction((txn) => AccountingService.postExpense(
          txn,
          expenseId: 80,
          date: '2026-11-04',
          category: 'Office',
          description: 'Unsupported mode',
          mode: 'crypto',
          amount: 100,
        )),
        throwsArgumentError,
      );
      expect(await db.query('journal_entries'), isEmpty);
      expect(await db.query('journal_lines'), isEmpty);
    });

    test('rejects zero, negative and non-finite expense amounts', () async {
      final db = await _openAccountingDatabase();
      addTearDown(db.close);

      Future<void> post(double amount) => db.transaction((txn) =>
        AccountingService.postExpense(
          txn,
          expenseId: 81,
          date: '2026-11-04',
          category: 'Office',
          description: 'Invalid amount',
          mode: 'cash',
          amount: amount,
        ));

      await expectLater(post(0), throwsArgumentError);
      await expectLater(post(-1), throwsArgumentError);
      await expectLater(post(double.infinity), throwsArgumentError);
      await expectLater(post(double.nan), throwsArgumentError);
      expect(await db.query('journal_entries'), isEmpty);
      expect(await db.query('journal_lines'), isEmpty);
    });

    test('normalizes supported expense payment modes', () async {
      final db = await _openAccountingDatabase();
      addTearDown(db.close);

      await db.transaction((txn) => AccountingService.postExpense(
        txn,
        expenseId: 82,
        date: '2026-11-04',
        category: 'Office',
        description: 'Bank expense',
        mode: ' BANK ',
        amount: 125,
      ));
      final rows = await db.rawQuery('''
        SELECT accounts.account_code, journal_lines.debit, journal_lines.credit
        FROM journal_lines JOIN accounts ON accounts.id = journal_lines.account_id
        ORDER BY journal_lines.id
      ''');
      expect(rows.map((row) => row['account_code']), ['5200', '1010']);
      expect(rows[0]['debit'], 125);
      expect(rows[1]['credit'], 125);
    });
  });
}
