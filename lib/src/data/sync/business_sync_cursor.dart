/// Builds the strict continuation boundary for a keyset-paginated pull.
///
/// The first page after a saved checkpoint is intentionally inclusive at the
/// timestamp level. Subsequent pages use this strict composite comparison.
class BusinessSyncCursor {
  const BusinessSyncCursor._();

  static String nextPageFilter({
    required String updatedAt,
    required String recordId,
  }) {
    if (updatedAt.isEmpty || recordId.isEmpty) {
      throw ArgumentError('Cursor timestamp and record ID must be non-empty.');
    }
    if (updatedAt.contains(',') || updatedAt.contains('(') ||
        updatedAt.contains(')') || recordId.contains(',') ||
        recordId.contains('(') || recordId.contains(')')) {
      throw ArgumentError('Cursor values contain unsupported filter characters.');
    }
    return 'updated_at.gt.$updatedAt,and(updated_at.eq.$updatedAt,record_id.gt.$recordId)';
  }
}
