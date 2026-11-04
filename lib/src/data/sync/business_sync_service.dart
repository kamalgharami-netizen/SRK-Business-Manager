import 'package:supabase_flutter/supabase_flutter.dart';

import '../local/app_database.dart';
import 'business_sync_entity_policy.dart';
import 'business_sync_cursor.dart';

class BusinessSyncResult {
  const BusinessSyncResult({
    required this.uploaded,
    required this.uploadFailures,
    required this.downloaded,
    required this.downloadFailures,
  });

  final int uploaded;
  final int uploadFailures;
  final int downloaded;
  final int downloadFailures;
}

/// Synchronises supported offline entities using optimistic cloud revisions.
class BusinessSyncService {
  BusinessSyncService({
    required this.businessId,
    SupabaseClient? client,
  }) : _client = client ?? Supabase.instance.client;

  final String businessId;
  final SupabaseClient _client;

  Future<BusinessSyncResult> syncNow({
    int batchSize = 500,
  }) async {
    if (batchSize < 1 || batchSize > 500) {
      throw RangeError.range(batchSize, 1, 500, 'batchSize');
    }

    // Drain successive ready batches so a large offline queue is not silently
    // limited to the first 100 records. Failed records receive a retry delay
    // and are therefore not selected repeatedly in this same sync run.
    var uploaded = 0;
    var uploadFailures = 0;
    const maxUploadBatches = 20; // Bound one sync run to at most 10,000 attempts.
    for (var batch = 0; batch < maxUploadBatches; batch++) {
      final result = await _pushPending(batchSize: batchSize);
      uploaded += result.$1;
      uploadFailures += result.$2;
      if (result.$1 + result.$2 < batchSize) break;
    }

    final download = await _pullChanges(pageSize: batchSize);
    return BusinessSyncResult(
      uploaded: uploaded,
      uploadFailures: uploadFailures,
      downloaded: download.$1,
      downloadFailures: download.$2,
    );
  }

  /// Resolves one optimistic-lock conflict only after an explicit user choice.
  /// The cloud revision is re-read immediately before either action.
  Future<void> resolveConflict({
    required int queueId,
    required String resolution,
  }) async {
    if (resolution != 'keep_local' && resolution != 'use_cloud') {
      throw ArgumentError.value(resolution, 'resolution');
    }

    final database = AppDatabase.instance;
    final queued = (await database.getPendingSyncOperations(limit: 1000, includeDelayed: true))
        .where((item) => item['id'] == queueId)
        .toList(growable: false);
    if (queued.isEmpty) {
      throw StateError('This pending operation no longer exists.');
    }

    final operation = queued.first;
    final entityType = operation['table_name'] as String;
    final recordId = operation['record_id'] as String;
    final lastError = operation['last_error']?.toString() ?? '';
    if (!lastError.contains('SYNC_CONFLICT')) {
      throw StateError('This operation is not marked as a cloud conflict.');
    }

    final remoteRows = await _client
        .from('business_records')
        .select('payload,is_deleted,updated_at')
        .eq('business_id', businessId)
        .eq('entity_type', entityType)
        .eq('record_id', recordId)
        .limit(1);
    if (remoteRows.isEmpty) {
      throw StateError(
        'The cloud record no longer exists. The local operation was retained; '
        'automatic resolution is not safe.',
      );
    }

    final remote = Map<String, dynamic>.from(remoteRows.first as Map);
    final remoteRevision = remote['updated_at'] as String;
    if (resolution == 'use_cloud') {
      final payload = Map<String, dynamic>.from(remote['payload'] as Map);
      await database.applyRemoteSyncRecord(
        tableName: entityType,
        recordId: recordId,
        payload: payload,
        isDeleted: remote['is_deleted'] as bool? ?? false,
      );
      await database.saveSyncRevision(
        entityType: entityType,
        recordId: recordId,
        remoteUpdatedAt: remoteRevision,
      );
      await database.markSyncOperationCompleted(queueId);
    } else {
      // Keep Local: use the freshly-read cloud revision as the compare-and-set
      // base, then retry the queued local write. If the cloud changes again,
      // optimistic locking rejects it and the queue remains intact.
      await database.saveSyncRevision(
        entityType: entityType,
        recordId: recordId,
        remoteUpdatedAt: remoteRevision,
      );
      await database.resetSyncOperationRetry(queueId);
      await _pushPending(batchSize: 1000);
      final stillPending = (await database.getPendingSyncOperations(limit: 1000, includeDelayed: true))
          .any((item) => item['id'] == queueId);
      if (stillPending) {
        throw StateError(
          'The cloud changed again or the upload failed. The local operation remains queued.',
        );
      }
    }

    await database.recordConflictResolution(
      queueId: queueId,
      entityType: entityType,
      recordId: recordId,
      resolution: resolution,
      remoteRevision: remoteRevision,
    );
  }

