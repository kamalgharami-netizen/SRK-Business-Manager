import 'package:flutter_test/flutter_test.dart';
import 'package:srk_business_manager/src/data/local/gst_gstr3b_itc.dart';

void main() {
  group('Gstr3bItcCalculator', () {
    const taxA = Gstr3bTaxAmounts(igst: 18, cgst: 9, sgst: 9, cess: 2);

    test('groups eligible ITC by Table 4(A) category and calculates net ITC', () {
      final summary = Gstr3bItcCalculator.summarize([
        const Gstr3bItcEntry(
          documentReference: 'IMP-G-01',
          category: Gstr3bItcCategory.importGoods,
          treatment: Gstr3bItcTreatment.eligible,
          tax: taxA,
        ),
        const Gstr3bItcEntry(
          documentReference: 'RCM-01',
          category: Gstr3bItcCategory.reverseCharge,
          treatment: Gstr3bItcTreatment.eligible,
          tax: Gstr3bTaxAmounts(cgst: 5, sgst: 5),
        ),
        const Gstr3bItcEntry(
          documentReference: 'REV-01',
          category: Gstr3bItcCategory.other,
          treatment: Gstr3bItcTreatment.reversalOther,
          tax: Gstr3bTaxAmounts(igst: 3, cgst: 1, sgst: 1),
        ),
      ]);

      expect(summary.importGoods.igst, 18);
      expect(summary.reverseCharge.cgst, 5);
      expect(summary.totalAvailable.igst, 18);
      expect(summary.totalAvailable.cgst, 14);
      expect(summary.totalReversed.igst, 3);
      expect(summary.netItc.igst, 15);
      expect(summary.netItc.cgst, 13);
      expect(summary.canPrepareDraft, isTrue);
    });

    test('reports ineligible ITC separately and excludes it from net ITC', () {
      final summary = Gstr3bItcCalculator.summarize([
        const Gstr3bItcEntry(
          documentReference: 'INEL-01',
          category: Gstr3bItcCategory.other,
          treatment: Gstr3bItcTreatment.ineligible,
          tax: taxA,
        ),
      ]);

      expect(summary.ineligible.igst, 18);
      expect(summary.totalAvailable.isZero, isTrue);
      expect(summary.netItc.isZero, isTrue);
    });

    test('includes reclaimed ITC in 4(A)(5) and discloses it in 4(D)(1)', () {
      final summary = Gstr3bItcCalculator.summarize([
        const Gstr3bItcEntry(
          documentReference: 'RECLAIM-01',
          category: Gstr3bItcCategory.other,
          treatment: Gstr3bItcTreatment.reclaimedPreviousReversal,
          tax: taxA,
        ),
      ]);

      expect(summary.other.igst, 18);
      expect(summary.reclaimedPreviousReversal.igst, 18);
      expect(summary.totalAvailable.igst, 18);
    });

    test('blocks draft readiness while any document is pending review', () {
      final summary = Gstr3bItcCalculator.summarize([
        const Gstr3bItcEntry(
          documentReference: 'PENDING-01',
          category: Gstr3bItcCategory.other,
          treatment: Gstr3bItcTreatment.pendingReview,
          tax: taxA,
        ),
      ]);

      expect(summary.pendingReviewCount, 1);
      expect(summary.canPrepareDraft, isFalse);
    });

    test('rejects duplicate document references case-insensitively', () {
      final summary = Gstr3bItcCalculator.summarize([
        const Gstr3bItcEntry(
          documentReference: 'BILL-01',
          category: Gstr3bItcCategory.other,
          treatment: Gstr3bItcTreatment.eligible,
          tax: taxA,
        ),
        const Gstr3bItcEntry(
          documentReference: 'bill-01',
          category: Gstr3bItcCategory.other,
          treatment: Gstr3bItcTreatment.eligible,
          tax: taxA,
        ),
      ]);

      expect(summary.issues, hasLength(1));
      expect(summary.canPrepareDraft, isFalse);
    });

    test('rejects negative and non-finite tax components', () {
      final summary = Gstr3bItcCalculator.summarize([
        const Gstr3bItcEntry(
          documentReference: 'BAD-01',
          category: Gstr3bItcCategory.other,
          treatment: Gstr3bItcTreatment.eligible,
          tax: Gstr3bTaxAmounts(igst: -1),
        ),
        const Gstr3bItcEntry(
          documentReference: 'BAD-02',
          category: Gstr3bItcCategory.other,
          treatment: Gstr3bItcTreatment.eligible,
          tax: Gstr3bTaxAmounts(cgst: double.infinity),
        ),
      ]);

      expect(summary.issues, hasLength(2));
      expect(summary.canPrepareDraft, isFalse);
    });

    test('retains negative net ITC instead of silently clamping to zero', () {
      final summary = Gstr3bItcCalculator.summarize([
        const Gstr3bItcEntry(
          documentReference: 'REV-02',
          category: Gstr3bItcCategory.other,
          treatment: Gstr3bItcTreatment.reversalOther,
          tax: Gstr3bTaxAmounts(igst: 25),
        ),
      ]);

      expect(summary.netItc.igst, -25);
    });

    test('reports negative Table 4(C) amounts separately as liability', () {
      final summary = Gstr3bItcCalculator.summarize([
        const Gstr3bItcEntry(
          documentReference: 'REV-03',
          category: Gstr3bItcCategory.other,
          treatment: Gstr3bItcTreatment.reversalOther,
          tax: Gstr3bTaxAmounts(igst: 25, cgst: 4),
        ),
        const Gstr3bItcEntry(
          documentReference: 'ITC-03',
          category: Gstr3bItcCategory.other,
          treatment: Gstr3bItcTreatment.eligible,
          tax: Gstr3bTaxAmounts(igst: 10),
        ),
      ]);

      expect(summary.netItc.igst, -15);
      expect(summary.negativeNetItcLiability.igst, 15);
      expect(summary.negativeNetItcLiability.cgst, 4);
      expect(summary.negativeNetItcLiability.sgst, 0);
    });

    test('blocks draft readiness when individually valid amounts overflow an ITC total', () {
      final largeAmount = double.maxFinite;
      final summary = Gstr3bItcCalculator.summarize([
        Gstr3bItcEntry(
          documentReference: 'LARGE-01',
          category: Gstr3bItcCategory.other,
          treatment: Gstr3bItcTreatment.eligible,
          tax: Gstr3bTaxAmounts(igst: largeAmount),
        ),
        Gstr3bItcEntry(
          documentReference: 'LARGE-02',
          category: Gstr3bItcCategory.other,
          treatment: Gstr3bItcTreatment.eligible,
          tax: Gstr3bTaxAmounts(igst: largeAmount),
        ),
      ]);

      expect(summary.issues, contains(
        'ITC totals exceed the supported numeric range; review the source amounts.',
      ));
      expect(summary.canPrepareDraft, isFalse);
    });

    test('flags entries without a source document reference', () {
      final summary = Gstr3bItcCalculator.summarize([
        const Gstr3bItcEntry(
          documentReference: ' ',
          category: Gstr3bItcCategory.other,
          treatment: Gstr3bItcTreatment.eligible,
          tax: taxA,
        ),
      ]);

      expect(summary.issues, hasLength(1));
      expect(summary.canPrepareDraft, isFalse);
    });
  });
}
