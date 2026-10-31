import 'package:flutter_test/flutter_test.dart';
import 'package:srk_business_manager/src/data/local/gst_gstr1_classification.dart';
import 'package:srk_business_manager/src/data/local/gst_gstr1_invoice_csv_export.dart';

void main() {
  group('Gstr1InvoiceCsvExport', () {
    test('exports invoice categories, amounts, supplier and period', () {
      final summary = Gstr1ClassificationSummary([
        const Gstr1InvoiceClassification(
          invoiceNumber: 'INV-001',
          category: Gstr1SupplyCategory.b2b,
          invoiceValue: 118,
          taxableValue: 100,
          taxAmount: 18,
        ),
        const Gstr1InvoiceClassification(
          invoiceNumber: 'INV-002',
          category: Gstr1SupplyCategory.b2cl,
          invoiceValue: 150000,
          taxableValue: 127118.64,
          taxAmount: 22881.36,
        ),
      ]);
      final csv = Gstr1InvoiceCsvExport.build(
        summary,
        supplierGstin: '19ABCDE1234F1Z5',
        periodStart: '2026-10-01',
        periodEnd: '2026-10-31',
      );
      expect(csv, startsWith('\uFEFF'));
      expect(csv, contains('Supplier GSTIN,19ABCDE1234F1Z5'));
      expect(csv, contains('2026-10-01 to 2026-10-31'));
      expect(csv, contains('INV-001,B2B,118.00,100.00,18.00,'));
      expect(csv, contains('INV-002,B2CL,150000.00,127118.64,22881.36,'));
    });

    test('quotes invoice numbers and review notes containing commas', () {
      final summary = Gstr1ClassificationSummary([
        const Gstr1InvoiceClassification(
          invoiceNumber: 'INV, "003"',
          category: Gstr1SupplyCategory.review,
          invoiceValue: 0,
          taxableValue: 0,
          taxAmount: 0,
          reason: 'Check GSTIN, place of supply',
        ),
      ]);
      final csv = Gstr1InvoiceCsvExport.build(
        summary, supplierGstin: '', periodStart: 'start', periodEnd: 'end',
      );
      expect(csv, contains('"INV, ""003""",REVIEW,0.00,0.00,0.00,"Check GSTIN, place of supply"'));
    });
  });
}
