import 'gst_gstr3b_itc.dart';

/// Exports a reviewable GSTR-3B Table 4 working paper.
/// This is not GSTN JSON and must not be treated as a filed return.
class Gstr3bTable4CsvExport {
  Gstr3bTable4CsvExport._();

  static String build({
    required String returnPeriod,
    required Gstr3bItcSummary summary,
  }) {
    if (!RegExp(r'^\d{4}-(0[1-9]|1[0-2])).hasMatch(returnPeriod)) {
      throw const FormatException('Return period must use YYYY-MM format.');
    }
    final rows = <List<String>>[
      ['SRK Business Manager - GSTR-3B Table 4 Working Paper'],
      ['Return Period', returnPeriod],
      ['Status', summary.canPrepareDraft ? 'PREPARATION_CHECKS_PASSED' : 'REVIEW_REQUIRED'],
      ['Pending Review Count', summary.pendingReviewCount.toString()],
      ['Data Issue Count', summary.issues.length.toString()],
      [],
      ['Table', 'Description', 'IGST', 'CGST', 'SGST', 'Cess'],
      _row('4(A)(1)', 'Import of Goods', summary.importGoods),
      _row('4(A)(2)', 'Import of Services', summary.importServices),
      _row('4(A)(3)', 'Reverse Charge', summary.reverseCharge),
      _row('4(A)(4)', 'Input Service Distributor', summary.inputServiceDistributor),
      _row('4(A)(5)', 'Other Eligible ITC / Reclaim', summary.other),
      _row('4(A)', 'Total ITC Available', summary.totalAvailable),
      _row('4(B)(1)', 'Rules 38/42/43 and Section 17(5) Reversal', summary.reversalRules),
      _row('4(B)(2)', 'Other Reversal', summary.reversalOther),
      _row('4(B)', 'Total ITC Reversed', summary.totalReversed),
      _row('4(C)', 'Net ITC (4A less 4B)', summary.netItc),
      _row('4(D)(1)', 'Reclaimed Previous Reversal', summary.reclaimedPreviousReversal),
      _row('4(D)(2)', 'Ineligible ITC', summary.ineligible),
      _row('REVIEW', 'Negative Net ITC Requiring Liability Review', summary.negativeNetItcLiability),
      [],
      ['Disclaimer', 'Internal working paper only; not GSTN upload JSON, tax advice or filing confirmation. Verify source documents, GSTR-2B and applicable law before filing.'],
      for (final issue in summary.issues) ['Data Issue', issue],
    ];
    return '\uFEFF${rows.map((row) => row.map(_escape).join(',')).join('\r\n')}\r\n';
  }

  static List<String> _row(String code, String description, Gstr3bTaxAmounts tax) =>
      [code, description, _amount(tax.igst), _amount(tax.cgst), _amount(tax.sgst), _amount(tax.cess)];

  static String _amount(double value) => value.toStringAsFixed(2);

  static String _escape(String value) {
    final safe = RegExp(r'^[\s]*[=+\-@]').hasMatch(value) ||
            value.startsWith('\t') || value.startsWith('\r')
        ? "'$value"
        : value;
    if (safe.contains(',') || safe.contains('"') ||
        safe.contains('\n') || safe.contains('\r')) {
      return '"${safe.replaceAll('"', '""')}"';
    }
    return safe;
  }
}
).hasMatch(returnPeriod)) {
      throw const FormatException('Return period must use YYYY-MM format.');
    }
    final rows = <List<String>>[
      ['SRK Business Manager - GSTR-3B Table 4 Working Paper'],
      ['Return Period', returnPeriod],
      ['Status', summary.canPrepareDraft ? 'PREPARATION_CHECKS_PASSED' : 'REVIEW_REQUIRED'],
      ['Pending Review Count', summary.pendingReviewCount.toString()],
      ['Data Issue Count', summary.issues.length.toString()],
      [],
      ['Table', 'Description', 'IGST', 'CGST', 'SGST', 'Cess'],
      _row('4(A)(1)', 'Import of Goods', summary.importGoods),
      _row('4(A)(2)', 'Import of Services', summary.importServices),
      _row('4(A)(3)', 'Reverse Charge', summary.reverseCharge),
      _row('4(A)(4)', 'Input Service Distributor', summary.inputServiceDistributor),
      _row('4(A)(5)', 'Other Eligible ITC / Reclaim', summary.other),
      _row('4(A)', 'Total ITC Available', summary.totalAvailable),
      _row('4(B)(1)', 'Rules 38/42/43 and Section 17(5) Reversal', summary.reversalRules),
      _row('4(B)(2)', 'Other Reversal', summary.reversalOther),
      _row('4(B)', 'Total ITC Reversed', summary.totalReversed),
      _row('4(C)', 'Net ITC (4A less 4B)', summary.netItc),
      _row('4(D)(1)', 'Reclaimed Previous Reversal', summary.reclaimedPreviousReversal),
      _row('4(D)(2)', 'Ineligible ITC', summary.ineligible),
      _row('REVIEW', 'Negative Net ITC Requiring Liability Review', summary.negativeNetItcLiability),
      [],
      ['Disclaimer', 'Internal working paper only; not GSTN upload JSON, tax advice or filing confirmation. Verify source documents, GSTR-2B and applicable law before filing.'],
      for (final issue in summary.issues) ['Data Issue', issue],
    ];
    return '\uFEFF${rows.map((row) => row.map(_escape).join(',')).join('\r\n')}\r\n';
  }

  static List<String> _row(String code, String description, Gstr3bTaxAmounts tax) =>
      [code, description, _amount(tax.igst), _amount(tax.cgst), _amount(tax.sgst), _amount(tax.cess)];

  static String _amount(double value) => value.toStringAsFixed(2);

  static String _escape(String value) {
    final safe = RegExp(r'^[\s]*[=+\-@]').hasMatch(value) ||
            value.startsWith('\t') || value.startsWith('\r')
        ? "'$value"
        : value;
    if (safe.contains(',') || safe.contains('"') ||
        safe.contains('\n') || safe.contains('\r')) {
      return '"${safe.replaceAll('"', '""')}"';
    }
    return safe;
  }
}
