/// Generates compact invoice numbers compatible with the GST invoice-number
/// character and 16-character length constraints.
class InvoiceNumberGenerator {
  InvoiceNumberGenerator._();

  static String generate(DateTime dateTime) {
    final year = dateTime.year.toString().padLeft(4, '0').substring(2);
    final month = dateTime.month.toString().padLeft(2, '0');
    final day = dateTime.day.toString().padLeft(2, '0');
    final suffix = dateTime.microsecondsSinceEpoch
        .toString()
        .padLeft(6, '0')
        .substring(dateTime.microsecondsSinceEpoch.toString().length > 6
            ? dateTime.microsecondsSinceEpoch.toString().length - 6
            : 0);
    return 'INV$year$month$day-$suffix';
  }
}
