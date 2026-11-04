/// Result of applying one ordered page of cloud records locally.
class BusinessSyncPullPageResult {
  const BusinessSyncPullPageResult({
    required this.applied,
    required this.failures,
    required this.stopped,
    required this.lastUpdatedAt,
    required this.lastRecordId,
  });
  final int applied;
  final int failures;
  final bool stopped;
  final String? lastUpdatedAt;
  final String? lastRecordId;
}

/// Applies rows in order and commits each cursor only after the row is safe.
class BusinessSyncPullCheckpoint {
  const BusinessSyncPullCheckpoint._();

  static Future<BusinessSyncPullPageResult> processPage({
    required String entityType,
    required List<Map<String, dynamic>> rows,
    required Future<bool> Function(String recordId) hasPendingLocalChange,
    required Future<String?> Function(String recordId) getLocalRevision,
    required Future<void> Function(Map<String, dynamic> row) applyRemote,
    required Future<void> Function(String recordId, String revision) saveRevision,
    required Future<void> Function(String updatedAt, String recordId) saveCursor,
  }) async {
    var applied = 0;
    var failures = 0;
    String? lastUpdatedAt;
    String? lastRecordId;
    for (final row in rows) {
      final recordId = row['record_id'] as String;
      final revision = row['updated_at'] as String;
      try {
        if (await hasPendingLocalChange(recordId)) {
          failures++;
          return BusinessSyncPullPageResult(
            applied: applied, failures: failures, stopped: true,
            lastUpdatedAt: lastUpdatedAt, lastRecordId: lastRecordId,
          );
        }
        final localRevision = await getLocalRevision(recordId);
        if (localRevision != revision) {
          await applyRemote(row);
          await saveRevision(recordId, revision);
          applied++;
        }
        await saveCursor(revision, recordId);
        lastUpdatedAt = revision;
        lastRecordId = recordId;
      } catch (_) {
        failures++;
        return BusinessSyncPullPageResult(
          applied: applied, failures: failures, stopped: true,
          lastUpdatedAt: lastUpdatedAt, lastRecordId: lastRecordId,
        );
      }
    }
    return BusinessSyncPullPageResult(
      applied: applied, failures: failures, stopped: false,
      lastUpdatedAt: lastUpdatedAt, lastRecordId: lastRecordId,
    );
  }
}
