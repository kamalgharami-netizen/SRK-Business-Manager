import 'package:flutter/material.dart';

import '../../data/local/app_database.dart';
import '../../data/sync/business_sync_service.dart';

/// Read-only view of durable local sync work and failures.
class SyncStatusPage extends StatefulWidget {
  const SyncStatusPage({super.key, required this.cloudConfigured});

  final bool cloudConfigured;

  @override
  State<SyncStatusPage> createState() => _SyncStatusPageState();
}

class _SyncStatusPageState extends State<SyncStatusPage> {
  late Future<List<Map<String, dynamic>>> _pendingFuture;
  bool _syncing = false;

  @override
  void initState() {
    super.initState();
    _pendingFuture = _loadPending();
  }

  Future<List<Map<String, dynamic>>> _loadPending() {
    return AppDatabase.instance.getPendingSyncOperations(limit: 1000, includeDelayed: true);
  }

  void _refresh() {
    setState(() => _pendingFuture = _loadPending());
  }

  Future<void> _syncNow() async {
    final businessId = AppDatabase.instance.activeBusinessId;
    if (!widget.cloudConfigured || businessId == null || _syncing) return;

    setState(() => _syncing = true);
    try {
      final result = await BusinessSyncService(businessId: businessId).syncNow();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${result.uploaded} uploaded, ${result.downloaded} downloaded, '
            '${result.uploadFailures + result.downloadFailures} failed.',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Sync failed. Local changes are retained. $error')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _syncing = false;
          _pendingFuture = _loadPending();
        });
      }
    }
  }

  Future<void> _resolveConflict(
    Map<String, dynamic> item,
    String resolution,
  ) async {
    final keepLocal = resolution == 'keep_local';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(keepLocal ? 'Keep this device version?' : 'Use cloud version?'),
        content: Text(
          keepLocal
              ? 'The latest cloud revision will be checked, then this device version will be uploaded over it. If another change occurs meanwhile, the upload will be rejected and kept pending.'
              : 'The cloud version will replace this record on this device. The pending local operation will be cleared only after the local update succeeds.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(keepLocal ? 'Keep Local' : 'Use Cloud'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    final businessId = AppDatabase.instance.activeBusinessId;
    if (!widget.cloudConfigured || businessId == null) return;

    try {
      await BusinessSyncService(businessId: businessId).resolveConflict(
        queueId: item['id'] as int,
        resolution: resolution,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            keepLocal
                ? 'Local version uploaded successfully.'
                : 'Cloud version applied successfully.',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Conflict was not resolved. Local queue retained where applicable. $error')),
      );
    } finally {
      if (mounted) {
        setState(() => _pendingFuture = _loadPending());
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Backup & Sync Status'),
        actions: [
          IconButton(
            tooltip: 'Refresh queue',
            onPressed: _refresh,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: _pendingFuture,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(child: Text('Could not read sync queue: ${snapshot.error}'));
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final operations = snapshot.data!;
          final now = DateTime.now().toUtc();
          final delayed = operations.where((item) {
            final retryAt = DateTime.tryParse(item['next_retry_at']?.toString() ?? '');
            return retryAt != null && retryAt.isAfter(now);
          }).length;
          final ready = operations.length - delayed;
          final conflicts = operations.where((item) =>
            (item['last_error']?.toString() ?? '').contains('SYNC_CONFLICT'),
          ).toList(growable: false);

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Pending local changes', style: Theme.of(context).textTheme.titleLarge),
                      const SizedBox(height: 8),
                      Text('${operations.length} queued operation(s)'),
                      Text('$ready ready to retry • $delayed waiting for retry time'),
                      Text('${conflicts.length} detected cloud conflict(s)'),
                      const SizedBox(height: 12),
                      if (!widget.cloudConfigured)
                        const Text('Cloud sync is not configured. Your data remains on this device.')
                      else if (AppDatabase.instance.activeBusinessId == null)
                        const Text('Open a cloud business before running cloud sync.')
                      else
                        FilledButton.icon(
                          onPressed: _syncing ? null : _syncNow,
                          icon: _syncing
                              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                              : const Icon(Icons.sync),
                          label: const Text('Sync now'),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              if (operations.isEmpty)
                const Card(
                  child: Padding(
                    padding: EdgeInsets.all(20),
                    child: Text('No pending sync operations.'),
                  ),
                )
              else
                ...operations.map((item) {
                  final error = item['last_error']?.toString();
                  final isConflict = error?.contains('SYNC_CONFLICT') ?? false;
                  final title = '${item['table_name']} • ${item['operation']}';
                  final recordId = item['record_id']?.toString() ?? '';
                  return Card(
                    child: ListTile(
                      leading: Icon(
                        isConflict ? Icons.warning_amber_rounded : Icons.cloud_upload_outlined,
                        color: isConflict ? Theme.of(context).colorScheme.error : null,
                      ),
                      title: Text(title),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Record: ${recordId.length > 18 ? '${recordId.substring(0, 18)}…' : recordId}'),
                          Text('Retries: ${item['retry_count'] ?? 0}'),
                          if (item['next_retry_at'] != null &&
                              DateTime.tryParse(item['next_retry_at'].toString()) != null)
                            Text(
                              'Next retry: ${DateTime.parse(item['next_retry_at'].toString()).toLocal().toString().substring(0, 16)}',
                            ),
                          if (error != null && error.isNotEmpty)
                            Text(error, style: TextStyle(color: isConflict ? Theme.of(context).colorScheme.error : null)),
                          if (isConflict && widget.cloudConfigured && AppDatabase.instance.activeBusinessId != null) ...[
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 8,
                              runSpacing: 4,
                              children: [
                                OutlinedButton(
                                  onPressed: () => _resolveConflict(item, 'keep_local'),
                                  child: const Text('Keep Local'),
                                ),
                                FilledButton.tonal(
                                  onPressed: () => _resolveConflict(item, 'use_cloud'),
                                  child: const Text('Use Cloud'),
                                ),
                              ],
                            ),
                          ],
                        ],
                      ),
                      isThreeLine: error != null && error.isNotEmpty,
                    ),
                  );
                }),
            ],
          );
        },
      ),
    );
  }
}
