import 'package:flutter_test/flutter_test.dart';
import 'package:srk_business_manager/src/data/local/invoice_number_generator.dart';

void main() {
  group('InvoiceNumberGenerator', () {
    test('generates a GST-compatible invoice number of at most 16 characters', () {
      final value = InvoiceNumberGenerator.generate(DateTime(2026, 11, 1, 8, 30));
      expect(value, hasLength(16));
      expect(value, matches(RegExp(r'^[A-Za-z0-9&/-]+$')));
    });

    test('uses a two-digit year and zero-padded month and day', () {
      final value = InvoiceNumberGenerator.generate(DateTime(2026, 2, 3));
      expect(value.substring(0, 9), 'INV260203');
    });
  });
}
