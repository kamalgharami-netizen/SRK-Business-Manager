import 'gst_gstr1_hsn_summary.dart';

/// Creates a spreadsheet-friendly CSV for the locally calculated HSN/rate summary.
/// This is a management report, not a GSTN upload file.
class Gstr1HsnCsvExport {
  Gstr1HsnCsvExport._();

  static String build(
    List<Gstr1HsnRateSummary> rows, {
    required String supplierGstin,
    required String periodStart,
    required String periodEnd,
  }) {
    final lines = <List<String>>[
      ['SRK Business Manager - GSTR-1 HSN/SAC Summary'],
      ['Supplier GSTIN', supplierGstin],
      ['Period', '$periodStart to $periodEnd'],
      [],
      ['HSN/SAC', 'GST Rate (%)', 'Unit (as entered)', 'Quantity', 'Total Value', 'Taxable Value', 'Total GST', 'CGST', 'SGST', 'IGST'],
      for (final row in rows)
        [row.hsnSac, _number(row.gstRate), row.unit, _number(row.quantity),
          _number(row.totalValue), _number(row.taxableValue), _number(row.taxAmount),
          _number(row.cgst), _number(row.sgst), _number(row.igst)],
    ];
    return '\uFEFF${lines.map((line) => line.map(_escape).join(',')).join('\r\n')}\r\n';
  }

  static String _number(double value) => value.toStringAsFixed(2);

  static String _escape(String value) {
    final safeValue = _protectSpreadsheetFormula(value);
    if (safeValue.contains(',') || safeValue.contains('"') ||
        safeValue.contains('\n') || safeValue.contains('\r')) {
      return '"${safeValue.replaceAll('"', '""')}"';
    }
    return safeValue;
  }

  // Prevent spreadsheet applications from evaluating untrusted text as a formula.
  static String _protectSpreadsheetFormula(String value) {
    if (RegExp(r'^[\s]*[=+\-@]').hasMatch(value) ||
        value.startsWith('\t') || value.startsWith('\r')) {
      return "'$value";
    }
    return value;
  }
}
