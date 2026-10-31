import 'package:flutter_test/flutter_test.dart';
import 'package:srk_business_manager/src/data/local/gst_calculator.dart';

void main() {
  group('GstCalculator', () {
    test('calculates intra-state GST and preserves paise across CGST and SGST', () {
      final result = GstCalculator.calculate(quantity: 1, unitRate: 100.05, gstRate: 18, intraState: true);
      expect(result.taxableValue, 100.05);
      expect(result.taxAmount, 18.01);
      expect(result.cgstAmount, 9.01);
      expect(result.sgstAmount, 9.00);
      expect(result.igstAmount, 0);
      expect(result.cgstAmount + result.sgstAmount, result.taxAmount);
      expect(result.lineTotal, 118.06);
    });

    test('calculates inter-state GST entirely as IGST', () {
      final result = GstCalculator.calculate(quantity: 2, unitRate: 250, gstRate: 12, intraState: false);
      expect(result.taxableValue, 500);
      expect(result.taxAmount, 60);
      expect(result.cgstAmount, 0);
      expect(result.sgstAmount, 0);
      expect(result.igstAmount, 60);
      expect(result.lineTotal, 560);
    });

    test('applies discount before GST', () {
      final result = GstCalculator.calculate(quantity: 2, unitRate: 100, discount: 25, gstRate: 5, intraState: false);
      expect(result.taxableValue, 175);
      expect(result.taxAmount, 8.75);
      expect(result.lineTotal, 183.75);
    });

    test('rejects invalid quantity, rate, GST rate and excessive discount', () {
      expect(() => GstCalculator.calculate(quantity: 0, unitRate: 10, gstRate: 5, intraState: true), throwsArgumentError);
      expect(() => GstCalculator.calculate(quantity: 1, unitRate: -1, gstRate: 5, intraState: true), throwsArgumentError);
      expect(() => GstCalculator.calculate(quantity: 1, unitRate: 10, gstRate: 101, intraState: true), throwsArgumentError);
      expect(() => GstCalculator.calculate(quantity: 1, unitRate: 10, discount: 11, gstRate: 5, intraState: true), throwsArgumentError);
    });

    test('rejects non-finite monetary inputs', () {
      expect(() => GstCalculator.calculate(quantity: 1, unitRate: double.infinity, gstRate: 5, intraState: true), throwsArgumentError);
    });
  });
}
