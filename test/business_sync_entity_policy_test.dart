import 'package:flutter_test/flutter_test.dart';
import 'package:srk_business_manager/src/data/sync/business_sync_entity_policy.dart';

void main() {
  group('BusinessSyncEntityPolicy', () {
    test('supports every entity in the dependency-aware pull order', () {
      for (final entity in BusinessSyncEntityPolicy.pullOrder) {
        expect(BusinessSyncEntityPolicy.supports(entity), isTrue, reason: entity);
      }
    });

    test('includes advance allocations as a supported cloud entity', () {
      expect(BusinessSyncEntityPolicy.supports('payment_allocations'), isTrue);
    });

    test('includes staff profiles as a supported cloud entity', () {
    expect(BusinessSyncEntityPolicy.supports('staff_members'), isTrue);
  });

  test('includes business profile as a supported cloud entity', () {
      expect(BusinessSyncEntityPolicy.supports('business_profile'), isTrue);
    });

    test('keeps payment dependencies ordered before allocations', () {
      const order = BusinessSyncEntityPolicy.pullOrder;
      expect(order.indexOf('invoices'), lessThan(order.indexOf('payments')));
      expect(order.indexOf('payments'), lessThan(order.indexOf('payment_allocations')));
    });

    test('rejects unknown or local-only entities', () {
      for (final entity in ['journal_entries', 'gst_itc_adjustments', 'unknown']) {
        expect(BusinessSyncEntityPolicy.supports(entity), isFalse, reason: entity);
      }
    });
  });
}