  Future<(int, int)> _pushPending({required int batchSize}) async {
    final database = AppDatabase.instance;
    final pending = await database.getPendingSyncOperations(limit: batchSize);
    var uploaded = 0;
    var failed = 0;

    for (final operation in pending) {
      final queueId = operation['id'] as int;
      try {
        final entityType = operation['table_name'] as String;
        if (!BusinessSyncEntityPolicy.supports(entityType)) {
          throw StateError('Unsupported sync entity: $entityType');
        }

        final recordId = operation['record_id'] as String;
        final payload = Map<String, dynamic>.from(
          operation['payload'] as Map,
        );
        if (payload['sync_id'] != recordId) {
          throw StateError('Queued record identifier does not match its payload.');
        }

        final operationType = operation['operation'] as String;
        if (!{'insert', 'update', 'delete'}.contains(operationType)) {
          throw StateError('Unsupported queued operation: $operationType');
        }

        final values = {
          'business_id': businessId,
          'entity_type': entityType,
          'record_id': recordId,
          'payload': payload,
          'is_deleted': operationType == 'delete',
          'updated_by': _client.auth.currentUser?.id,
        };
        var expectedRevision = await database.getSyncRevision(entityType: entityType, recordId: recordId);
        if (expectedRevision == null) {
          // Upgrade path: discover an existing cloud revision before the first
          // version-aware write, avoiding a duplicate insert on older installs.
          final existing = await _client.from('business_records')
              .select('updated_at')
              .eq('business_id', businessId)
              .eq('entity_type', entityType)
              .eq('record_id', recordId)
              .limit(1);
          if (existing.isNotEmpty) {
            expectedRevision = existing.first['updated_at'] as String;
          }
        }
        String confirmedRevision;
        if (expectedRevision == null) {
          final inserted = await _client.from('business_records').insert(values).select('updated_at').single();
          confirmedRevision = inserted['updated_at'] as String;
        } else {
          final updated = await _client.from('business_records').update(values)
              .eq('business_id', businessId)
              .eq('entity_type', entityType)
              .eq('record_id', recordId)
              .eq('updated_at', expectedRevision)
              .select('updated_at');
          if (updated.isEmpty) {
            throw StateError('SYNC_CONFLICT: Record changed on another device. Local edit remains queued and was not uploaded.');
          }
          confirmedRevision = updated.first['updated_at'] as String;
        }
        await database.saveSyncRevision(entityType: entityType, recordId: recordId, remoteUpdatedAt: confirmedRevision);
        await database.markSyncOperationCompleted(queueId);
        uploaded++;
      } catch (error) {
        await database.markSyncOperationFailed(queueId, error);
        failed++;
      }
    }

    return (uploaded, failed);
  }

  Future<(int, int)> _pullChanges({required int pageSize}) async {
    if (pageSize < 1 || pageSize > 500) {
      throw RangeError.range(pageSize, 1, 500, 'pageSize');
    }

    final database = AppDatabase.instance;
    var downloaded = 0;
    var failed = 0;

    for (final entityType in BusinessSyncEntityPolicy.pullOrder) {
      // Freeze the timestamp boundary for this pass. Rows written after this
      // query are picked up by the next pass rather than extending this scan.
      final newestRows = await _client
          .from('business_records')
          .select('updated_at')
          .eq('business_id', businessId)
          .eq('entity_type', entityType)
          .order('updated_at', ascending: false)
          .order('record_id', ascending: false)
          .limit(1);
      if (newestRows.isEmpty) continue;
      final upperUpdatedAt = newestRows.first['updated_at'] as String;

      final savedCursor = await database.getSyncPullCursor(entityType);
      // Re-scan the last timestamp inclusively on each sync. This deliberately
      // catches records inserted later with the same timestamp but a lower
      // record_id; revision checks make the overlap idempotent.
      String? pageUpdatedAt;
      String? pageRecordId;
      var firstPage = true;
      var stopEntity = false;

      while (!stopEntity) {
        dynamic request = _client
            .from('business_records')
            .select('entity_type,record_id,payload,is_deleted,updated_at')
            .eq('business_id', businessId)
            .eq('entity_type', entityType)
            .lte('updated_at', upperUpdatedAt)
            .order('updated_at')
            .order('record_id')
            .limit(pageSize);

        if (firstPage && savedCursor != null) {
          request = request.gte('updated_at', savedCursor['updated_at']!);
        } else if (!firstPage && pageUpdatedAt != null && pageRecordId != null) {
          request = request.or(
            BusinessSyncCursor.nextPageFilter(
              updatedAt: pageUpdatedAt,
              recordId: pageRecordId,
            ),
          );
        }

        final rows = await request;
        if (rows.isEmpty) break;

        for (final rawRow in rows) {
          final row = Map<String, dynamic>.from(rawRow as Map);
          final recordId = row['record_id'] as String;
          final remoteRevision = row['updated_at'] as String;
          try {
            final hasLocalPendingChange =
                await database.hasPendingSyncOperation(
              tableName: entityType,
              recordId: recordId,
            );
            if (hasLocalPendingChange) {
              // Do not move the checkpoint past a cloud conflict or a queued
              // local edit. The next sync retries this exact boundary.
              failed++;
              stopEntity = true;
              break;
            }

            final localRevision = await database.getSyncRevision(
              entityType: entityType,
              recordId: recordId,
            );
            if (localRevision != remoteRevision) {
              final payload = Map<String, dynamic>.from(
                row['payload'] as Map,
              );
              await database.applyRemoteSyncRecord(
                tableName: entityType,
                recordId: recordId,
                payload: payload,
                isDeleted: row['is_deleted'] as bool? ?? false,
              );
              await database.saveSyncRevision(
                entityType: entityType,
                recordId: recordId,
                remoteUpdatedAt: remoteRevision,
              );
              downloaded++;
            }

            // Checkpoint only after apply + revision persistence, or after a
            // confirmed unchanged revision. A crash before this point safely
            // replays the row; a failed apply never advances the cursor.
            await database.saveSyncPullCursor(
              entityType: entityType,
              updatedAt: remoteRevision,
              recordId: recordId,
            );
            pageUpdatedAt = remoteRevision;
            pageRecordId = recordId;
          } catch (_) {
            failed++;
            stopEntity = true;
            break;
          }
        }

        if (stopEntity || rows.length < pageSize) break;
        firstPage = false;
      }
    }

    return (downloaded, failed);
  }
}
