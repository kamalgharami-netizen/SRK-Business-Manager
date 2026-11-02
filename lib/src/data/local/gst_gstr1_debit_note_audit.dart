/// Management audit for locally recorded sales debit notes.
/// This is not a GSTN Table 9B mapping or filing-ready return.
class Gstr1DebitNoteAuditCsv {
  Gstr1DebitNoteAuditCsv._();

  static String build(
    List<Map<String, Object?>> rows, {
    required String supplierGstin,
    required String periodStart,
    required String periodEnd,
  }) {
    final lines = <List<String>>[
      ['SRK Business Manager - Sales Debit Note Audit (Manual Review)'],
      ['Supplier GSTIN', supplierGstin],
      ['Period', '$periodStart to $periodEnd'],
      [],
      ['Debit Note Number', 'Original Sales Invoice', 'Note Date', 'Reason',
       'Recipient', 'Recipient GSTIN', 'Place of Supply', 'Review Status',
       'Taxable Value', 'Total GST', 'CGST', 'SGST', 'IGST', 'Debit Note Value'],
      for (final row in rows)
        [
          _text(row['note_number']),
          _text(row['original_invoice_number']),
          _text(row['note_date']),
          _text(row['reason']),
          _text(row['party_name']),
          _text(row['party_gstin']),
          _text(row['place_of_supply']),
          _text(row['review_status']),
          _amount(row['taxable_value']),
          _amount(row['tax_amount']),
          _amount(row['cgst_amount']),
          _amount(row['sgst_amount']),
          _amount(row['igst_amount']),
          _amount(row['note_value']),
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
