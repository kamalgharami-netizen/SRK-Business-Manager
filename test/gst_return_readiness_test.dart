import 'package:flutter_test/flutter_test.dart';
import 'package:srk_business_manager/src/data/local/gst_return_readiness.dart';

void main() {
  group('GstReturnReadiness.validateGstr1', () {
    final periodStart = DateTime(2026, 10, 1);
    final periodEnd = DateTime(2026, 10, 31);

    Map<String, Object?> validInvoice() => {
      'invoice_number': 'INV-001',
      'invoice_date': '2026-10-12',
      'place_of_supply': 'West Bengal',
      'party_gstin': '19ABCDE1234F1Z5',
      'party_state': 'West Bengal',
      'items': [
        {'hsn_sac': '9983', 'line_total': 1180.0, 'tax_amount': 180.0, 'cgst_amount': 90.0, 'sgst_amount': 90.0, 'igst_amount': 0.0},
      ],
    };

    GstReadinessReport validate(List<Map<String, Object?>> invoices) =>
        GstReturnReadiness.validateGstr1(
          supplierGstin: '19ABCDE1234F1Z5',
          supplierState: 'West Bengal',
          periodStart: periodStart,
          periodEnd: periodEnd,
          invoices: invoices,
        );


    test('normalizes state casing and repeated whitespace in supplier, place and recipient state', () {
      final invoice = validInvoice()
        ..['place_of_supply'] = ' west   bengal '
        ..['party_state'] = ' WEST  BENGAL ';
      final report = GstReturnReadiness.validateGstr1(
        supplierGstin: '19ABCDE1234F1Z5',
        supplierState: ' west   bengal ',
        periodStart: periodStart,
        periodEnd: periodEnd,
        invoices: [invoice],
      );
      expect(report.issues.where((issue) =>
          issue.code == 'supplier_state_missing' ||
          issue.code == 'supplier_gstin_invalid' ||
          issue.code == 'place_of_supply_missing' ||
          issue.code == 'recipient_gstin_invalid'), isEmpty);
      expect(report.errorCount, 0);
    });

    test('accepts valid core invoice data but keeps scope warning visible', () {
      final report = validate([validInvoice()]);
      expect(report.errorCount, 0);
      expect(report.canPrepareDraft, isTrue);
      expect(report.issues.any((issue) => issue.code == 'manual_scope_review'), isTrue);
    });

    test('accepts explicit taxable value when supplied by another data source', () {
      final invoice = validInvoice()..['items'] = [
        {'hsn_sac': '9983', 'taxable_value': 1000.0, 'tax_amount': 180.0},
      ];
      expect(validate([invoice]).errorCount, 0);
    });

    test('flags tax component mismatch and tax exceeding line total', () {
      final invoice = validInvoice()..['items'] = [
        {'hsn_sac': '9983', 'line_total': 1180.0, 'tax_amount': 180.0, 'cgst_amount': 80.0, 'sgst_amount': 90.0, 'igst_amount': 0.0},
        {'hsn_sac': '9983', 'line_total': 100.0, 'tax_amount': 110.0, 'cgst_amount': 55.0, 'sgst_amount': 55.0, 'igst_amount': 0.0},
      ];
      expect(validate([invoice]).issues.where((issue) => issue.code == 'invalid_tax_values').length, 2);
    });


    test('rejects invoice numbers longer than 16 characters or with unsupported symbols', () {
      final tooLong = validInvoice()..['invoice_number'] = 'INV-1234567890123';
      final unsupported = validInvoice()..['invoice_number'] = 'INV_001';
      final report = validate([tooLong, unsupported]);
      expect(report.issues.where((issue) =>
          issue.code == 'invoice_number_format_invalid').length, 2);
      expect(report.canPrepareDraft, isFalse);
    });

    test('accepts invoice numbers using permitted characters within 16 characters', () {
      final invoice = validInvoice()..['invoice_number'] = 'AB-12/34&X';
      final report = validate([invoice]);
      expect(report.issues.any((issue) =>
          issue.code == 'invoice_number_format_invalid'), isFalse);
      expect(report.errorCount, 0);
    });

    test('flags invalid supplier GSTIN and out-of-period invoice', () {
      final invoice = validInvoice()..['invoice_date'] = '2026-09-30';
      final report = GstReturnReadiness.validateGstr1(
        supplierGstin: 'INVALID',
        supplierState: 'West Bengal',
        periodStart: periodStart,
        periodEnd: periodEnd,
        invoices: [invoice],
      );
      expect(report.issues.any((issue) => issue.code == 'supplier_gstin_invalid'), isTrue);
      expect(report.issues.any((issue) => issue.code == 'invoice_date_outside_period'), isTrue);
      expect(report.canPrepareDraft, isFalse);
    });

    test('flags missing place of supply and warns for missing HSN', () {
      final invoice = validInvoice()
        ..['place_of_supply'] = ''
        ..['items'] = [
          {'hsn_sac': '', 'taxable_value': 500.0, 'tax_amount': 90.0},
        ];
      final report = validate([invoice]);
      expect(report.issues.any((issue) => issue.code == 'place_of_supply_missing'), isTrue);
      expect(report.issues.any((issue) => issue.code == 'hsn_sac_missing'), isTrue);
      expect(report.canPrepareDraft, isFalse);
    });

    test('flags recipient GSTIN that does not match party state', () {
      final invoice = validInvoice()..['party_state'] = 'Bihar';
      final report = validate([invoice]);
      expect(report.issues.any((issue) => issue.code == 'recipient_gstin_invalid'), isTrue);
      expect(report.canPrepareDraft, isFalse);
    });

    test('detects duplicate invoice numbers case-insensitively in the selected period', () {
      final second = validInvoice()..['invoice_number'] = 'inv-001';
      final report = validate([validInvoice(), second]);
      expect(report.issues.any((issue) => issue.code == 'duplicate_invoice_number'), isTrue);
    });

    test('detects a duplicate invoice number used in another month of the same financial year', () {
      final report = GstReturnReadiness.validateGstr1(
        supplierGstin: '19ABCDE1234F1Z5',
        supplierState: 'West Bengal',
        periodStart: periodStart,
        periodEnd: periodEnd,
        invoices: [validInvoice()],
        financialYearInvoiceNumbers: ['INV-001', 'inv-001'],
      );
      expect(
        report.issues.where((issue) => issue.code == 'duplicate_invoice_number'),
        hasLength(1),
      );
      expect(report.canPrepareDraft, isFalse);
    });

    test('does not flag a number repeated only once in the financial year', () {
      final report = GstReturnReadiness.validateGstr1(
        supplierGstin: '19ABCDE1234F1Z5',
        supplierState: 'West Bengal',
        periodStart: periodStart,
        periodEnd: periodEnd,
        invoices: [validInvoice()],
        financialYearInvoiceNumbers: ['INV-001'],
      );
      expect(
        report.issues.any((issue) => issue.code == 'duplicate_invoice_number'),
        isFalse,
      );
    });

    test('does not silently ignore malformed invoice line items', () {
      final invoice = validInvoice()..['items'] = [null, 'not a row'];
      final report = validate([invoice]);
      expect(report.issues.where((issue) => issue.code == 'invoice_item_malformed').length, 2);
      expect(report.canPrepareDraft, isFalse);
    });

    test('flags non-finite and negative line tax values', () {
      final invoice = validInvoice()
        ..['items'] = [
          {'hsn_sac': '9983', 'taxable_value': double.infinity, 'tax_amount': 10.0},
          {'hsn_sac': '9983', 'taxable_value': 10.0, 'tax_amount': -1.0},
        ];
      final report = validate([invoice]);
      expect(report.issues.where((issue) => issue.code == 'invalid_tax_values').length, 2);
      expect(report.canPrepareDraft, isFalse);
    });


    test('flags invoice header GST total that differs from its line-item GST sum', () {
      final invoice = validInvoice()..['tax_total'] = 200.0;
      final report = validate([invoice]);
      expect(report.issues.any((issue) =>
          issue.code == 'invoice_tax_total_mismatch'), isTrue);
      expect(report.canPrepareDraft, isFalse);
    });

    test('accepts invoice header GST total and components matching line items', () {
      final invoice = validInvoice()
        ..['tax_total'] = 180.0
        ..['cgst_total'] = 90.0
        ..['sgst_total'] = 90.0
        ..['igst_total'] = 0.0;
      final report = validate([invoice]);
      expect(report.issues.any((issue) =>
          issue.code == 'invoice_tax_total_mismatch'), isFalse);
      expect(report.issues.any((issue) =>
          issue.code == 'invoice_tax_components_mismatch'), isFalse);
      expect(report.errorCount, 0);
    });

    test('flags invoice header GST components that do not reconcile', () {
      final invoice = validInvoice()
        ..['tax_total'] = 180.0
        ..['cgst_total'] = 80.0
        ..['sgst_total'] = 90.0
        ..['igst_total'] = 0.0;
      final report = validate([invoice]);
      expect(report.issues.any((issue) =>
          issue.code == 'invoice_tax_components_mismatch'), isTrue);
      expect(report.canPrepareDraft, isFalse);
    });

    test('warns when no outward invoices exist in the selected period', () {
      final report = validate([]);
      expect(report.issues.any((issue) => issue.code == 'no_outward_invoices'), isTrue);
      expect(report.errorCount, 0);
    });
  });
}
