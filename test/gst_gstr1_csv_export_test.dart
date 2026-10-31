import 'package:flutter_test/flutter_test.dart';
import 'package:srk_business_manager/src/data/local/gst_gstr1_hsn_summary.dart';
import 'package:srk_business_manager/src/data/local/gst_gstr1_csv_export.dart';

void main() {
  group('Gstr1HsnCsvExport', () {
    test('exports HSN totals with period and spreadsheet-friendly BOM', () {
      final csv = Gstr1HsnCsvExport.build([
        const Gstr1HsnRateSummary(
          hsnSac: '1001', gstRate: 5, taxableValue: 100,
          taxAmount: 5, cgst: 2.5, sgst: 2.5, igst: 0,
        ),
      ], supplierGstin: '19ABCDE1234F1Z5',
        periodStart: '2026-10-01', periodEnd: '2026-10-31');
      expect(csv, startsWith('\uFEFF'));
      expect(csv, contains('Supplier GSTIN,19ABCDE1234F1Z5'));
      expect(csv, contains('2026-10-01 to 2026-10-31'));
      expect(csv, contains('1001,5.00,100.00,5.00,2.50,2.50,0.00'));
    });

    test('escapes commas and quotation marks in HSN text', () {
      final csv = Gstr1HsnCsvExport.build([
        const Gstr1HsnRateSummary(
          hsnSac: 'HSN, "other"', gstRate: 0, taxableValue: 20,
          taxAmount: 0, cgst: 0, sgst: 0, igst: 0,
        ),
      ], supplierGstin: '', periodStart: 'start', periodEnd: 'end');
      expect(csv, contains('"HSN, ""other"""'));
    });
  });
}
