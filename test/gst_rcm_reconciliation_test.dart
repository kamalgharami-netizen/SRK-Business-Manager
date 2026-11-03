import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:srk_business_manager/src/data/local/gst_rcm_reconciliation.dart';

Future<Database> _openDb() async {
  sqfliteFfiInit();
  final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
  await db.execute('''CREATE TABLE gst_rcm_liabilities (
    id INTEGER PRIMARY KEY, return_period TEXT NOT NULL,
    document_reference TEXT NOT NULL, igst REAL NOT NULL DEFAULT 0,
    cgst REAL NOT NULL DEFAULT 0, sgst REAL NOT NULL DEFAULT 0,
    cess REAL NOT NULL DEFAULT 0)''');
  await db.execute('''CREATE TABLE gst_rcm_payments (
    id INTEGER PRIMARY KEY, liability_id INTEGER NOT NULL,
    payment_date TEXT NOT NULL, cash_ledger_reference TEXT, challan_reference TEXT, igst REAL NOT NULL DEFAULT 0,
    cgst REAL NOT NULL DEFAULT 0, sgst REAL NOT NULL DEFAULT 0,
    cess REAL NOT NULL DEFAULT 0)''');
  await db.execute('''CREATE TABLE gst_rcm_audit (
    id INTEGER PRIMARY KEY, return_period TEXT NOT NULL)''');
  return db;
}

void main() {
  group('GST RCM reconciliation', () {
    test('reconciles partial and fully paid liabilities by tax head', () async {
      final db = await _openDb();
      addTearDown(db.close);
      await db.insert('gst_rcm_liabilities', {
        'id': 1, 'return_period': '2026-11', 'document_reference': 'RCM-1',
        'igst': 100, 'cgst': 50, 'sgst': 50, 'cess': 0,
      });
      await db.insert('gst_rcm_liabilities', {
        'id': 2, 'return_period': '2026-11', 'document_reference': 'RCM-2',
        'igst': 0, 'cgst': 20, 'sgst': 20, 'cess': 0,
      });
      await db.insert('gst_rcm_payments', {
        'id': 1, 'liability_id': 1, 'payment_date': '2026-11-10', 'cash_ledger_reference': 'CASH-1', 'challan_reference': 'CIN-1',
        'igst': 100, 'cgst': 25, 'sgst': 25, 'cess': 0,
      });
      await db.insert('gst_rcm_payments', {
        'id': 2, 'liability_id': 2, 'payment_date': '2026-11-12', 'cash_ledger_reference': 'CASH-2', 'challan_reference': 'CIN-2',
        'igst': 0, 'cgst': 20, 'sgst': 20, 'cess': 0,
      });
      await db.insert('gst_rcm_audit', {'id': 1, 'return_period': '2026-11'});
      final result = await GstRcmReconciliation.load(db);
      expect(result['liability_count'], 2);
      expect(result['payment_count'], 2);
      expect(result['liability_total'], 240);
      expect(result['paid_total'], 190);
      expect(result['outstanding_total'], 50);
      expect(result['unpaid_count'], 1);
      expect(result['fully_paid_count'], 1);
      expect(result['overpaid_count'], 0);
      expect(result['audit_event_count'], 1);
      expect(result['is_reconciled'], isTrue);
    });

    test('flags overpayment and applies selected return-period range', () async {
      final db = await _openDb();
      addTearDown(db.close);
      await db.insert('gst_rcm_liabilities', {
        'id': 1, 'return_period': '2026-10', 'document_reference': 'OLD',
        'igst': 10, 'cgst': 0, 'sgst': 0, 'cess': 0,
      });
      await db.insert('gst_rcm_payments', {
        'id': 1, 'liability_id': 1, 'payment_date': '2026-10-15', 'cash_ledger_reference': 'CASH-OLD', 'challan_reference': 'CIN-OLD',
        'igst': 12, 'cgst': 0, 'sgst': 0, 'cess': 0,
      });
      await db.insert('gst_rcm_liabilities', {
        'id': 2, 'return_period': '2026-11', 'document_reference': 'CURRENT',
        'igst': 25, 'cgst': 0, 'sgst': 0, 'cess': 0,
      });
      final result = await GstRcmReconciliation.load(
        db, startDate: '2026-11-01', endDate: '2026-11-30',
      );
      expect(result['liability_count'], 1);
      expect(result['liability_total'], 25);
      expect(result['paid_total'], 0);
      expect(result['outstanding_total'], 25);
      expect(result['is_reconciled'], isTrue);
      final all = await GstRcmReconciliation.load(db);
      expect(all['overpaid_count'], 1);
      expect(all['is_reconciled'], isFalse);
    });


    test('flags cash payments missing either supporting reference', () async {
      final db = await _openDb();
      addTearDown(db.close);
      await db.insert('gst_rcm_liabilities', {
        'id': 1, 'return_period': '2026-11', 'document_reference': 'RCM-1',
        'igst': 18, 'cgst': 0, 'sgst': 0, 'cess': 0,
      });
      await db.insert('gst_rcm_payments', {
        'id': 1, 'liability_id': 1, 'payment_date': '2026-11-10',
        'cash_ledger_reference': '', 'challan_reference': 'CIN-1',
        'igst': 18, 'cgst': 0, 'sgst': 0, 'cess': 0,
      });
      final result = await GstRcmReconciliation.load(db);
      expect(result['missing_payment_reference_count'], 1);
      expect(result['is_reconciled'], isFalse);
    });

    test('does not modify liability or payment records', () async {
      final db = await _openDb();
      addTearDown(db.close);
      await db.insert('gst_rcm_liabilities', {
        'id': 1, 'return_period': '2026-11', 'document_reference': 'RCM-1',
        'igst': 18, 'cgst': 0, 'sgst': 0, 'cess': 0,
      });
      final before = await db.query('gst_rcm_liabilities');
      await GstRcmReconciliation.load(db);
      expect(await db.query('gst_rcm_liabilities'), before);
    });
  });
}
