import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:srk_business_manager/src/data/local/app_database.dart';

void main() {
  late Directory temporaryDirectory;
  late AppDatabase deviceA;
  late AppDatabase deviceB;

  const partySyncId = 'party-customer-001';
  const paymentSyncId = 'payment-advance-001';
  const invoiceSyncId = 'invoice-sale-001';
  const allocationSyncId = 'allocation-001';
  const transactionDate = '2026-11-04';

  Future<void> seedDevice(AppDatabase database) async {
    final db = await database.database;
    final partyId = await db.insert('parties', {
      'sync_id': partySyncId,
      'name': 'Test Customer',
      'party_type': 'customer',
      'opening_balance': 0,
      'balance_type': 'receivable',
    });
    await db.insert('invoices', {
      'sync_id': invoiceSyncId,
      'invoice_number': 'SYNC-INV-001',
      'invoice_type': 'sale',
      'party_id': partyId,
      'invoice_date': transactionDate,
      'subtotal': 1000,
      'grand_total': 1000,
      'amount_paid': 0,
      'status': 'unpaid',
    });
    await db.insert('payments', {
      'sync_id': paymentSyncId,
      'party_id': partyId,
      'payment_type': 'receipt',
      'payment_date': transactionDate,
      'amount': 600,
      'mode': 'cash',
    });
  }

  Future<void> applyAllocation(AppDatabase database) {
    return database.applyRemoteSyncRecord(
      tableName: 'payment_allocations',
      recordId: allocationSyncId,
      payload: {
        'sync_id': allocationSyncId,
        'payment_sync_id': paymentSyncId,
        'invoice_sync_id': invoiceSyncId,
        'amount': 400,
        'allocation_date': transactionDate,
      },
      isDeleted: false,
    );
  }

  Future<Map<String, Object?>> allocationSnapshot(AppDatabase database) async {
    final db = await database.database;
    final allocationRows = await db.query(
      'payment_allocations',
      columns: ['sync_id', 'amount'],
      where: 'sync_id = ?',
      whereArgs: [allocationSyncId],
    );
    final invoiceRows = await db.query(
      'invoices',
      columns: ['amount_paid', 'status'],
      where: 'sync_id = ?',
      whereArgs: [invoiceSyncId],
    );
    final paymentRows = await db.query(
      'payments',
      columns: ['amount'],
      where: 'sync_id = ?',
      whereArgs: [paymentSyncId],
    );
    return {
      'allocation_count': allocationRows.length,
      'allocation_amount': allocationRows.isEmpty ? 0 : allocationRows.single['amount'],
      'invoice_paid': invoiceRows.single['amount_paid'],
      'invoice_status': invoiceRows.single['status'],
      'payment_amount': paymentRows.single['amount'],
    };
  }

  setUp(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    temporaryDirectory = await Directory.systemTemp.createTemp('srk-payment-sync-');
    deviceA = AppDatabase.forTesting(
      databasePath: '${temporaryDirectory.path}/device-a.db',
    );
    deviceB = AppDatabase.forTesting(
      databasePath: '${temporaryDirectory.path}/device-b.db',
    );
    await deviceA.database;
    await deviceB.database;
    await seedDevice(deviceA);
    await seedDevice(deviceB);
  });

  tearDown(() async {
    await deviceA.close();
    await deviceB.close();
    if (await temporaryDirectory.exists()) {
      await temporaryDirectory.delete(recursive: true);
    }
  });

  test('two devices apply the same advance allocation once and converge', () async {
    await applyAllocation(deviceA);
    await applyAllocation(deviceB);

    expect(await allocationSnapshot(deviceA), {
      'allocation_count': 1,
      'allocation_amount': 400.0,
      'invoice_paid': 400.0,
      'invoice_status': 'partial',
      'payment_amount': 600.0,
    });
    expect(await allocationSnapshot(deviceB), await allocationSnapshot(deviceA));

    await applyAllocation(deviceA);
    await applyAllocation(deviceB);
    expect(await allocationSnapshot(deviceA), await allocationSnapshot(deviceB));
    expect((await allocationSnapshot(deviceA))['allocation_count'], 1);
    expect((await allocationSnapshot(deviceA))['invoice_paid'], 400.0);
  });

  test('allocation for a different party is rejected without partial writes', () async {
    final db = await deviceA.database;
    final otherPartyId = await db.insert('parties', {
      'sync_id': 'party-customer-002',
      'name': 'Different Customer',
      'party_type': 'customer',
    });
    await db.update(
      'invoices',
      {'party_id': otherPartyId},
      where: 'sync_id = ?',
      whereArgs: [invoiceSyncId],
    );

    await expectLater(
      applyAllocation(deviceA),
      throwsA(isA<FormatException>()),
    );

    final snapshot = await allocationSnapshot(deviceA);
    expect(snapshot['allocation_count'], 0);
    expect(snapshot['invoice_paid'], 0.0);
  });
}
