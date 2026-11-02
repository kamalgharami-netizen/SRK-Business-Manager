/// Exports recorded RCM liabilities and linked cash payments for review.
/// This is a management reconciliation, not a GSTN filing document.
class GstrRcmReconciliationCsvExport {
  GstrRcmReconciliationCsvExport._();

  static String build(
    List<Map<String, Object?>> rows, {
    required String returnPeriod,
  }) {
    if (!RegExp(r'^\\d{4}-(0[1-9]|1[0-2])$').hasMatch(returnPeriod)) {
      throw const FormatException('Return period must use YYYY-MM format.');
    }
    final output = <List<String>>[
      ['SRK Business Manager - RCM Liability Reconciliation'],
      ['Return Period', returnPeriod],
      [],
      [
        'Document Reference', 'Supplier', 'Taxable Value',
        'IGST Liability', 'IGST Paid', 'IGST Outstanding',
        'CGST Liability', 'CGST Paid', 'CGST Outstanding',
        'SGST Liability', 'SGST Paid', 'SGST Outstanding',
        'Cess Liability', 'Cess Paid', 'Cess Outstanding',
        'Cash Payment Count', 'Cash Payment References', 'Review Status',
      ],
    ];
    for (final row in rows) {
      double amount(String key) {
        final value = row[key];
        if (value == null) return 0;
        if (value is! num || !value.toDouble().isFinite || value.toDouble() < 0) {
          throw FormatException('Invalid non-negative amount in $key.');
        }
        return value.toDouble();
      }
      final igstDue = amount('igst') - amount('igst_paid');
      final cgstDue = amount('cgst') - amount('cgst_paid');
      final sgstDue = amount('sgst') - amount('sgst_paid');
      final cessDue = amount('cess') - amount('cess_paid');
      final overpaid = [igstDue, cgstDue, sgstDue, cessDue].any((v) => v < -0.005);
      output.add([
        _text(row['document_reference']),
        _text(row['supplier_name']),
        _amount(amount('taxable_value')),
        _amount(amount('igst')), _amount(amount('igst_paid')), _amount(igstDue),
        _amount(amount('cgst')), _amount(amount('cgst_paid')), _amount(cgstDue),
        _amount(amount('sgst')), _amount(amount('sgst_paid')), _amount(sgstDue),
        _amount(amount('cess')), _amount(amount('cess_paid')), _amount(cessDue),
        (row['payment_count'] as num?)?.toInt().toString() ?? '0',
        _text(row['payment_references']),
        overpaid ? 'OVERPAYMENT_REVIEW_REQUIRED' : 'MANUAL_CHALLAN_VERIFICATION_REQUIRED',
      ]);
    }
    output.add([]);
    output.add([
      'Disclaimer',
      'Management reconciliation only. Verify challans, cash ledger and statutory RCM applicability before filing.'
    ]);
    return '\uFEFF${output.map((row) => row.map(_escape).join(',')).join('\\r\\n')}\\r\\n';
  }

  static String _text(Object? value) => value?.toString() ?? '';
  static String _amount(double value) => value.toStringAsFixed(2);
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
