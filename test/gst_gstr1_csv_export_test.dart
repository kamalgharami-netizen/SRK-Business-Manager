import 'package:flutter_test/flutter_test.dart';
import 'package:srk_business_manager/src/data/local/gst_gstr1_hsn_summary.dart';
import 'package:srk_business_manager/src/data/local/gst_gstr1_csv_export.dart';

void main() {
  group('Gstr1HsnCsvExport', () {
    test('exports HSN totals with period and spreadsheet-friendly BOM', () {
      final csv = Gstr1HsnCsvExport.build([
        const Gstr1HsnRateSummary(
          hsnSac: '1001', gstRate: 5, unit: 'pcs', quantity: 2, totalValue: 105, taxableValue: 100,
          taxAmount: 5, cgst: 2.5, sgst: 2.5, igst: 0,
        ),
      ], supplierGstin: '19ABCDE1234F1Z5',
        periodStart: '2026-10-01', periodEnd: '2026-10-31');
      expect(csv, startsWith('\uFEFF'));
      expect(csv, contains('Supplier GSTIN,19ABCDE1234F1Z5'));
      expect(csv, contains('2026-10-01 to 2026-10-31'));
      expect(csv, contains('1001,5.00,pcs,2.00,105.00,100.00,5.00,2.50,2.50,0.00'));
      expect(csv, contains('Unit (as entered)'));
      expect(csv, contains('TOTAL,,,,105.00,100.00,5.00,2.50,2.50,0.00'));
    });

    test('omits total row when there are no HSN rows', () {
      final csv = Gstr1HsnCsvExport.build(
        const [], supplierGstin: '', periodStart: 'start', periodEnd: 'end',
      );
      expect(csv, isNot(contains('TOTAL')));
    });

    test('escapes commas and quotation marks in HSN text', () {
      final csv = Gstr1HsnCsvExport.build([
        const Gstr1HsnRateSummary(
          hsnSac: 'HSN, "other"', gstRate: 0, unit: 'pcs', quantity: 1, totalValue: 20, taxableValue: 20,
          taxAmount: 0, cgst: 0, sgst: 0, igst: 0,
        ),
      ], supplierGstin: '', periodStart: 'start', periodEnd: 'end');
      expect(csv, contains('"HSN, ""other"""'));
    });

    test('neutralises spreadsheet formulas in untrusted HSN text', () {
      final csv = Gstr1HsnCsvExport.build([
        const Gstr1HsnRateSummary(
          hsnSac: '=HYPERLINK("https://example.com")', gstRate: 0,
          unit: 'pcs', quantity: 1, totalValue: 20, taxableValue: 20, taxAmount: 0, cgst: 0, sgst: 0, igst: 0,
        ),
      ], supplierGstin: '', periodStart: 'start', periodEnd: 'end');
      expect(csv, contains("'=HYPERLINK"));
    });
  });
}
