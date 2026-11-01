import 'package:flutter_test/flutter_test.dart';
import 'package:srk_business_manager/src/data/local/gst_gstr3b_itc.dart';
import 'package:srk_business_manager/src/data/local/gst_gstr3b_itc_repository.dart';

void main() {
  group('GSTR-3B ITC assessment validation', () {
    const tax = Gstr3bTaxAmounts(igst: 18, cess: 2);

    test('accepts valid supplier invoice and period data', () {
      expect(
        Gstr3bItcAssessmentValidator.validate(
          supplierGstin: '27AAPFU0939F1ZV',
          supplierInvoiceNumber: 'INV-100',
          supplierInvoiceDate: '2026-10-12',
          returnPeriod: '2026-10',
          taxableValue: 100,
          tax: tax,
        ),
        isEmpty,
      );
    });

    test('keeps a missing supplier GSTIN visible as an incomplete-data issue', () {
      expect(
        Gstr3bItcAssessmentValidator.validate(
          supplierGstin: '',
          supplierInvoiceNumber: 'INV-100',
          supplierInvoiceDate: '2026-10-12',
          returnPeriod: '2026-10',
          taxableValue: 100,
          tax: tax,
        ),
        contains('Supplier GSTIN is missing.'),
      );
    });

    test('rejects invalid invoice dates, periods and negative taxable value', () {
      final issues = Gstr3bItcAssessmentValidator.validate(
        supplierGstin: '27AAPFU0939F1ZV',
        supplierInvoiceNumber: 'INV-100',
        supplierInvoiceDate: 'not-a-date',
        returnPeriod: '2026-13',
        taxableValue: -1,
        tax: tax,
      );
      expect(issues, hasLength(3));
    });

    test('rejects negative or infinite GST components', () {
      final issues = Gstr3bItcAssessmentValidator.validate(
        supplierGstin: '27AAPFU0939F1ZV',
        supplierInvoiceNumber: 'INV-100',
        supplierInvoiceDate: '2026-10-12',
        returnPeriod: '2026-10',
        taxableValue: 100,
        tax: const Gstr3bTaxAmounts(cgst: double.infinity),
      );
      expect(issues, contains('GST components must be finite and non-negative.'));
    });
  });

  group('GSTR-2B reconciliation matching', () {
    const statement = Gstr2bImportRecord(
      supplierGstin: '27AAPFU0939F1ZV',
      invoiceNumber: 'inv-100',
      invoiceDate: '2026-10-12',
      returnPeriod: '2026-10',
      taxableValue: 100,
      igst: 18,
    );

    test('matches supplier, document, period and tax values case-insensitively', () {
      expect(
        Gstr2bReconciliationMatcher.matches(
          statement: statement,
          supplierGstin: '27aapfu0939f1zv',
          invoiceNumber: 'INV-100',
          invoiceDate: '2026-10-12T00:00:00',
          returnPeriod: '2026-10',
          taxableValue: 100.005,
          tax: const Gstr3bTaxAmounts(igst: 18),
        ),
        isTrue,
      );
    });

    test('does not match when the tax amount differs', () {
      expect(
        Gstr2bReconciliationMatcher.matches(
          statement: statement,
          supplierGstin: '27AAPFU0939F1ZV',
          invoiceNumber: 'INV-100',
          invoiceDate: '2026-10-12',
          returnPeriod: '2026-10',
          taxableValue: 100,
          tax: const Gstr3bTaxAmounts(igst: 19),
        ),
        isFalse,
      );
    });
  });
}
