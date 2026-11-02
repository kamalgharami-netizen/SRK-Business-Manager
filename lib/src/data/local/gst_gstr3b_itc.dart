/// Explicitly classified input-tax-credit data for GSTR-3B Table 4 preparation.
///
/// This is a calculation/readiness layer, not a GSTN filing utility. Entries
/// must be reviewed against purchase documents and GSTR-2B before use.
enum Gstr3bItcCategory {
  importGoods,
  importServices,
  reverseCharge,
  inputServiceDistributor,
  other,
}

enum Gstr3bItcTreatment {
  eligible,
  ineligible,
  reversalRules38_42_43And17_5,
  reversalOther,
  reclaimedPreviousReversal,
  pendingReview,
}

/// Tax amounts are stored separately by statutory tax head.
class Gstr3bTaxAmounts {
  const Gstr3bTaxAmounts({
    this.igst = 0,
    this.cgst = 0,
    this.sgst = 0,
    this.cess = 0,
  });

  final double igst;
  final double cgst;
  final double sgst;
  final double cess;

  bool get isValid =>
      _valid(igst) && _valid(cgst) && _valid(sgst) && _valid(cess);

  bool get isZero => igst == 0 && cgst == 0 && sgst == 0 && cess == 0;

  Gstr3bTaxAmounts operator +(Gstr3bTaxAmounts other) => Gstr3bTaxAmounts(
        igst: igst + other.igst,
        cgst: cgst + other.cgst,
        sgst: sgst + other.sgst,
        cess: cess + other.cess,
      );

  Gstr3bTaxAmounts operator -(Gstr3bTaxAmounts other) => Gstr3bTaxAmounts(
        igst: igst - other.igst,
        cgst: cgst - other.cgst,
        sgst: sgst - other.sgst,
        cess: cess - other.cess,
      );

  static bool _valid(double value) => value.isFinite && value >= 0;
}

/// One assessed purchase-document ITC component.
///
/// Use a unique document reference per assessed document/adjustment. A
/// document must not be entered twice in the same period.
class Gstr3bItcEntry {
  const Gstr3bItcEntry({
    required this.documentReference,
    required this.category,
    required this.treatment,
    required this.tax,
  });

  final String documentReference;
  final Gstr3bItcCategory category;
  final Gstr3bItcTreatment treatment;
  final Gstr3bTaxAmounts tax;
}

class Gstr3bItcSummary {
  const Gstr3bItcSummary({
    required this.importGoods,
    required this.importServices,
    required this.reverseCharge,
    required this.inputServiceDistributor,
    required this.other,
    required this.reversalRules,
    required this.reversalOther,
    required this.ineligible,
    required this.reclaimedPreviousReversal,
    required this.pendingReviewCount,
    required this.issues,
  });

  /// Table 4(A)(1) to 4(A)(5).
  final Gstr3bTaxAmounts importGoods;
  final Gstr3bTaxAmounts importServices;
  final Gstr3bTaxAmounts reverseCharge;
  final Gstr3bTaxAmounts inputServiceDistributor;
  final Gstr3bTaxAmounts other;

  /// Table 4(B)(1) and 4(B)(2).
  final Gstr3bTaxAmounts reversalRules;
  final Gstr3bTaxAmounts reversalOther;

  /// Table 4(D)(2), not included in net ITC.
  final Gstr3bTaxAmounts ineligible;

  /// Table 4(D)(1) disclosure; reclaimed amount is also included in 4(A)(5).
  final Gstr3bTaxAmounts reclaimedPreviousReversal;

  final int pendingReviewCount;
  final List<String> issues;

  Gstr3bTaxAmounts get totalAvailable =>
      importGoods +
      importServices +
      reverseCharge +
      inputServiceDistributor +
      other;

  Gstr3bTaxAmounts get totalReversed => reversalRules + reversalOther;

  /// Table 4(C) = Table 4(A) - Table 4(B). A negative result is retained.
  Gstr3bTaxAmounts get netItc => totalAvailable - totalReversed;

