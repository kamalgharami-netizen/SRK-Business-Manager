/// Management audit for locally recorded sales returns used as credit notes.
/// This deliberately does not claim GSTN Table 9B mapping or tax eligibility.
class Gstr1CreditNoteAuditCsv {
  Gstr1CreditNoteAuditCsv._();

  static String build(
    List<Map<String, Object?>> rows, {
    required String supplierGstin,
    required String periodStart,
    required String periodEnd,
  }) {
    final lines = <List<String>>[
      ['SRK Business Manager - Credit Note Audit (Manual Review)'],
      ['Supplier GSTIN', supplierGstin],
      ['Period', '$periodStart to $periodEnd'],
      [],
      ['Note Number', 'Original Invoice Number', 'Note Date', 'Review Status',
       'Note Value', 'Taxable Value', 'Total GST', 'CGST', 'SGST', 'IGST'],
      for (final row in rows)
        [
          _text(row['note_number']),
          _text(row['original_invoice_number']),
          _text(row['note_date']),
          _text(row['review_status']),
          _amount(row['note_value']),
          _amount(row['taxable_value']),
          _amount(row['tax_amount']),
          _amount(row['cgst_amount']),
          _amount(row['sgst_amount']),
          _amount(row['igst_amount']),
        ],
    ];
    return '\uFEFF${lines.map((line) => line.map(_escape).join(',')).join('\r\n')}\r\n';
  }

  static String _text(Object? value) => value?.toString() ?? '';
  static String _amount(Object? value) =>
      value is num && value.isFinite ? value.toStringAsFixed(2) : '0.00';

  static String _escape(String value) {
    final safe = RegExp(r'^[\\s]*[=+\\-@]').hasMatch(value) ||
            value.startsWith('\\t') || value.startsWith('\\r')
        ? "'$value"
        : value;
    if (safe.contains(',') || safe.contains('"') ||
        safe.contains('\\n') || safe.contains('\\r')) {
      return '"${safe.replaceAll('"', '""')}"';
    }
    return safe;
  }
}
