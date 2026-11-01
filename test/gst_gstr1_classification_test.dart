import 'package:flutter_test/flutter_test.dart';
import 'package:srk_business_manager/src/data/local/gst_gstr1_classification.dart';

void main() {
  group('Gstr1DomesticClassifier', () {
    Gstr1ClassificationSummary classify(
      List<Map<String, Object?>> invoices, {
      String supplierState = 'West Bengal',
      DateTime? returnPeriod,
    }) =>
        Gstr1DomesticClassifier.classify(
          invoices,
          supplierState: supplierState,
          returnPeriod: returnPeriod ?? DateTime(2024, 8),
        );

    Map<String, Object?> invoice({
      String gstin = '',
      String partyState = '',
      String place = 'West Bengal',
      double value = 50000,
    }) => {
      'invoice_number': 'INV-1',
      'party_gstin': gstin,
      'party_state': partyState,
      'place_of_supply': place,
      'invoice_value': value,
      'taxable_value': 40000.0,
      'tax_amount': 7200.0,
    };

    test('classifies registered recipient as B2B when GSTIN matches party state', () {
      final result = Gstr1DomesticClassifier.classify(
        [invoice(gstin: '19ABCDE1234F1Z5', partyState: 'West Bengal')],
        supplierState: 'West Bengal',
      );
      expect(result.count(Gstr1SupplyCategory.b2b), 1);
    });

    test('routes B2B invoice with missing place of supply to review', () {
      final result = Gstr1DomesticClassifier.classify(
        [invoice(gstin: '19ABCDE1234F1Z5', partyState: 'West Bengal', place: '')],
        supplierState: 'West Bengal',
      );
      expect(result.count(Gstr1SupplyCategory.review), 1);
      expect(result.invoices.single.reason,
          'Supplier state or place of supply is missing or invalid.');
    });

    test('routes B2B invoice with unknown supplier state to review', () {
      final result = Gstr1DomesticClassifier.classify(
        [invoice(gstin: '19ABCDE1234F1Z5', partyState: 'West Bengal')],
        supplierState: 'Unknown State',
      );
      expect(result.count(Gstr1SupplyCategory.review), 1);
    });

    test('routes a recipient GSTIN and state mismatch to review', () {
      final result = Gstr1DomesticClassifier.classify(
        [invoice(gstin: '19ABCDE1234F1Z5', partyState: 'Bihar')],
        supplierState: 'West Bengal',
      );
      expect(result.count(Gstr1SupplyCategory.review), 1);
      expect(result.invoices.single.reason,
          'Recipient GSTIN does not match a valid recipient state.');
    });

    test('routes a registered recipient without party state to review', () {
      final result = Gstr1DomesticClassifier.classify(
        [invoice(gstin: '19ABCDE1234F1Z5')],
        supplierState: 'West Bengal',
      );
      expect(result.count(Gstr1SupplyCategory.review), 1);
    });

    test('classifies inter-State unregistered invoice above ₹1 lakh as B2CL', () {
      final result = Gstr1DomesticClassifier.classify(
        [invoice(place: 'Bihar', value: 100000.01)],
        supplierState: 'West Bengal',
      );
      expect(result.count(Gstr1SupplyCategory.b2cl), 1);
    });

    test('classifies exactly ₹1 lakh and intra-State unregistered as B2CS', () {
      final result = Gstr1DomesticClassifier.classify(
        [invoice(value: 100000), invoice(place: 'Bihar', value: 90000)],
        supplierState: 'West Bengal',
      );
      expect(result.count(Gstr1SupplyCategory.b2cs), 2);
    });

    test('sends missing place of supply or invalid amounts to review', () {
      final missingPlace = invoice()..['place_of_supply'] = '';
      final invalidAmount = invoice()..['invoice_value'] = double.nan;
      final result = Gstr1DomesticClassifier.classify(
        [missingPlace, invalidAmount],
        supplierState: 'West Bengal',
      );
      expect(result.count(Gstr1SupplyCategory.review), 2);
    });

    test('routes malformed recipient GSTIN to review instead of B2B', () {
      final result = Gstr1DomesticClassifier.classify(
        [invoice(gstin: 'NOT-A-GSTIN', partyState: 'West Bengal')],
        supplierState: 'West Bengal',
      );
      expect(result.count(Gstr1SupplyCategory.review), 1);
      expect(result.invoices.single.reason, 'Recipient GSTIN format is invalid.');
    });

    test('compares state names without case or extra-space differences', () {
      final result = Gstr1DomesticClassifier.classify(
        [invoice(place: ' west   bengal ')],
        supplierState: 'West Bengal',
      );
      expect(result.count(Gstr1SupplyCategory.b2cs), 1);
      expect(result.count(Gstr1SupplyCategory.b2cl), 0);
    });

    test('routes missing invoice number to review', () {
      final row = invoice()..['invoice_number'] = '  ';
      final result = Gstr1DomesticClassifier.classify(
        [row],
        supplierState: 'West Bengal',
      );
      expect(result.count(Gstr1SupplyCategory.review), 1);
      expect(result.invoices.single.reason, 'Invoice number is missing.');
    });

    test('uses the ₹2.5 lakh B2CL threshold through July 2024', () {
      final result = classify(
        [invoice(place: 'Bihar', value: 200000)],
        returnPeriod: DateTime(2024, 7),
      );
      expect(result.count(Gstr1SupplyCategory.b2cs), 1);
      expect(result.count(Gstr1SupplyCategory.b2cl), 0);
    });

    test('uses the ₹1 lakh B2CL threshold from August 2024', () {
      final result = classify(
        [invoice(place: 'Bihar', value: 150000)],
        returnPeriod: DateTime(2024, 8),
      );
      expect(result.count(Gstr1SupplyCategory.b2cl), 1);
    });

    test('does not classify an invoice exactly at the applicable threshold as B2CL', () {
      final oldPeriod = classify(
        [invoice(place: 'Bihar', value: 250000)],
        returnPeriod: DateTime(2024, 7),
      );
      final newPeriod = classify(
        [invoice(place: 'Bihar', value: 100000)],
        returnPeriod: DateTime(2024, 8),
      );
      expect(oldPeriod.count(Gstr1SupplyCategory.b2cs), 1);
      expect(newPeriod.count(Gstr1SupplyCategory.b2cs), 1);
    });

    test('provides category totals', () {
      final result = Gstr1DomesticClassifier.classify(
        [invoice(value: 120000, place: 'Bihar')],
        supplierState: 'West Bengal',
      );
      expect(result.invoiceValue(Gstr1SupplyCategory.b2cl), 120000);
      expect(result.taxableValue(Gstr1SupplyCategory.b2cl), 40000);
      expect(result.taxAmount(Gstr1SupplyCategory.b2cl), 7200);
    });
  });
}
