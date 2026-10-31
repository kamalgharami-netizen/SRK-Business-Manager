import 'package:supabase_flutter/supabase_flutter.dart';

import '../local/app_database.dart';

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
    int batchSize = 100,
  }) async {
    final upload = await _pushPending(batchSize: batchSize);
    final download = await _pullChanges(pageSize: batchSize);
    return BusinessSyncResult(
      uploaded: upload.$1,
      uploadFailures: upload.$2,
      downloaded: download.$1,
      downloadFailures: download.$2,
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
        if (entityType != 'parties' && entityType != 'products' && entityType != 'expenses') {
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
        final expectedRevision = await database.getSyncRevision(entityType: entityType, recordId: recordId);
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

    for (final entityType in const ['parties', 'products', 'expenses']) {
      var offset = 0;
      while (true) {
        final rows = await _client
            .from('business_records')
            .select('entity_type,record_id,payload,is_deleted,updated_at')
            .eq('business_id', businessId)
            .eq('entity_type', entityType)
            .order('record_id')
            .range(offset, offset + pageSize - 1);

        for (final rawRow in rows) {
          final row = Map<String, dynamic>.from(rawRow as Map);
          final recordId = row['record_id'] as String;
          try {
            final hasLocalPendingChange =
                await database.hasPendingSyncOperation(
              tableName: entityType,
              recordId: recordId,
            );
            if (hasLocalPendingChange) continue;

            final payload = Map<String, dynamic>.from(
              row['payload'] as Map,
            );
            await database.applyRemoteSyncRecord(
              tableName: entityType,
              recordId: recordId,
              payload: payload,
              isDeleted: row['is_deleted'] as bool? ?? false,
            );
            await database.saveSyncRevision(entityType: entityType, recordId: recordId, remoteUpdatedAt: row['updated_at'] as String);
            downloaded++;
          } catch (_) {
            failed++;
          }
        }

        offset += rows.length;
        if (rows.length < pageSize) break;
      }
    }

    return (downloaded, failed);
  }
}
