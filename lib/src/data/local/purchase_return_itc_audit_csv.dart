/// Management audit for locally recorded purchase returns and potential ITC reversal.
/// This is a review aid only; it does not determine statutory ITC eligibility or post reversals.
class PurchaseReturnItcAuditCsv {
  PurchaseReturnItcAuditCsv._();

  static String build(
    List<Map<String, Object?>> rows, {
    required String recipientGstin,
    required String periodStart,
    required String periodEnd,
  }) {
    final lines = <List<String>>[
      ['SRK Business Manager - Purchase Return / ITC Reversal Audit (Manual Review)'],
      ['Recipient GSTIN', recipientGstin],
      ['Period', '$periodStart to $periodEnd'],
      [],
      ['Return Number', 'Original Purchase Invoice', 'Return Date', 'Review Status',
       'Return Value', 'Taxable Value', 'GST Amount', 'CGST', 'SGST', 'IGST'],
      for (final row in rows)
        [
          _text(row['return_number']),
          _text(row['original_invoice_number']),
          _text(row['return_date']),
          _text(row['review_status']),
          _amount(row['return_value']),
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
