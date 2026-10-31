/// Centralised Indian GST amount calculation for invoice line items.
/// Monetary values are rounded to the nearest paise before aggregation.
class GstBreakdown {
  const GstBreakdown({required this.taxableValue, required this.taxRate, required this.taxAmount, required this.cgstAmount, required this.sgstAmount, required this.igstAmount});
  final double taxableValue;
  final double taxRate;
  final double taxAmount;
  final double cgstAmount;
  final double sgstAmount;
  final double igstAmount;
  double get lineTotal => GstCalculator.roundMoney(taxableValue + taxAmount);
}

class GstCalculator {
  GstCalculator._();

  static double roundMoney(double value) {
    if (!value.isFinite) throw ArgumentError.value(value, 'value', 'Must be finite.');
    return (value * 100).roundToDouble() / 100;
  }

  static GstBreakdown calculate({required double quantity, required double unitRate, required double gstRate, required bool intraState, double discount = 0}) {
    if (!quantity.isFinite || quantity <= 0) throw ArgumentError.value(quantity, 'quantity', 'Must be a finite positive quantity.');
    if (!unitRate.isFinite || unitRate < 0) throw ArgumentError.value(unitRate, 'unitRate', 'Must be finite and non-negative.');
    if (!gstRate.isFinite || gstRate < 0 || gstRate > 100) throw ArgumentError.value(gstRate, 'gstRate', 'Must be between 0 and 100.');
    if (!discount.isFinite || discount < 0) throw ArgumentError.value(discount, 'discount', 'Must be finite and non-negative.');
    final gross = roundMoney(quantity * unitRate);
    if (discount > gross) throw ArgumentError.value(discount, 'discount', 'Cannot exceed the gross value.');
    final taxable = roundMoney(gross - discount);
    final tax = roundMoney(taxable * gstRate / 100);
    final cgst = intraState ? roundMoney(tax / 2) : 0.0;
    final sgst = intraState ? roundMoney(tax - cgst) : 0.0;
    final igst = intraState ? 0.0 : tax;
    return GstBreakdown(taxableValue: taxable, taxRate: gstRate, taxAmount: tax, cgstAmount: cgst, sgstAmount: sgst, igstAmount: igst);
  }
}
