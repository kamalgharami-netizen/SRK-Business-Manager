import 'package:flutter_test/flutter_test.dart';
import 'package:srk_business_manager/src/data/local/gst_gstr3b_itc.dart';
import 'package:srk_business_manager/src/data/local/gst_gstr3b_table4_csv_export.dart';

void main() {
  group('Gstr3bTable4CsvExport', () {
    test('exports Table 4 amounts by tax head and preparation status', () {
      final summary = Gstr3bItcCalculator.summarize([
        const Gstr3bItcEntry(
          documentReference: 'PUR-001',
          category: Gstr3bItcCategory.other,
          treatment: Gstr3bItcTreatment.eligible,
          tax: Gstr3bTaxAmounts(igst: 18, cgst: 9, sgst: 9, cess: 2),
        ),
        const Gstr3bItcEntry(
          documentReference: 'REV-001',
          category: Gstr3bItcCategory.other,
          treatment: Gstr3bItcTreatment.reversalOther,
          tax: Gstr3bTaxAmounts(igst: 3),
        ),
      ]);
      final csv = Gstr3bTable4CsvExport.build(
        returnPeriod: '2026-11',
        summary: summary,
      );
      expect(csv, startsWith('\uFEFF'));
      expect(csv, contains('PREPARATION_CHECKS_PASSED'));
      expect(csv, contains('4(A)(5),Other Eligible ITC / Reclaim,18.00,9.00,9.00,2.00'));
      expect(csv, contains('4(B)(2),Other Reversal,3.00,0.00,0.00,0.00'));
      expect(csv, contains('4(C),Net ITC (4A less 4B),15.00,9.00,9.00,2.00'));
      expect(csv, contains('not GSTN upload JSON'));
    });

    test('marks unresolved reviews and blocks invalid return periods', () {
      final summary = Gstr3bItcCalculator.summarize([
        const Gstr3bItcEntry(
          documentReference: 'PENDING-1',
          category: Gstr3bItcCategory.other,
          treatment: Gstr3bItcTreatment.pendingReview,
          tax: Gstr3bTaxAmounts(igst: 1),
        ),
      ]);
      final csv = Gstr3bTable4CsvExport.build(
        returnPeriod: '2026-11',
        summary: summary,
      );
      expect(csv, contains('REVIEW_REQUIRED'));
      expect(csv, contains('Pending Review Count,1'));
      expect(
        () => Gstr3bTable4CsvExport.build(returnPeriod: '2026-13', summary: summary),
        throwsFormatException,
      );
    });

    test('quotes CSV cells and neutralises formula-like issue text', () {
      final summary = Gstr3bItcCalculator.summarize([
        const Gstr3bItcEntry(
          documentReference: '=FORMULA,1',
          category: Gstr3bItcCategory.other,
          treatment: Gstr3bItcTreatment.eligible,
          tax: Gstr3bTaxAmounts(igst: -1),
        ),
      ]);
      final csv = Gstr3bTable4CsvExport.build(
        returnPeriod: '2026-11',
        summary: summary,
      );
      expect(csv, contains("'Document =FORMULA,1 contains a negative or non-finite tax amount."));
      expect(csv, contains('Negative'));
    });
  });
}
