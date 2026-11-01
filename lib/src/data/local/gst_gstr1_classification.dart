import '../indian_states.dart';

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

  /// GSTN B2CL threshold changed from ₹2.5 lakh to ₹1 lakh
  /// for return periods beginning August 2024.
  static double b2clThresholdForReturnPeriod(DateTime returnPeriod) =>
      returnPeriod.isBefore(DateTime(2024, 8)) ? 250000 : 100000;

  static Gstr1ClassificationSummary classify(
    List<Map<String, Object?>> invoices, {
    required String supplierState,
    required DateTime returnPeriod,
  }) {
    final b2clThreshold = b2clThresholdForReturnPeriod(returnPeriod);
    final supplier = supplierState.trim();
    final results = <Gstr1InvoiceClassification>[];

    for (final invoice in invoices) {
      final number = (invoice['invoice_number'] as String? ?? '').trim();
      final recipientGstin =
          (invoice['party_gstin'] as String? ?? '').trim().toUpperCase();
      final recipientState = (invoice['party_state'] as String? ?? '').trim();
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
        results.add(_review(number, 'Invoice values are missing, non-finite or negative.'));
        continue;
      }
      if (number.isEmpty) {
        results.add(_review(number, 'Invoice number is missing.',
            invoiceValue, taxableValue, taxAmount));
        continue;
      }

      // This classifier currently handles domestic supplies only. Do not
      // silently classify a B2B invoice when supplier state or POS is unknown.
      if (!IndianStates.isKnown(supplier) ||
          !IndianStates.isKnown(placeOfSupply)) {
        results.add(_review(number,
            'Supplier state or place of supply is missing or invalid.',
            invoiceValue, taxableValue, taxAmount));
        continue;
      }

      if (recipientGstin.isNotEmpty) {
        if (!_isValidGstinFormat(recipientGstin)) {
          results.add(_review(number, 'Recipient GSTIN format is invalid.',
              invoiceValue, taxableValue, taxAmount));
          continue;
        }
        if (!IndianStates.isKnown(recipientState) ||
            !IndianStates.gstinMatchesState(recipientGstin, recipientState)) {
          results.add(_review(number,
              'Recipient GSTIN does not match a valid recipient state.',
              invoiceValue, taxableValue, taxAmount));
          continue;
        }
        results.add(Gstr1InvoiceClassification(
          invoiceNumber: number,
          category: Gstr1SupplyCategory.b2b,
          invoiceValue: invoiceValue,
          taxableValue: taxableValue,
          taxAmount: taxAmount,
        ));
        continue;
      }

      final interState =
          IndianStates.normalizeState(supplier) !=
          IndianStates.normalizeState(placeOfSupply);
      final category =
          interState && invoiceValue > b2clThreshold
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

  static Gstr1InvoiceClassification _review(
    String number,
    String reason, [
    double invoiceValue = 0,
    double taxableValue = 0,
    double taxAmount = 0,
  ]) => Gstr1InvoiceClassification(
        invoiceNumber: number,
        category: Gstr1SupplyCategory.review,
        invoiceValue: invoiceValue,
        taxableValue: taxableValue,
        taxAmount: taxAmount,
        reason: reason,
      );

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