  /// Negative Table 4(C) amounts are separately disclosed as liability.
  /// Values are returned as positive amounts by tax head for clear reporting.
  Gstr3bTaxAmounts get negativeNetItcLiability {
    final value = netItc;
    return Gstr3bTaxAmounts(
      igst: value.igst < 0 ? -value.igst : 0,
      cgst: value.cgst < 0 ? -value.cgst : 0,
      sgst: value.sgst < 0 ? -value.sgst : 0,
      cess: value.cess < 0 ? -value.cess : 0,
    );
  }

  bool get canPrepareDraft => issues.isEmpty && pendingReviewCount == 0;
}

class Gstr3bItcCalculator {
  Gstr3bItcCalculator._();

  static Gstr3bItcSummary summarize(Iterable<Gstr3bItcEntry> entries) {
    var importGoods = const Gstr3bTaxAmounts();
    var importServices = const Gstr3bTaxAmounts();
    var reverseCharge = const Gstr3bTaxAmounts();
    var inputServiceDistributor = const Gstr3bTaxAmounts();
    var other = const Gstr3bTaxAmounts();
    var reversalRules = const Gstr3bTaxAmounts();
    var reversalOther = const Gstr3bTaxAmounts();
    var ineligible = const Gstr3bTaxAmounts();
    var reclaimed = const Gstr3bTaxAmounts();
    var pending = 0;
    final issues = <String>[];
    final seen = <String>{};

    for (final entry in entries) {
      final reference = entry.documentReference.trim().toUpperCase();
      if (reference.isEmpty) {
        issues.add('An ITC entry has no document reference.');
      } else if (!seen.add(reference)) {
        issues.add('Document reference $reference is duplicated.');
      }

      if (!entry.tax.isValid) {
        issues.add('Document $reference contains a negative or non-finite tax amount.');
        continue;
      }

      switch (entry.treatment) {
        case Gstr3bItcTreatment.pendingReview:
          pending++;
          break;
        case Gstr3bItcTreatment.ineligible:
          ineligible = ineligible + entry.tax;
          break;
        case Gstr3bItcTreatment.reversalRules38_42_43And17_5:
          reversalRules = reversalRules + entry.tax;
          break;
        case Gstr3bItcTreatment.reversalOther:
          reversalOther = reversalOther + entry.tax;
          break;
        case Gstr3bItcTreatment.reclaimedPreviousReversal:
          reclaimed = reclaimed + entry.tax;
          other = other + entry.tax;
          break;
        case Gstr3bItcTreatment.eligible:
          switch (entry.category) {
            case Gstr3bItcCategory.importGoods:
              importGoods = importGoods + entry.tax;
              break;
            case Gstr3bItcCategory.importServices:
              importServices = importServices + entry.tax;
              break;
            case Gstr3bItcCategory.reverseCharge:
              reverseCharge = reverseCharge + entry.tax;
              break;
            case Gstr3bItcCategory.inputServiceDistributor:
              inputServiceDistributor = inputServiceDistributor + entry.tax;
              break;
            case Gstr3bItcCategory.other:
              other = other + entry.tax;
              break;
          }
          break;
      }
    }

    final aggregateAmounts = [
      importGoods, importServices, reverseCharge, inputServiceDistributor,
      other, reversalRules, reversalOther, ineligible, reclaimed,
    ];
    if (aggregateAmounts.any((amount) =>
        !amount.igst.isFinite || !amount.cgst.isFinite ||
        !amount.sgst.isFinite || !amount.cess.isFinite)) {
      issues.add('ITC totals exceed the supported numeric range; review the source amounts.');
    }

    return Gstr3bItcSummary(
      importGoods: importGoods,
      importServices: importServices,
      reverseCharge: reverseCharge,
      inputServiceDistributor: inputServiceDistributor,
      other: other,
      reversalRules: reversalRules,
      reversalOther: reversalOther,
      ineligible: ineligible,
      reclaimedPreviousReversal: reclaimed,
      pendingReviewCount: pending,
      issues: List.unmodifiable(issues),
    );
  }
}
