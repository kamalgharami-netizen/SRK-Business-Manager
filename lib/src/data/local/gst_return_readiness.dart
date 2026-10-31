import '../indian_states.dart';

enum GstReadinessSeverity { error, warning }

class GstReadinessIssue {
  const GstReadinessIssue({
    required this.severity,
    required this.code,
    required this.message,
  });

  final GstReadinessSeverity severity;
  final String code;
  final String message;
}

class GstReadinessReport {
  const GstReadinessReport(this.issues);

  final List<GstReadinessIssue> issues;

  int get errorCount =>
      issues.where((issue) => issue.severity == GstReadinessSeverity.error).length;
  int get warningCount =>
      issues.where((issue) => issue.severity == GstReadinessSeverity.warning).length;
  bool get canPrepareDraft => errorCount == 0;
}

/// Preflight checks for locally recorded outward invoices before GSTR-1
/// preparation. This deliberately does not generate a GSTN upload JSON file.
class GstReturnReadiness {
  GstReturnReadiness._();

  static GstReadinessReport validateGstr1({
    required String supplierGstin,
    required String supplierState,
    required DateTime periodStart,
    required DateTime periodEnd,
    required List<Map<String, Object?>> invoices,
  }) {
    final issues = <GstReadinessIssue>[];
    final gstin = supplierGstin.trim().toUpperCase();
    final state = supplierState.trim();

    if (periodEnd.isBefore(periodStart)) {
      issues.add(const GstReadinessIssue(
        severity: GstReadinessSeverity.error,
        code: 'invalid_period',
        message: 'Return period end date must not be before its start date.',
      ));
    }
    if (!RegExp(r'^[0-9]{2}[A-Z]{5}[0-9]{4}[A-Z][1-9A-Z]Z[0-9A-Z]$')
            .hasMatch(gstin) ||
        !IndianStates.gstinMatchesState(gstin, state)) {
      issues.add(const GstReadinessIssue(
        severity: GstReadinessSeverity.error,
        code: 'supplier_gstin_invalid',
        message: 'Enter a valid supplier GSTIN matching the selected registration state.',
      ));
    }
    if (!IndianStates.all.contains(state)) {
      issues.add(const GstReadinessIssue(
        severity: GstReadinessSeverity.error,
        code: 'supplier_state_missing',
        message: 'Select a valid GST registration state.',
      ));
    }

    final seenNumbers = <String>{};
    for (final invoice in invoices) {
      final number = (invoice['invoice_number'] as String? ?? '').trim();
      final dateText = (invoice['invoice_date'] as String? ?? '').trim();
      final date = DateTime.tryParse(dateText);
      if (number.isEmpty) {
        issues.add(const GstReadinessIssue(
          severity: GstReadinessSeverity.error,
          code: 'invoice_number_missing',
          message: 'An outward invoice has no invoice number.',
        ));
      } else if (!seenNumbers.add(number.toUpperCase())) {
        issues.add(GstReadinessIssue(
          severity: GstReadinessSeverity.error,
          code: 'duplicate_invoice_number',
          message: 'Duplicate invoice number in this return data: $number',
        ));
      }
      if (date == null ||
          date.isBefore(DateTime(periodStart.year, periodStart.month, periodStart.day)) ||
          date.isAfter(DateTime(periodEnd.year, periodEnd.month, periodEnd.day, 23, 59, 59))) {
        issues.add(GstReadinessIssue(
          severity: GstReadinessSeverity.error,
          code: 'invoice_date_outside_period',
          message: 'Invoice $number has a missing or out-of-period invoice date.',
        ));
      }

      final placeOfSupply = (invoice['place_of_supply'] as String? ?? '').trim();
      if (!IndianStates.all.contains(placeOfSupply)) {
        issues.add(GstReadinessIssue(
          severity: GstReadinessSeverity.error,
          code: 'place_of_supply_missing',
          message: 'Invoice $number has no valid place of supply state.',
        ));
      }

      final recipientGstin = (invoice['party_gstin'] as String? ?? '').trim().toUpperCase();
      final recipientState = (invoice['party_state'] as String? ?? '').trim();
      if (recipientGstin.isNotEmpty &&
          (!RegExp(r'^[0-9]{2}[A-Z]{5}[0-9]{4}[A-Z][1-9A-Z]Z[0-9A-Z]
        issues.add(GstReadinessIssue(
          severity: GstReadinessSeverity.error,
          code: 'recipient_gstin_invalid',
          message: 'Invoice $number contains an invalid recipient GSTIN.',
        ));
      }

      final items = invoice['items'];
      if (items is! List || items.isEmpty) {
        issues.add(GstReadinessIssue(
          severity: GstReadinessSeverity.error,
          code: 'invoice_items_missing',
          message: 'Invoice $number has no invoice line items.',
        ));
        continue;
      }
      for (final rawItem in items) {
        if (rawItem is! Map) continue;
        final hsn = (rawItem['hsn_sac'] as String? ?? '').trim();
        if (hsn.isEmpty) {
          issues.add(GstReadinessIssue(
            severity: GstReadinessSeverity.warning,
            code: 'hsn_sac_missing',
            message: 'Invoice $number contains a line without HSN/SAC; verify the applicable reporting requirement.',
          ));
        }
        final tax = (rawItem['tax_amount'] as num?)?.toDouble();
        final taxable = (rawItem['taxable_value'] as num?)?.toDouble();
        if (tax == null || taxable == null ||
            !tax.isFinite || !taxable.isFinite || tax < 0 || taxable < 0) {
          issues.add(GstReadinessIssue(
            severity: GstReadinessSeverity.error,
            code: 'invalid_tax_values',
            message: 'Invoice $number contains invalid taxable value or GST amount.',
          ));
        }
      }
    }

    issues.add(const GstReadinessIssue(
      severity: GstReadinessSeverity.warning,
      code: 'manual_scope_review',
      message: 'This preflight does not cover every GSTR-1 table, amendments, advances, exports, e-commerce supplies, or GSTN schema validation. Review these separately before filing.',
    ));
    return GstReadinessReport(List.unmodifiable(issues));
  }
}
)
                  .hasMatch(recipientGstin) ||
              !IndianStates.gstinMatchesState(recipientGstin, recipientState))) {
        issues.add(GstReadinessIssue(
          severity: GstReadinessSeverity.error,
          code: 'recipient_gstin_invalid',
          message: 'Invoice $number contains an invalid recipient GSTIN.',
        ));
      }

      final items = invoice['items'];
      if (items is! List || items.isEmpty) {
        issues.add(GstReadinessIssue(
          severity: GstReadinessSeverity.error,
          code: 'invoice_items_missing',
          message: 'Invoice $number has no invoice line items.',
        ));
        continue;
      }
      for (final rawItem in items) {
        if (rawItem is! Map) continue;
        final hsn = (rawItem['hsn_sac'] as String? ?? '').trim();
        if (hsn.isEmpty) {
          issues.add(GstReadinessIssue(
            severity: GstReadinessSeverity.warning,
            code: 'hsn_sac_missing',
            message: 'Invoice $number contains a line without HSN/SAC; verify the applicable reporting requirement.',
          ));
        }
        final tax = (rawItem['tax_amount'] as num?)?.toDouble();
        final taxable = (rawItem['taxable_value'] as num?)?.toDouble();
        if (tax == null || taxable == null ||
            !tax.isFinite || !taxable.isFinite || tax < 0 || taxable < 0) {
          issues.add(GstReadinessIssue(
            severity: GstReadinessSeverity.error,
            code: 'invalid_tax_values',
            message: 'Invoice $number contains invalid taxable value or GST amount.',
          ));
        }
      }
    }

    issues.add(const GstReadinessIssue(
      severity: GstReadinessSeverity.warning,
      code: 'manual_scope_review',
      message: 'This preflight does not cover every GSTR-1 table, amendments, advances, exports, e-commerce supplies, or GSTN schema validation. Review these separately before filing.',
    ));
    return GstReadinessReport(List.unmodifiable(issues));
  }
}
