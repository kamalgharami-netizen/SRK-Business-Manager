import 'gst_gstr1_classification.dart';

/// Invoice-wise domestic sales classification CSV for review.
/// This is a management report, not a GSTN upload file.
class Gstr1InvoiceCsvExport {
  Gstr1InvoiceCsvExport._();

  static String build(
    Gstr1ClassificationSummary summary, {
    required String supplierGstin,
    required String periodStart,
    required String periodEnd,
  }) {
    final lines = <List<String>>[
      ['SRK Business Manager - GSTR-1 Invoice Classification'],
      ['Supplier GSTIN', supplierGstin],
      ['Period', '$periodStart to $periodEnd'],
      [],
      ['Invoice Number', 'Category', 'Invoice Value', 'Taxable Value', 'Total GST', 'Review Note'],
      for (final invoice in summary.invoices)
        [
          invoice.invoiceNumber,
          _category(invoice.category),
          _number(invoice.invoiceValue),
          _number(invoice.taxableValue),
          _number(invoice.taxAmount),
          invoice.reason ?? '',
        ],
    ];
    return '\uFEFF${lines.map((line) => line.map(_escape).join(',')).join('\r\n')}\r\n';
  }

  static String _category(Gstr1SupplyCategory category) => switch (category) {
    Gstr1SupplyCategory.b2b => 'B2B',
    Gstr1SupplyCategory.b2cl => 'B2CL',
    Gstr1SupplyCategory.b2cs => 'B2CS',
    Gstr1SupplyCategory.review => 'REVIEW',
  };

  static String _number(double value) => value.toStringAsFixed(2);

  static String _escape(String value) {
    if (value.contains(',') || value.contains('"') ||
        value.contains('\n') || value.contains('\r')) {
      return '"${value.replaceAll('"', '""')}"';
    }
    return value;
  }
}
