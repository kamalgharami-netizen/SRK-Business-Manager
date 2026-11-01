/// Core B2B/B2C classification for locally recorded domestic outward invoices.
/// This is a preparation aid, not a complete GSTR-1 table mapper or GSTN export.
enum Gstr1SupplyCategory { b2b, b2cl, b2cs, review }

class Gstr1InvoiceClassification {
  const Gstr1InvoiceClassification({
    required this.invoiceNumber,
    required this.category,
    required this.invoiceValue,
    required this.taxableValue,
    required this.taxAmount,
    this.reason,
  });

  final String invoiceNumber;
  final Gstr1SupplyCategory category;
  final double invoiceValue;
  final double taxableValue;
  final double taxAmount;
  final String? reason;
}

class Gstr1ClassificationSummary {
  const Gstr1ClassificationSummary(this.invoices);

  final List<Gstr1InvoiceClassification> invoices;

  int count(Gstr1SupplyCategory category) =>
      invoices.where((invoice) => invoice.category == category).length;

  double invoiceValue(Gstr1SupplyCategory category) => invoices
      .where((invoice) => invoice.category == category)
      .fold(0, (total, invoice) => total + invoice.invoiceValue);

  double taxableValue(Gstr1SupplyCategory category) => invoices
      .where((invoice) => invoice.category == category)
      .fold(0, (total, invoice) => total + invoice.taxableValue);

  double taxAmount(Gstr1SupplyCategory category) => invoices
      .where((invoice) => invoice.category == category)
      .fold(0, (total, invoice) => total + invoice.taxAmount);
}

class Gstr1DomesticClassifier {
  Gstr1DomesticClassifier._();

  /// The current configured threshold is ₹1,00,000 for inter-State B2C Large.
  /// Verify the applicable GSTN rules before relying on statutory filing.
  static const double b2clInvoiceValueThreshold = 100000;

  static Gstr1ClassificationSummary classify(
    List<Map<String, Object?>> invoices, {
    required String supplierState,
  }) {
    final normalizedSupplierState = supplierState.trim();
    final results = <Gstr1InvoiceClassification>[];

    for (final invoice in invoices) {
      final number = (invoice['invoice_number'] as String? ?? '').trim();
      final recipientGstin =
          (invoice['party_gstin'] as String? ?? '').trim().toUpperCase();
      final placeOfSupply =
          (invoice['place_of_supply'] as String? ?? '').trim();
      final invoiceValue = _number(invoice['invoice_value']);
      final taxableValue = _number(invoice['taxable_value']);
      final taxAmount = _number(invoice['tax_amount']);

      if (invoiceValue == null ||
          taxableValue == null ||
          taxAmount == null ||
          invoiceValue < 0 ||
          taxableValue < 0 ||
          taxAmount < 0) {
        results.add(Gstr1InvoiceClassification(
          invoiceNumber: number,
          category: Gstr1SupplyCategory.review,
          invoiceValue: 0,
          taxableValue: 0,
          taxAmount: 0,
          reason: 'Invoice values are missing, non-finite or negative.',
        ));
        continue;
      }

      if (number.isEmpty) {
        results.add(Gstr1InvoiceClassification(
          invoiceNumber: number,
          category: Gstr1SupplyCategory.review,
          invoiceValue: invoiceValue,
          taxableValue: taxableValue,
          taxAmount: taxAmount,
          reason: 'Invoice number is missing.',
        ));
        continue;
      }

      if (recipientGstin.isNotEmpty && !_isValidGstinFormat(recipientGstin)) {
        results.add(Gstr1InvoiceClassification(
          invoiceNumber: number,
          category: Gstr1SupplyCategory.review,
          invoiceValue: invoiceValue,
          taxableValue: taxableValue,
          taxAmount: taxAmount,
          reason: 'Recipient GSTIN format is invalid.',
        ));
        continue;
      }

      if (recipientGstin.isNotEmpty) {
        results.add(Gstr1InvoiceClassification(
          invoiceNumber: number,
          category: Gstr1SupplyCategory.b2b,
          invoiceValue: invoiceValue,
          taxableValue: taxableValue,
          taxAmount: taxAmount,
        ));
        continue;
      }

      if (!IndianStateCheck.isKnown(normalizedSupplierState) ||
          !IndianStateCheck.isKnown(placeOfSupply)) {
        results.add(Gstr1InvoiceClassification(
          invoiceNumber: number,
          category: Gstr1SupplyCategory.review,
          invoiceValue: invoiceValue,
          taxableValue: taxableValue,
          taxAmount: taxAmount,
          reason: 'Supplier state or place of supply is missing or invalid.',
        ));
        continue;
      }

      final interState = _normalizeState(normalizedSupplierState) !=
          _normalizeState(placeOfSupply);
      final category =
          interState && invoiceValue > b2clInvoiceValueThreshold
              ? Gstr1SupplyCategory.b2cl
              : Gstr1SupplyCategory.b2cs;
      results.add(Gstr1InvoiceClassification(
        invoiceNumber: number,
        category: category,
        invoiceValue: invoiceValue,
        taxableValue: taxableValue,
        taxAmount: taxAmount,
      ));
    }

    return Gstr1ClassificationSummary(List.unmodifiable(results));
  }

  static String _normalizeState(String value) =>
      value.trim().replaceAll(RegExp(r'\\s+'), ' ').toLowerCase();

  /// Checks GSTIN structure only; checksum and registration status are not
  /// verified against the GST portal.
  static bool _isValidGstinFormat(String value) => RegExp(
        r'^[0-9]{2}[A-Z]{5}[0-9]{4}[A-Z][1-9A-Z]Z[0-9A-Z]$',
      ).hasMatch(value);

  static double? _number(Object? value) {
    if (value is! num) return null;
    final result = value.toDouble();
    return result.isFinite ? result : null;
  }
}

/// Kept local to avoid coupling this pure classification helper to UI code.
class IndianStateCheck {
  static const _states = {
    'Andhra Pradesh', 'Arunachal Pradesh', 'Assam', 'Bihar',
    'Chhattisgarh', 'Goa', 'Gujarat', 'Haryana', 'Himachal Pradesh',
    'Jharkhand', 'Karnataka', 'Kerala', 'Madhya Pradesh', 'Maharashtra',
    'Manipur', 'Meghalaya', 'Mizoram', 'Nagaland', 'Odisha', 'Punjab',
    'Rajasthan', 'Sikkim', 'Tamil Nadu', 'Telangana', 'Tripura',
    'Uttar Pradesh', 'Uttarakhand', 'West Bengal',
    'Andaman and Nicobar Islands', 'Chandigarh',
    'Dadra and Nagar Haveli and Daman and Diu', 'Delhi',
    'Jammu and Kashmir', 'Ladakh', 'Lakshadweep', 'Puducherry',
  };

  static bool isKnown(String state) => _states.contains(state);
}
