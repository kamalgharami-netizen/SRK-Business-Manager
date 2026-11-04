import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:srk_business_manager/src/data/local/app_database.dart';
import 'package:srk_business_manager/src/data/sync/business_sync_pull_checkpoint.dart';

void main() {
  late Directory temporaryDirectory;
  late AppDatabase deviceA;
  late AppDatabase deviceB;

  const entity = 'warehouses';
  const id = 'warehouse-shared-001';
  const firstRevision = '2026-11-04T11:00:00.000000+00:00';
  const secondRevision = '2026-11-04T11:05:00.000000+00:00';

  Map<String, dynamic> cloudRow(String revision, {String name = 'Main Warehouse'}) => {
    'entity_type': entity,
    'record_id': id,
    'updated_at': revision,
    'is_deleted': false,
    'payload': {
      'sync_id': id,
      'name': name,
      'code': 'MAIN',
      'address': 'Kolkata',
      'phone': null,
      'is_active': 1,
      'created_at': firstRevision,
      'updated_at': revision,
    },
  };

  Future<BusinessSyncPullPageResult> pull(
    AppDatabase device,
    Map<String, dynamic> row,
  ) {
    return BusinessSyncPullCheckpoint.processPage(
      entityType: entity,
      rows: [row],
      hasPendingLocalChange: (recordId) => device.hasPendingSyncOperation(
        tableName: entity,
        recordId: recordId,
      ),
      getLocalRevision: (recordId) => device.getSyncRevision(
        entityType: entity,
        recordId: recordId,
      ),
      applyRemote: (record) => device.applyRemoteSyncRecord(
        tableName: entity,
        recordId: record['record_id'] as String,
        payload: Map<String, dynamic>.from(record['payload'] as Map),
        isDeleted: record['is_deleted'] as bool? ?? false,
      ),
      saveRevision: (recordId, revision) => device.saveSyncRevision(
        entityType: entity,
        recordId: recordId,
        remoteUpdatedAt: revision,
      ),
      saveCursor: (updatedAt, recordId) => device.saveSyncPullCursor(
        entityType: entity,
        updatedAt: updatedAt,
        recordId: recordId,
      ),
    );
  }

  Future<String?> warehouseName(AppDatabase device) async {
    final db = await device.database;
    final rows = await db.query(
      'warehouses',
      columns: ['name'],
      where: 'sync_id = ?',
      whereArgs: [id],
      limit: 1,
    );
    return rows.isEmpty ? null : rows.single['name'] as String;
  }

  setUp(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    temporaryDirectory = await Directory.systemTemp.createTemp('srk-two-device-sync-');
    deviceA = AppDatabase.forTesting(
      databasePath: '${temporaryDirectory.path}/device-a.db',
    );
    deviceB = AppDatabase.forTesting(
      databasePath: '${temporaryDirectory.path}/device-b.db',
    );
    await deviceA.database;
    await deviceB.database;
  });

  tearDown(() async {
    await deviceA.close();
    await deviceB.close();
    if (await temporaryDirectory.exists()) {
      await temporaryDirectory.delete(recursive: true);
    }
  });

  test('two independent device databases reconcile cloud revisions idempotently', () async {
    // Device A publishes a new cloud revision; both devices independently pull it.
    final first = cloudRow(firstRevision);
    final aFirstPull = await pull(deviceA, first);
    final bFirstPull = await pull(deviceB, first);
    expect(aFirstPull.applied, 1);
    expect(bFirstPull.applied, 1);
    expect(await warehouseName(deviceA), 'Main Warehouse');
    expect(await warehouseName(deviceB), 'Main Warehouse');

    // Device B's next cloud upload is represented by a newer server revision.
    // Device A pulls that revision and both local databases converge.
    final editedOnB = cloudRow(secondRevision, name: 'Updated Warehouse');
    final aSecondPull = await pull(deviceA, editedOnB);
    expect(aSecondPull.applied, 1);
    expect(await warehouseName(deviceA), 'Updated Warehouse');
    expect(await deviceA.getSyncRevision(entityType: entity, recordId: id), secondRevision);

    // Device B already has that exact revision: replay must not apply twice.
    final bReplay = await pull(deviceB, editedOnB);
    expect(bReplay.applied, 0);
    expect(bReplay.failures, 0);
    expect(await warehouseName(deviceB), 'Updated Warehouse');

    // A repeated replay on A also leaves the record and revision unchanged.
    final aReplay = await pull(deviceA, editedOnB);
    expect(aReplay.applied, 0);
    expect(await warehouseName(deviceA), 'Updated Warehouse');
  });

  test('pending local edit blocks cloud overwrite and keeps its checkpoint safe', () async {
    final initial = cloudRow(firstRevision);
    await pull(deviceA, initial);
    await deviceA.enqueueSyncOperation(
      tableName: entity,
      recordId: id,
      operation: 'update',
      payload: {
        ...Map<String, dynamic>.from(initial['payload'] as Map),
        'name': 'Local unsynced edit',
      },
    );

    final newerCloud = cloudRow(secondRevision, name: 'Other device edit');
    final result = await pull(deviceA, newerCloud);

    expect(result.applied, 0);
    expect(result.failures, 1);
    expect(result.stopped, isTrue);
    expect(await warehouseName(deviceA), 'Main Warehouse');
    expect(await deviceA.getSyncRevision(entityType: entity, recordId: id), firstRevision);
    expect(await deviceA.hasPendingSyncOperation(tableName: entity, recordId: id), isTrue);
  });
}
