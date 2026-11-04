import 'package:flutter_test/flutter_test.dart';
import 'package:srk_business_manager/src/data/sync/business_sync_pull_checkpoint.dart';

void main() {
  const revision = '2026-11-04T10:15:30.123456+00:00';
  List<Map<String, dynamic>> rows() => [
    {'record_id': 'a', 'updated_at': revision, 'payload': {'value': 1}},
    {'record_id': 'b', 'updated_at': revision, 'payload': {'value': 2}},
    {'record_id': 'c', 'updated_at': revision, 'payload': {'value': 3}},
  ];

  test('checkpoints each row only after apply and revision persistence', () async {
    final events = <String>[];
    final result = await BusinessSyncPullCheckpoint.processPage(
      entityType: 'parties', rows: rows(),
      hasPendingLocalChange: (_) async => false,
      getLocalRevision: (_) async => null,
      applyRemote: (row) async => events.add('apply:${row['record_id']}'),
      saveRevision: (id, _) async => events.add('revision:$id'),
      saveCursor: (_, id) async => events.add('cursor:$id'),
    );
    expect(result.applied, 3);
    expect(result.failures, 0);
    expect(result.stopped, isFalse);
    expect(events, [
      'apply:a', 'revision:a', 'cursor:a',
      'apply:b', 'revision:b', 'cursor:b',
      'apply:c', 'revision:c', 'cursor:c',
    ]);
  });

  test('pending local change stops before that row and preserves prior cursor', () async {
    final cursors = <String>[];
    final result = await BusinessSyncPullCheckpoint.processPage(
      entityType: 'parties', rows: rows(),
      hasPendingLocalChange: (id) async => id == 'b',
      getLocalRevision: (_) async => null,
      applyRemote: (_) async {},
      saveRevision: (_, __) async {},
      saveCursor: (_, id) async => cursors.add(id),
    );
    expect(result.stopped, isTrue);
    expect(result.failures, 1);
    expect(cursors, ['a']);
    expect(result.lastRecordId, 'a');
  });

  test('failed apply never advances cursor beyond previous successful row', () async {
    final cursors = <String>[];
    final result = await BusinessSyncPullCheckpoint.processPage(
      entityType: 'parties', rows: rows(),
      hasPendingLocalChange: (_) async => false,
      getLocalRevision: (_) async => null,
      applyRemote: (row) async {
        if (row['record_id'] == 'b') throw StateError('simulated apply failure');
      },
      saveRevision: (_, __) async {},
      saveCursor: (_, id) async => cursors.add(id),
    );
    expect(result.stopped, isTrue);
    expect(result.applied, 1);
    expect(result.failures, 1);
    expect(cursors, ['a']);
    expect(result.lastRecordId, 'a');
  });

  test('revision-save failure prevents cursor advancement', () async {
    final cursors = <String>[];
    final result = await BusinessSyncPullCheckpoint.processPage(
      entityType: 'parties', rows: rows().take(1).toList(),
      hasPendingLocalChange: (_) async => false,
      getLocalRevision: (_) async => null,
      applyRemote: (_) async {},
      saveRevision: (_, __) async => throw StateError('disk failure'),
      saveCursor: (_, id) async => cursors.add(id),
    );
    expect(result.stopped, isTrue);
    expect(cursors, isEmpty);
    expect(result.lastRecordId, isNull);
  });

  test('unchanged cloud revision advances cursor without reapplying', () async {
    final cursors = <String>[];
    var applyCount = 0;
    final result = await BusinessSyncPullCheckpoint.processPage(
      entityType: 'parties', rows: rows().take(1).toList(),
      hasPendingLocalChange: (_) async => false,
      getLocalRevision: (_) async => revision,
      applyRemote: (_) async => applyCount++,
      saveRevision: (_, __) async {},
      saveCursor: (_, id) async => cursors.add(id),
    );
    expect(result.applied, 0);
    expect(applyCount, 0);
    expect(cursors, ['a']);
  });
}
