import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:srk_business_manager/src/data/local/app_database.dart';
import 'package:srk_business_manager/src/data/sync/business_sync_pull_checkpoint.dart';

void main() {
  late Directory temporaryDirectory;
  late String databasePath;

  setUp(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    temporaryDirectory = await Directory.systemTemp.createTemp(
      'srk-sync-restart-',
    );
    databasePath = '${temporaryDirectory.path}/sync_test.db';
  });

  tearDown(() async {
    if (await temporaryDirectory.exists()) {
      await temporaryDirectory.delete(recursive: true);
    }
  });

  const revision = '2026-11-04T10:15:30.123456+00:00';
  const entityType = 'warehouses';

  Map<String, dynamic> warehouseRow(
    String id, {
    bool valid = true,
  }) {
    return {
      'entity_type': entityType,
      'record_id': id,
      'updated_at': revision,
      'is_deleted': false,
      'payload': {
        'sync_id': id,
        'name': 'Warehouse $id',
        'code': 'WH-$id',
        'address': null,
        'phone': null,
        'is_active': 1,
        'created_at': revision,
        'updated_at': valid ? revision : '',
      },
    };
  }

  Future<BusinessSyncPullPageResult> process(
    AppDatabase database,
    List<Map<String, dynamic>> rows,
  ) {
    return BusinessSyncPullCheckpoint.processPage(
      entityType: entityType,
      rows: rows,
      hasPendingLocalChange: (recordId) => database.hasPendingSyncOperation(
        tableName: entityType,
        recordId: recordId,
      ),
      getLocalRevision: (recordId) => database.getSyncRevision(
        entityType: entityType,
        recordId: recordId,
      ),
      applyRemote: (row) => database.applyRemoteSyncRecord(
        tableName: entityType,
        recordId: row['record_id'] as String,
        payload: Map<String, dynamic>.from(row['payload'] as Map),
        isDeleted: row['is_deleted'] as bool? ?? false,
      ),
      saveRevision: (recordId, value) => database.saveSyncRevision(
        entityType: entityType,
        recordId: recordId,
        remoteUpdatedAt: value,
      ),
      saveCursor: (updatedAt, recordId) => database.saveSyncPullCursor(
        entityType: entityType,
        updatedAt: updatedAt,
        recordId: recordId,
      ),
    );
  }

  test(
    'persists the last safe SQLite checkpoint and resumes after close/reopen',
    () async {
      final firstDatabase = AppDatabase.forTesting(
        databasePath: databasePath,
      );
      await firstDatabase.database;

      final firstRun = await process(firstDatabase, [
        warehouseRow('a'),
        warehouseRow('b'),
        warehouseRow('c', valid: false),
      ]);

      expect(firstRun.applied, 2);
      expect(firstRun.failures, 1);
      expect(firstRun.stopped, isTrue);
      expect(firstRun.lastRecordId, 'b');
      expect(
        await firstDatabase.getSyncPullCursor(entityType),
        {'updated_at': revision, 'record_id': 'b'},
      );
      expect(
        await firstDatabase.getSyncRevision(
          entityType: entityType,
          recordId: 'b',
        ),
        revision,
      );
      expect(
        await firstDatabase.getSyncRevision(
          entityType: entityType,
          recordId: 'c',
        ),
        isNull,
      );

      // Simulate application shutdown and a fresh database-service instance.
      await firstDatabase.close();
      final reopenedDatabase = AppDatabase.forTesting(
        databasePath: databasePath,
      );

      expect(
        await reopenedDatabase.getSyncPullCursor(entityType),
        {'updated_at': revision, 'record_id': 'b'},
      );
      expect(
        await reopenedDatabase.getSyncRevision(
          entityType: entityType,
          recordId: 'a',
        ),
        revision,
      );
      expect(
        await reopenedDatabase.getSyncRevision(
          entityType: entityType,
          recordId: 'b',
        ),
        revision,
      );

      final resumedRows = [
        warehouseRow('a'),
        warehouseRow('b'),
        warehouseRow('c'),
      ].where((row) {
        final id = row['record_id'] as String;
        return id.compareTo('b') > 0;
      }).toList();

      final secondRun = await process(reopenedDatabase, resumedRows);
      expect(secondRun.applied, 1);
      expect(secondRun.failures, 0);
      expect(secondRun.stopped, isFalse);
      expect(secondRun.lastRecordId, 'c');
      expect(
        await reopenedDatabase.getSyncPullCursor(entityType),
        {'updated_at': revision, 'record_id': 'c'},
      );
      expect(
        await reopenedDatabase.getSyncRevision(
          entityType: entityType,
          recordId: 'c',
        ),
        revision,
      );

      final db = await reopenedDatabase.database;
      final persistedWarehouses = await db.query(
        'warehouses',
        columns: ['sync_id'],
        orderBy: 'sync_id',
      );
      expect(
        persistedWarehouses.map((row) => row['sync_id']).toList(),
        ['a', 'b', 'c'],
      );

      // Replaying the same cloud row after restart is idempotent.
      final replay = await process(reopenedDatabase, [warehouseRow('c')]);
      expect(replay.applied, 0);
      expect(replay.failures, 0);
      expect(
        await reopenedDatabase.getSyncRevision(
          entityType: entityType,
          recordId: 'c',
        ),
        revision,
      );

      await reopenedDatabase.close();
    },
  );

  test('does not persist a cursor when the SQLite apply transaction fails', () async {
    final database = AppDatabase.forTesting(databasePath: databasePath);
    await database.database;

    final result = await process(database, [
      warehouseRow('bad', valid: false),
    ]);

    expect(result.applied, 0);
    expect(result.failures, 1);
    expect(result.stopped, isTrue);
    expect(await database.getSyncPullCursor(entityType), isNull);
    expect(
      await database.getSyncRevision(
        entityType: entityType,
        recordId: 'bad',
      ),
      isNull,
    );

    await database.close();
  });
}
