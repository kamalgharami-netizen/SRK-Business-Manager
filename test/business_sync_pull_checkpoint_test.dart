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
  test('processes a large page without skipping or reordering checkpoints', () async {
    const count = 1200;
    final largeRows = List.generate(
      count,
      (index) => {
        'record_id': 'record-${index.toString().padLeft(4, '0')}',
        'updated_at': revision,
        'payload': {'value': index},
      },
    );
    final saved = <String>[];
    final result = await BusinessSyncPullCheckpoint.processPage(
      entityType: 'parties',
      rows: largeRows,
      hasPendingLocalChange: (_) async => false,
      getLocalRevision: (_) async => null,
      applyRemote: (_) async {},
      saveRevision: (_, __) async {},
      saveCursor: (_, id) async => saved.add(id),
    );
    expect(result.applied, count);
    expect(result.failures, 0);
    expect(result.stopped, isFalse);
    expect(saved, hasLength(count));
    expect(saved.first, 'record-0000');
    expect(saved.last, 'record-1199');
    expect(result.lastRecordId, 'record-1199');
  });

  test('resumes from the last committed cursor after a later row fails', () async {
    final firstRunCursors = <String>[];
    final firstRun = await BusinessSyncPullCheckpoint.processPage(
      entityType: 'parties',
      rows: rows(),
      hasPendingLocalChange: (_) async => false,
      getLocalRevision: (_) async => null,
      applyRemote: (row) async {
        if (row['record_id'] == 'c') throw StateError('temporary failure');
      },
      saveRevision: (_, __) async {},
      saveCursor: (_, id) async => firstRunCursors.add(id),
    );
    expect(firstRun.stopped, isTrue);
    expect(firstRun.lastRecordId, 'b');
    expect(firstRunCursors, ['a', 'b']);

    final remainingRows = rows().where(
      (row) => (row['record_id'] as String).compareTo(firstRun.lastRecordId!) > 0,
    ).toList();
    final secondRunCursors = <String>[];
    final secondRun = await BusinessSyncPullCheckpoint.processPage(
      entityType: 'parties',
      rows: remainingRows,
      hasPendingLocalChange: (_) async => false,
      getLocalRevision: (_) async => null,
      applyRemote: (_) async {},
      saveRevision: (_, __) async {},
      saveCursor: (_, id) async => secondRunCursors.add(id),
    );
    expect(secondRun.stopped, isFalse);
    expect(secondRunCursors, ['c']);
    expect(secondRun.lastRecordId, 'c');
  });

}
