/// HSN/SAC and GST-rate-wise summary for locally recorded outward invoice lines.
class Gstr1HsnRateSummary {
  const Gstr1HsnRateSummary({
    required this.hsnSac,
    required this.gstRate,
    required this.unit,
    required this.quantity,
    required this.totalValue,
    required this.taxableValue,
    required this.taxAmount,
    required this.cgst,
    required this.sgst,
    required this.igst,
  });
  final String hsnSac;
  final double gstRate;
  /// Unit exactly as stored on invoice lines; not an official GST UQC mapping.
  final String unit;
  final double quantity;
  final double totalValue;
  final double taxableValue;
  final double taxAmount;
  final double cgst;
  final double sgst;
  final double igst;
}

class Gstr1HsnRateAggregator {
  Gstr1HsnRateAggregator._();

  static List<Gstr1HsnRateSummary> aggregate(
    List<Map<String, Object?>> rows,
  ) {
    final totals = <(String, double, String), List<double>>{};
    for (final row in rows) {
      final hsn = (row['hsn_sac'] as String? ?? '').trim();
      final rate = _number(row['gst_rate']);
      final quantity = _number(row['quantity']);
      final unit = (row['unit'] as String? ?? '').trim();
      final lineTotal = _number(row['line_total']);
      final tax = _number(row['tax_amount']);
      final cgst = _number(row['cgst_amount']);
      final sgst = _number(row['sgst_amount']);
      final igst = _number(row['igst_amount']);
      if (rate == null || quantity == null || lineTotal == null || tax == null ||
          cgst == null || sgst == null || igst == null ||
          rate < 0 || quantity < 0 || lineTotal < 0 || tax < 0 || cgst < 0 ||
          sgst < 0 || igst < 0 || tax > lineTotal + 0.01) {
        continue;
      }
      final key = (hsn.isEmpty ? 'HSN/SAC অনুল্লিখিত' : hsn, rate,
          unit.isEmpty ? 'একক অনুল্লিখিত' : unit);
      final values = totals.putIfAbsent(key, () => List<double>.filled(7, 0));
      values[0] += quantity;
      values[1] += lineTotal;
      values[2] += lineTotal - tax;
      values[3] += tax;
      values[4] += cgst;
      values[5] += sgst;
      values[6] += igst;
    }
    final result = totals.entries.map((entry) => Gstr1HsnRateSummary(
      hsnSac: entry.key.$1,
      gstRate: entry.key.$2,
      unit: entry.key.$3,
      quantity: entry.value[0],
      totalValue: entry.value[1],
      taxableValue: entry.value[2],
      taxAmount: entry.value[3],
      cgst: entry.value[4],
      sgst: entry.value[5],
      igst: entry.value[6],
    )).toList();
    result.sort((a, b) {
      final hsnOrder = a.hsnSac.compareTo(b.hsnSac);
      return hsnOrder != 0 ? hsnOrder : a.gstRate.compareTo(b.gstRate);
    });
    return List.unmodifiable(result);
  }

  static double? _number(Object? value) {
    if (value is! num) return null;
    final number = value.toDouble();
    return number.isFinite ? number : null;
  }
}
