import 'package:flutter_test/flutter_test.dart';
import 'package:srk_business_manager/src/data/sync/business_sync_entity_policy.dart';

void main() {
  group('BusinessSyncEntityPolicy', () {
    test('does not reapply an unchanged cloud revision', () {
      expect(
        BusinessSyncEntityPolicy.shouldApplyRemoteRevision('rev-1', 'rev-1'),
        isFalse,
      );
    });

    test('applies a new or previously unseen cloud revision', () {
      expect(
        BusinessSyncEntityPolicy.shouldApplyRemoteRevision('rev-1', 'rev-2'),
        isTrue,
      );
      expect(
        BusinessSyncEntityPolicy.shouldApplyRemoteRevision(null, 'rev-1'),
        isTrue,
      );
    });

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

    test('includes warehouse master data as a supported cloud entity', () {
      expect(BusinessSyncEntityPolicy.supports('warehouses'), isTrue);
    });

    test('includes atomic warehouse transfers as a supported cloud entity', () {
      expect(BusinessSyncEntityPolicy.supports('warehouse_transfers'), isTrue);
    });

    test('applies warehouse transfers after products, warehouses and stock source records', () {
      const order = BusinessSyncEntityPolicy.pullOrder;
      expect(order.indexOf('products'), lessThan(order.indexOf('warehouse_transfers')));
      expect(order.indexOf('warehouses'), lessThan(order.indexOf('warehouse_transfers')));
      expect(order.indexOf('invoices'), lessThan(order.indexOf('warehouse_transfers')));
      expect(order.indexOf('stock_movements'), lessThan(order.indexOf('warehouse_transfers')));
    });

    test('includes business profile as a supported cloud entity', () {
      expect(BusinessSyncEntityPolicy.supports('business_profile'), isTrue);
    });

    test('keeps product data available before invoices and stock movements', () {
      const order = BusinessSyncEntityPolicy.pullOrder;
      expect(order.indexOf('products'), lessThan(order.indexOf('invoices')));
      expect(order.indexOf('products'), lessThan(order.indexOf('stock_movements')));
    });

    test('keeps payment dependencies ordered before allocations', () {
      const order = BusinessSyncEntityPolicy.pullOrder;
      expect(order.indexOf('invoices'), lessThan(order.indexOf('payments')));
      expect(order.indexOf('payments'), lessThan(order.indexOf('payment_allocations')));
    });

    test('allows owner and admin to write every supported cloud entity', () {
      for (final role in ['owner', 'admin']) {
        for (final entity in BusinessSyncEntityPolicy.pullOrder) {
          expect(
            BusinessSyncEntityPolicy.canWrite(role, entity),
            isTrue,
            reason: '$role should write $entity',
          );
        }
      }
    });

    test('limits accountant to accounting and stock movement entities', () {
      const allowed = {
        'parties', 'products', 'expenses', 'invoices', 'payments',
        'payment_allocations', 'stock_movements',
      };
      for (final entity in BusinessSyncEntityPolicy.pullOrder) {
        expect(
          BusinessSyncEntityPolicy.canWrite('accountant', entity),
          allowed.contains(entity),
          reason: 'accountant permission for $entity',
        );
      }
    });

    test('limits sales to sales and payment entities, excluding warehouse transfers', () {
      const allowed = {
        'parties', 'products', 'invoices', 'payments', 'payment_allocations',
      };
      for (final entity in BusinessSyncEntityPolicy.pullOrder) {
        expect(
          BusinessSyncEntityPolicy.canWrite('sales', entity),
          allowed.contains(entity),
          reason: 'sales permission for $entity',
        );
      }
      expect(
        BusinessSyncEntityPolicy.canWrite('sales', 'warehouse_transfers'),
        isFalse,
      );
    });

    test('viewer and unknown roles cannot write cloud entities', () {
      for (final entity in BusinessSyncEntityPolicy.pullOrder) {
        expect(BusinessSyncEntityPolicy.canWrite('viewer', entity), isFalse);
        expect(BusinessSyncEntityPolicy.canWrite('unknown', entity), isFalse);
      }
    });

    test('role matching is case and whitespace tolerant', () {
      expect(BusinessSyncEntityPolicy.canWrite(' OWNER ', 'warehouse_transfers'), isTrue);
      expect(BusinessSyncEntityPolicy.canWrite(' Sales ', 'warehouse_transfers'), isFalse);
    });

    test('rejects unknown or local-only entities', () {
      for (final entity in ['journal_entries', 'gst_itc_adjustments', 'unknown']) {
        expect(BusinessSyncEntityPolicy.supports(entity), isFalse, reason: entity);
      }
    });

  });
}
