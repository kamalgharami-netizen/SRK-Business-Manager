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
      'items': [
        {'hsn_sac': '9983', 'taxable_value': 1000.0, 'tax_amount': 180.0},
      ],
    };

    test('accepts valid core invoice data but keeps scope warning visible', () {
      final report = GstReturnReadiness.validateGstr1(
        supplierGstin: '19ABCDE1234F1Z5',
        supplierState: 'West Bengal',
        periodStart: periodStart,
        periodEnd: periodEnd,
        invoices: [validInvoice()],
      );

      expect(report.errorCount, 0);
      expect(report.canPrepareDraft, isTrue);
      expect(report.issues.any((issue) => issue.code == 'manual_scope_review'), isTrue);
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

    test('flags missing place of supply, line items and warns for missing HSN', () {
      final invoice = validInvoice()
        ..['place_of_supply'] = ''
        ..['items'] = [
          {'hsn_sac': '', 'taxable_value': 500.0, 'tax_amount': 90.0},
        ];
      final report = GstReturnReadiness.validateGstr1(
        supplierGstin: '19ABCDE1234F1Z5',
        supplierState: 'West Bengal',
        periodStart: periodStart,
        periodEnd: periodEnd,
        invoices: [invoice],
      );

      expect(report.issues.any((issue) => issue.code == 'place_of_supply_missing'), isTrue);
      expect(report.issues.any((issue) => issue.code == 'hsn_sac_missing'), isTrue);
      expect(report.canPrepareDraft, isFalse);
    });

    test('detects duplicate invoice numbers case-insensitively', () {
      final second = validInvoice()..['invoice_number'] = 'inv-001';
      final report = GstReturnReadiness.validateGstr1(
        supplierGstin: '19ABCDE1234F1Z5',
        supplierState: 'West Bengal',
        periodStart: periodStart,
        periodEnd: periodEnd,
        invoices: [validInvoice(), second],
      );

      expect(report.issues.any((issue) => issue.code == 'duplicate_invoice_number'), isTrue);
    });
  });
}
