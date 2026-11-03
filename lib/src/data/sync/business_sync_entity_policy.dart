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
    'expenses',
    'invoices',
    'payments',
    'payment_allocations',
    'stock_movements',
    'warehouse_transfers',
  ];

  static bool supports(String entityType) => pullOrder.contains(entityType);

  /// Mirrors the server-side can_write_business_entity role policy.
  static bool canWrite(String role, String entityType) {
    switch (role.trim().toLowerCase()) {
      case 'owner':
      case 'admin':
        return true;
      case 'accountant':
        return const {
          'parties',
          'products',
          'expenses',
          'invoices',
          'payments',
          'payment_allocations',
          'stock_movements',
        }.contains(entityType);
      case 'sales':
        return const {
          'parties',
          'products',
          'invoices',
          'payments',
          'payment_allocations',
        }.contains(entityType);
      case 'viewer':
      default:
        return false;
    }
  }
}
