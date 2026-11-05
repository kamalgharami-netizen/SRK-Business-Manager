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
      'srk_exact_journal_${DateTime.now().microsecondsSinceEpoch}.sqlite',
    );
    db = await openFixture();
  });

  tearDown(() async {
    await db.close();
    final file = File(databasePath);
    if (await file.exists()) await file.delete();
  });

  Future<Map<String, Map<String, double>>> linesFor(String source, int id) async {
    final rows = await db.rawQuery('''
      SELECT a.account_code, jl.debit, jl.credit
      FROM journal_entries je
      JOIN journal_lines jl ON jl.journal_entry_id = je.id
      JOIN accounts a ON a.id = jl.account_id
      WHERE je.source_type = ? AND je.source_id = ? AND je.status = 'posted'
      ORDER BY a.account_code
    ''', [source, id]);
    return {
      for (final row in rows)
        row['account_code'] as String: {
          'debit': (row['debit'] as num).toDouble(),
          'credit': (row['credit'] as num).toDouble(),
        },
    };
  }

  test('posts exact sales journal including output GST and FIFO cost', () async {
    await db.transaction((txn) => AccountingService.postSalesInvoice(
      txn,
      invoiceId: 11,
      invoiceNumber: 'S-11',
      date: '2026-11-05',
      subtotal: 1000,
      tax: 180,
      total: 1180,
      costOfGoodsSold: 625,
    ));

    expect(await linesFor('sales_invoice', 11), {
      '1100': {'debit': 1180, 'credit': 0},
      '1200': {'debit': 0, 'credit': 625},
      '2100': {'debit': 0, 'credit': 180},
      '4000': {'debit': 0, 'credit': 1000},
      '5000': {'debit': 625, 'credit': 0},
    });
  });

  test('posts purchase ITC to eligible, ineligible and pending-review accounts', () async {
    for (final treatment in ['eligible', 'ineligible', 'pendingReview']) {
      final id = treatment == 'eligible' ? 21 : treatment == 'ineligible' ? 22 : 23;
      await db.transaction((txn) => AccountingService.postPurchaseInvoice(
        txn,
        invoiceId: id,
        invoiceNumber: 'P-$id',
        date: '2026-11-05',
        subtotal: 500,
        tax: 90,
        total: 590,
        itcTreatment: treatment,
      ));
    }

    expect(await linesFor('purchase_invoice', 21), {
      '1200': {'debit': 500, 'credit': 0},
      '1300': {'debit': 90, 'credit': 0},
      '2000': {'debit': 0, 'credit': 590},
    });
    expect(await linesFor('purchase_invoice', 22), {
      '1200': {'debit': 590, 'credit': 0},
      '2000': {'debit': 0, 'credit': 590},
    });
    expect(await linesFor('purchase_invoice', 23), {
      '1200': {'debit': 500, 'credit': 0},
      '1310': {'debit': 90, 'credit': 0},
      '2000': {'debit': 0, 'credit': 590},
    });
  });

  test('posts sales return at restored FIFO cost and reverses purchase ITC', () async {
    await db.transaction((txn) async {
      await AccountingService.postSalesReturn(
        txn,
        returnId: 31,
        returnNumber: 'SR-31',
        date: '2026-11-05',
        subtotal: 200,
        tax: 36,
        total: 236,
        costOfGoodsReturned: 125,
      );
      await AccountingService.postPurchaseReturn(
        txn,
        returnId: 32,
        returnNumber: 'PR-32',
        date: '2026-11-05',
        subtotal: 100,
        tax: 18,
        total: 118,
        itcTreatment: 'eligible',
      );
    });

    expect(await linesFor('sales_return', 31), {
      '1100': {'debit': 0, 'credit': 236},
      '1200': {'debit': 125, 'credit': 0},
      '2100': {'debit': 36, 'credit': 0},
      '4000': {'debit': 200, 'credit': 0},
      '5000': {'debit': 0, 'credit': 125},
    });
    expect(await linesFor('purchase_return', 32), {
      '1300': {'debit': 0, 'credit': 18},
      '1200': {'debit': 0, 'credit': 100},
      '2000': {'debit': 118, 'credit': 0},
    });
  });

  test('separates linked settlement from customer and supplier advances', () async {
    await db.transaction((txn) async {
      await AccountingService.postPayment(
        txn, paymentId: 41, date: '2026-11-05', paymentType: 'receipt',
        mode: 'upi', amount: 75, reference: 'linked receipt', invoiceLinked: true,
      );
      await AccountingService.postPayment(
        txn, paymentId: 42, date: '2026-11-05', paymentType: 'receipt',
        mode: 'cash', amount: 25, reference: 'customer advance', invoiceLinked: false,
      );
      await AccountingService.postPayment(
        txn, paymentId: 43, date: '2026-11-05', paymentType: 'payment',
        mode: 'bank', amount: 60, reference: 'supplier advance', invoiceLinked: false,
      );
    });

    expect(await linesFor('receipt', 41), {
      '1010': {'debit': 75, 'credit': 0},
      '1100': {'debit': 0, 'credit': 75},
    });
    expect(await linesFor('receipt', 42), {
      '1000': {'debit': 25, 'credit': 0},
      '2200': {'debit': 0, 'credit': 25},
    });
    expect(await linesFor('payment', 43), {
      '1010': {'debit': 0, 'credit': 60},
      '1400': {'debit': 60, 'credit': 0},
    });
  });

  test('rejects unsupported purchase ITC treatment without partial journal writes', () async {
    await expectLater(
      db.transaction((txn) => AccountingService.postPurchaseInvoice(
        txn,
        invoiceId: 51,
        invoiceNumber: 'P-51',
        date: '2026-11-05',
        subtotal: 100,
        tax: 18,
        total: 118,
        itcTreatment: 'unknown',
      )),
      throwsA(isA<StateError>()),
    );
    expect(await db.query('journal_entries'), isEmpty);
    expect(await db.query('journal_lines'), isEmpty);
  });
}
