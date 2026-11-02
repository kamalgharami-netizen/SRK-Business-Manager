/// Spreadsheet-friendly export of the local RCM audit history.
/// This is a management record, not a GSTN upload or statutory filing file.
class GstrRcmAuditCsvExport {
  GstrRcmAuditCsvExport._();

  static String build(
    List<Map<String, Object?>> rows, {
    required String returnPeriod,
  }) {
    final lines = <List<String>>[
      ['SRK Business Manager - RCM Audit History'],
      ['Return Period', returnPeriod],
      [],
      [
        'Changed At', 'Entity Type', 'Record ID', 'Action', 'Document Reference',
        'Payment Date', 'Cash Ledger Reference', 'Challan Reference',
        'Taxable Value', 'IGST', 'CGST', 'SGST', 'Cess', 'Notes',
      ],
      for (final row in rows)
        [
          _text(row['changed_at']),
          _text(row['entity_type']),
          _text(row['record_id']),
          _text(row['action']),
          _text(row['document_reference']),
          _text(row['payment_date']),
          _text(row['cash_ledger_reference']),
          _text(row['challan_reference']),
          _number(row['taxable_value']),
          _number(row['igst']),
          _number(row['cgst']),
          _number(row['sgst']),
          _number(row['cess']),
          _text(row['notes']),
        ],
    ];
    return '\uFEFF\${lines.map((line) => line.map(_escape).join(',')).join('\r\n')}\r\n';
  }

  static String _text(Object? value) => value?.toString() ?? '';

  static String _number(Object? value) =>
      value is num ? value.toStringAsFixed(2) : '';

  static String _escape(String value) {
    final safeValue = _protectSpreadsheetFormula(value);
    if (safeValue.contains(',') || safeValue.contains('"') ||
        safeValue.contains('\n') || safeValue.contains('\r')) {
      return '"\${safeValue.replaceAll('"', '""')}"';
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
