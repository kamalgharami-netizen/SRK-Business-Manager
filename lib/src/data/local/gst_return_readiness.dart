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

/// Core preflight checks only; this does not generate GSTN upload JSON.
class GstReturnReadiness {
  GstReturnReadiness._();

  static GstReadinessReport validateGstr1({
    required String supplierGstin,
    required String supplierState,
    required DateTime periodStart,
    required DateTime periodEnd,
    required List<Map<String, Object?>> invoices,
    List<String> financialYearInvoiceNumbers = const [],
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
    if (!IndianStates.isKnown(state)) {
      issues.add(const GstReadinessIssue(
        severity: GstReadinessSeverity.error,
        code: 'supplier_state_missing',
        message: 'Select a valid GST registration state.',
      ));
    }

    if (invoices.isEmpty) {
      issues.add(const GstReadinessIssue(
        severity: GstReadinessSeverity.warning,
        code: 'no_outward_invoices',
        message: 'No outward sales invoices were found for the selected period.',
      ));
    }

    final seenNumbers = <String>{};
    final financialYearNumberCounts = <String, int>{};
    for (final value in financialYearInvoiceNumbers) {
      final normalized = value.trim().toUpperCase();
      if (normalized.isNotEmpty) {
        financialYearNumberCounts.update(
          normalized,
          (count) => count + 1,
          ifAbsent: () => 1,
        );
      }
    }
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
      } else if (number.length > 16 ||
          !RegExp(r'^[A-Za-z0-9&/-]+$').hasMatch(number)) {
        issues.add(GstReadinessIssue(
          severity: GstReadinessSeverity.error,
          code: 'invoice_number_format_invalid',
          message: 'Invoice $number must be at most 16 characters and use only letters, numbers, hyphen, ampersand or slash.',
        ));
      } else {
        final normalizedNumber = number.toUpperCase();
        final duplicateInSelectedPeriod = !seenNumbers.add(normalizedNumber);
        final duplicateInFinancialYear =
            (financialYearNumberCounts[normalizedNumber] ?? 0) > 1;
        if (duplicateInSelectedPeriod || duplicateInFinancialYear) {
          issues.add(GstReadinessIssue(
            severity: GstReadinessSeverity.error,
            code: 'duplicate_invoice_number',
            message: 'Invoice number $number is duplicated within the financial year.',
          ));
        }
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
      if (!IndianStates.isKnown(placeOfSupply)) {
        issues.add(GstReadinessIssue(
          severity: GstReadinessSeverity.error,
          code: 'place_of_supply_missing',
          message: 'Invoice $number has no valid place of supply state.',
        ));
      }

      final recipientGstin = (invoice['party_gstin'] as String? ?? '').trim().toUpperCase();
      final recipientState = (invoice['party_state'] as String? ?? '').trim();
      if (recipientGstin.isNotEmpty &&
          (!RegExp(r'^[0-9]{2}[A-Z]{5}[0-9]{4}[A-Z][1-9A-Z]Z[0-9A-Z]$')
                  .hasMatch(recipientGstin) ||
              !IndianStates.gstinMatchesState(recipientGstin, recipientState))) {
        issues.add(GstReadinessIssue(
          severity: GstReadinessSeverity.error,
          code: 'recipient_gstin_invalid',
          message: 'Invoice $number contains an invalid recipient GSTIN or GSTIN/state mismatch.',
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
      var itemTaxTotal = 0.0;
      var itemTaxValuesValid = true;
      for (var index = 0; index < items.length; index++) {
        final rawItem = items[index];
        if (rawItem is! Map) {
          issues.add(GstReadinessIssue(
            severity: GstReadinessSeverity.error,
            code: 'invoice_item_malformed',
            message: 'Invoice $number contains an unreadable line item at row ${index + 1}.',
          ));
          continue;
        }
        final hsn = (rawItem['hsn_sac'] as String? ?? '').trim();
        if (hsn.isEmpty) {
          issues.add(GstReadinessIssue(
            severity: GstReadinessSeverity.warning,
            code: 'hsn_sac_missing',
            message: 'Invoice $number contains a line without HSN/SAC; verify the applicable reporting requirement.',
          ));
        }
        final tax = _finiteNumber(rawItem['tax_amount']);
        if (tax == null) {
          itemTaxValuesValid = false;
        } else {
          itemTaxTotal += tax;
        }
        final storedTaxable = _finiteNumber(rawItem['taxable_value']);
        final lineTotal = _finiteNumber(rawItem['line_total']);
        final taxable = storedTaxable ?? (lineTotal != null && tax != null
            ? lineTotal - tax
            : null);
        final cgst = _finiteNumber(rawItem['cgst_amount']);
        final sgst = _finiteNumber(rawItem['sgst_amount']);
        final igst = _finiteNumber(rawItem['igst_amount']);
        final hasTaxComponents = rawItem.containsKey('cgst_amount') ||
            rawItem.containsKey('sgst_amount') ||
            rawItem.containsKey('igst_amount');
        final componentsReconcile = !hasTaxComponents ||
            (cgst != null && sgst != null && igst != null &&
                (cgst + sgst + igst - (tax ?? double.nan)).abs() <= 0.01);
        if (tax == null || taxable == null || tax < 0 || taxable < 0 ||
            (lineTotal != null && (lineTotal < 0 || tax > lineTotal + 0.01)) ||
            !componentsReconcile) {
          issues.add(GstReadinessIssue(
            severity: GstReadinessSeverity.error,
            code: 'invalid_tax_values',
            message: 'Invoice $number contains invalid taxable value or GST amount, or tax components do not reconcile.',
          ));
        }
      }

      final headerTaxTotal = _finiteNumber(invoice['tax_total']);
      if (invoice.containsKey('tax_total')) {
        if (headerTaxTotal == null || headerTaxTotal < 0 ||
            (itemTaxValuesValid &&
                (itemTaxTotal - headerTaxTotal).abs() > 0.01)) {
          issues.add(GstReadinessIssue(
            severity: GstReadinessSeverity.error,
            code: 'invoice_tax_total_mismatch',
            message: 'Invoice $number header GST total does not match the sum of its line-item GST amounts.',
          ));
        }
      }

      final hasHeaderTaxComponents = invoice.containsKey('cgst_total') ||
          invoice.containsKey('sgst_total') ||
          invoice.containsKey('igst_total');
      if (hasHeaderTaxComponents) {
        final headerCgst = _finiteNumber(invoice['cgst_total']);
        final headerSgst = _finiteNumber(invoice['sgst_total']);
        final headerIgst = _finiteNumber(invoice['igst_total']);
        final componentsValid = headerCgst != null &&
            headerSgst != null &&
            headerIgst != null &&
            headerCgst >= 0 &&
            headerSgst >= 0 &&
            headerIgst >= 0;
        if (!componentsValid ||
            (headerTaxTotal != null &&
                ((headerCgst ?? double.nan) + (headerSgst ?? double.nan) + (headerIgst ?? double.nan) - headerTaxTotal).abs() > 0.01)) {
          issues.add(GstReadinessIssue(
            severity: GstReadinessSeverity.error,
            code: 'invoice_tax_components_mismatch',
            message: 'Invoice $number header CGST, SGST and IGST do not reconcile with its total GST.',
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

  static double? _finiteNumber(Object? value) {
    if (value is! num) return null;
    final number = value.toDouble();
    return number.isFinite ? number : null;
  }
}
