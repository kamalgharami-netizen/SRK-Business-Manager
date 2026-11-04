import 'package:flutter_test/flutter_test.dart';
import 'package:srk_business_manager/src/data/sync/business_sync_cursor.dart';

void main() {
  group('BusinessSyncCursor', () {
    test('continues after timestamp and record ID as a composite key', () {
      expect(
        BusinessSyncCursor.nextPageFilter(
          updatedAt: '2026-11-04T10:15:30.123456+00:00',
          recordId: 'record-b',
        ),
        'updated_at.gt.2026-11-04T10:15:30.123456+00:00,'
        'and(updated_at.eq.2026-11-04T10:15:30.123456+00:00,'
        'record_id.gt.record-b)',
      );
    });

    test('same-timestamp records are ordered by record ID', () {
      final filter = BusinessSyncCursor.nextPageFilter(
        updatedAt: '2026-11-04T10:15:30+00:00',
        recordId: 'record-100',
      );
      expect(filter, contains('updated_at.eq.2026-11-04T10:15:30+00:00'));
      expect(filter, contains('record_id.gt.record-100'));
    });

    test('rejects empty cursor components', () {
      expect(
        () => BusinessSyncCursor.nextPageFilter(
          updatedAt: '',
          recordId: 'record-a',
        ),
        throwsArgumentError,
      );
      expect(
        () => BusinessSyncCursor.nextPageFilter(
          updatedAt: '2026-11-04T10:15:30+00:00',
          recordId: '',
        ),
        throwsArgumentError,
      );
    });

    test('rejects filter syntax characters in cursor values', () {
      expect(
        () => BusinessSyncCursor.nextPageFilter(
          updatedAt: '2026-11-04T10:15:30+00:00)',
          recordId: 'record-a',
        ),
        throwsArgumentError,
      );
    });
  });
}
