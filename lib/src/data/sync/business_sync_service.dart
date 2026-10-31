import 'package:supabase_flutter/supabase_flutter.dart';

import '../local/app_database.dart';

class SyncPushResult {
  const SyncPushResult({
    required this.uploaded,
    required this.failed,
  });

  final int uploaded;
  final int failed;
}

/// Uploads locally queued party/product changes to the current business.
class BusinessSyncService {
  BusinessSyncService({
    required this.businessId,
    SupabaseClient? client,
  }) : _client = client ?? Supabase.instance.client;

  final String businessId;
  final SupabaseClient _client;

  Future<SyncPushResult> pushPending({int batchSize = 100}) async {
    final database = AppDatabase.instance;
    final pending = await database.getPendingSyncOperations(limit: batchSize);
    var uploaded = 0;
    var failed = 0;

    for (final operation in pending) {
      final queueId = operation['id'] as int;
      try {
        final entityType = operation['table_name'] as String;
        if (entityType != 'parties' && entityType != 'products') {
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

        await _client.from('business_records').upsert({
          'business_id': businessId,
          'entity_type': entityType,
          'record_id': recordId,
          'payload': payload,
          'is_deleted': operationType == 'delete',
          'updated_by': _client.auth.currentUser?.id,
        }, onConflict: 'business_id,entity_type,record_id');

        await database.markSyncOperationCompleted(queueId);
        uploaded++;
      } catch (error) {
        await database.markSyncOperationFailed(queueId, error);
        failed++;
      }
    }

    return SyncPushResult(uploaded: uploaded, failed: failed);
  }
}
