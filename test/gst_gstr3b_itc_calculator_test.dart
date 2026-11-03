import 'package:flutter_test/flutter_test.dart';
import 'package:srk_business_manager/src/data/local/gst_gstr3b_itc.dart';

void main() {
  group('GSTR-3B Table 4 net ITC calculation', () {
    test('retains negative net ITC and exposes the liability by tax head', () {
      final summary = Gstr3bItcCalculator.summarize([
        const Gstr3bItcEntry(
          documentReference: 'PURCHASE-1',
          category: Gstr3bItcCategory.other,
          treatment: Gstr3bItcTreatment.eligible,
          tax: Gstr3bTaxAmounts(igst: 100, cgst: 30),
        ),
        const Gstr3bItcEntry(
          documentReference: 'REVERSAL-1',
          category: Gstr3bItcCategory.other,
          treatment: Gstr3bItcTreatment.reversalOther,
          tax: Gstr3bTaxAmounts(igst: 125, cgst: 20, sgst: 8),
        ),
      ]);

      expect(summary.netItc.igst, -25);
      expect(summary.netItc.cgst, 10);
      expect(summary.netItc.sgst, -8);
      expect(summary.negativeNetItcLiability.igst, 25);
      expect(summary.negativeNetItcLiability.cgst, 0);
      expect(summary.negativeNetItcLiability.sgst, 8);
      expect(summary.requiresNegativeNetItcReview, isTrue);
      expect(summary.canPrepareDraft, isFalse);
    });

    test('does not create a negative liability when net ITC is non-negative', () {
      final summary = Gstr3bItcCalculator.summarize([
        const Gstr3bItcEntry(
          documentReference: 'PURCHASE-2',
          category: Gstr3bItcCategory.importGoods,
          treatment: Gstr3bItcTreatment.eligible,
          tax: Gstr3bTaxAmounts(igst: 80, cgst: 40, sgst: 40),
        ),
        const Gstr3bItcEntry(
          documentReference: 'REVERSAL-2',
          category: Gstr3bItcCategory.other,
          treatment: Gstr3bItcTreatment.reversalRules38_42_43And17_5,
          tax: Gstr3bTaxAmounts(igst: 20, cgst: 10, sgst: 10),
        ),
      ]);

      expect(summary.netItc.igst, 60);
      expect(summary.netItc.cgst, 30);
      expect(summary.netItc.sgst, 30);
      expect(summary.negativeNetItcLiability.isZero, isTrue);
      expect(summary.requiresNegativeNetItcReview, isFalse);
    });

    test('keeps ineligible ITC outside available and net ITC totals', () {
      final summary = Gstr3bItcCalculator.summarize([
        const Gstr3bItcEntry(
          documentReference: 'INELIGIBLE-1',
          category: Gstr3bItcCategory.other,
          treatment: Gstr3bItcTreatment.ineligible,
          tax: Gstr3bTaxAmounts(igst: 18, cgst: 9),
        ),
      ]);

      expect(summary.ineligible.igst, 18);
      expect(summary.ineligible.cgst, 9);
      expect(summary.totalAvailable.isZero, isTrue);
      expect(summary.netItc.isZero, isTrue);
      expect(summary.negativeNetItcLiability.isZero, isTrue);
    });

    test('includes reclaimed previous reversal in other eligible ITC and disclosure', () {
      final summary = Gstr3bItcCalculator.summarize([
        const Gstr3bItcEntry(
          documentReference: 'RECLAIM-1',
          category: Gstr3bItcCategory.other,
          treatment: Gstr3bItcTreatment.reclaimedPreviousReversal,
          tax: Gstr3bTaxAmounts(igst: 12, cess: 2),
        ),
      ]);

      expect(summary.other.igst, 12);
      expect(summary.totalAvailable.igst, 12);
      expect(summary.reclaimedPreviousReversal.igst, 12);
      expect(summary.reclaimedPreviousReversal.cess, 2);
      expect(summary.netItc.igst, 12);
    });

    test('blocks draft preparation when an ITC item is pending review', () {
      final summary = Gstr3bItcCalculator.summarize([
        const Gstr3bItcEntry(
          documentReference: 'PENDING-1',
          category: Gstr3bItcCategory.other,
          treatment: Gstr3bItcTreatment.pendingReview,
          tax: Gstr3bTaxAmounts(igst: 18),
        ),
      ]);

      expect(summary.pendingReviewCount, 1);
      expect(summary.canPrepareDraft, isFalse);
    });

    test('reports duplicate document references instead of silently double counting', () {
      final summary = Gstr3bItcCalculator.summarize([
        const Gstr3bItcEntry(
          documentReference: 'DUP-1',
          category: Gstr3bItcCategory.other,
          treatment: Gstr3bItcTreatment.eligible,
          tax: Gstr3bTaxAmounts(igst: 10),
        ),
        const Gstr3bItcEntry(
          documentReference: ' dup-1 ',
          category: Gstr3bItcCategory.other,
          treatment: Gstr3bItcTreatment.eligible,
          tax: Gstr3bTaxAmounts(igst: 10),
        ),
      ]);

      expect(summary.issues, contains('Document reference DUP-1 is duplicated.'));
      expect(summary.canPrepareDraft, isFalse);
    });

    test('reports aggregate overflow instead of producing an apparently valid total', () {
      final summary = Gstr3bItcCalculator.summarize([
        const Gstr3bItcEntry(
          documentReference: 'LARGE-1',
          category: Gstr3bItcCategory.other,
          treatment: Gstr3bItcTreatment.eligible,
          tax: Gstr3bTaxAmounts(igst: 1e308),
        ),
        const Gstr3bItcEntry(
          documentReference: 'LARGE-2',
          category: Gstr3bItcCategory.other,
          treatment: Gstr3bItcTreatment.eligible,
          tax: Gstr3bTaxAmounts(igst: 1e308),
        ),
      ]);

      expect(
        summary.issues,
        contains('ITC totals exceed the supported numeric range; review the source amounts.'),
      );
      expect(summary.canPrepareDraft, isFalse);
    });
  });
}
