import 'package:flutter_test/flutter_test.dart';
import 'package:srk_business_manager/src/data/local/debit_note_service.dart';

void main() {
  group('DebitNoteLine validation', () {
    test('accepts a valid intra-state debit note line', () {
      const line = DebitNoteLine(
        description: 'Additional service charge',
        quantity: 2,
        unit: 'pcs',
        rate: 500,
        gstRate: 18,
        taxableValue: 1000,
        cgst: 90,
        sgst: 90,
        igst: 0,
      );

      expect(() => line.validate(taxType: 'intra_state'), returnsNormally);
      expect(line.taxAmount, 180);
      expect(line.lineTotal, 1180);
    });

    test('accepts a valid inter-state debit note line', () {
      const line = DebitNoteLine(
        description: 'Freight difference',
        quantity: 1,
        unit: 'job',
        rate: 1000,
        gstRate: 18,
        taxableValue: 1000,
        cgst: 0,
        sgst: 0,
        igst: 180,
      );

      expect(() => line.validate(taxType: 'inter_state'), returnsNormally);
    });

    test('rejects IGST on an intra-state debit note', () {
      const line = DebitNoteLine(
        description: 'Charge',
        quantity: 1,
        unit: 'job',
        rate: 1000,
        gstRate: 18,
        taxableValue: 1000,
        cgst: 0,
        sgst: 0,
        igst: 180,
      );

      expect(
        () => line.validate(taxType: 'intra_state'),
        throwsA(isA<FormatException>()),
      );
    });

    test('rejects CGST or SGST on an inter-state debit note', () {
      const line = DebitNoteLine(
        description: 'Charge',
        quantity: 1,
        unit: 'job',
        rate: 1000,
        gstRate: 18,
        taxableValue: 1000,
        cgst: 90,
        sgst: 90,
        igst: 0,
      );

      expect(
        () => line.validate(taxType: 'inter_state'),
        throwsA(isA<FormatException>()),
      );
    });

    test('rejects mismatched taxable value and GST rate', () {
      const line = DebitNoteLine(
        description: 'Charge',
        quantity: 1,
        unit: 'job',
        rate: 1000,
        gstRate: 18,
        taxableValue: 900,
        cgst: 81,
        sgst: 81,
        igst: 0,
      );

      expect(
        () => line.validate(taxType: 'intra_state'),
        throwsA(isA<FormatException>()),
      );
    });

    test('rejects non-finite or non-positive quantities', () {
      const line = DebitNoteLine(
        description: 'Charge',
        quantity: double.infinity,
        unit: 'job',
        rate: 1000,
        gstRate: 18,
        taxableValue: 1000,
        cgst: 90,
        sgst: 90,
        igst: 0,
      );

      expect(
        () => line.validate(taxType: 'intra_state'),
        throwsA(isA<FormatException>()),
      );
    });
  });
}
