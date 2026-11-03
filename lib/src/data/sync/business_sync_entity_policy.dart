/// Single source of truth for entities that participate in business sync.
///
/// Pull order is dependency-aware: parent records are applied before records
/// that refer to them (invoices before payments, payments before allocations).
class BusinessSyncEntityPolicy {
  BusinessSyncEntityPolicy._();

  static const List<String> pullOrder = [
    'business_profile',
    'staff_members',
    'parties',
    'products',
    'warehouses',
    'warehouse_transfers',
    'expenses',
    'invoices',
    'payments',
    'payment_allocations',
    'stock_movements',
  ];

  static bool supports(String entityType) => pullOrder.contains(entityType);
}
