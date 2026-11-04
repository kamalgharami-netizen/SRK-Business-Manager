import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:srk_business_manager/src/data/local/app_database.dart';

void main() {
  late Directory temporaryDirectory;
  late AppDatabase database;

  setUp(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    temporaryDirectory = await Directory.systemTemp.createTemp('srk-sync-retry-');
    database = AppDatabase.forTesting(
      databasePath: '${temporaryDirectory.path}/retry.db',
    );
    await database.database;
  });

  tearDown(() async {
    await database.close();
    if (await temporaryDirectory.exists()) {
      await temporaryDirectory.delete(recursive: true);
    }
  });

  Future<int> enqueue() => database.enqueueSyncOperation(
        tableName: 'parties',
        recordId: 'party-retry-001',
        operation: 'update',
        payload: {'sync_id': 'party-retry-001', 'name': 'Local edit'},
      );

  test('manual retry clears delay metadata but preserves queued payload', () async {
    final queueId = await enqueue();
    await database.markSyncOperationFailed(
      queueId,
      StateError('Temporary network failure'),
    );

    final before = (await database.getPendingSyncOperations(
      limit: 10,
      includeDelayed: true,
    )).single;
    expect(before['retry_count'], 1);
    expect(before['last_error'], contains('Temporary network failure'));
    expect(before['next_retry_at'], isNotNull);

    expect(await database.retrySyncOperationNow(queueId), 1);

    final after = (await database.getPendingSyncOperations(
      limit: 10,
      includeDelayed: true,
    )).single;
    expect(after['retry_count'], 0);
    expect(after['last_error'], isNull);
    expect(after['next_retry_at'], isNull);
    expect(after['payload'], {
      'sync_id': 'party-retry-001',
      'name': 'Local edit',
    });
    expect(await database.getPendingSyncCount(), 1);
  });

  test('manual retry refuses cloud conflicts and leaves the queue unchanged', () async {
    final queueId = await enqueue();
    await database.markSyncOperationFailed(
      queueId,
      StateError('SYNC_CONFLICT: another device changed this record'),
    );

    final before = (await database.getPendingSyncOperations(
      limit: 10,
      includeDelayed: true,
    )).single;

    await expectLater(
      database.retrySyncOperationNow(queueId),
      throwsA(isA<StateError>()),
    );

    final after = (await database.getPendingSyncOperations(
      limit: 10,
      includeDelayed: true,
    )).single;
    expect(after['retry_count'], before['retry_count']);
    expect(after['last_error'], before['last_error']);
    expect(after['next_retry_at'], before['next_retry_at']);
    expect(after['payload'], before['payload']);
  });

  test('manual retry reports an operation that no longer exists', () async {
    expect(await database.retrySyncOperationNow(999999), 0);
    expect(await database.getPendingSyncCount(), 0);
  });
}
