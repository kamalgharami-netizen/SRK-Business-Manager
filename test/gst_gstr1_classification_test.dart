import 'package:flutter_test/flutter_test.dart';
import 'package:srk_business_manager/src/data/local/gst_gstr1_classification.dart';

void main() {
  group('Gstr1DomesticClassifier', () {
    Map<String, Object?> invoice({
      String gstin = '',
      String place = 'West Bengal',
      double value = 50000,
    }) => {
      'invoice_number': 'INV-1',
      'party_gstin': gstin,
      'place_of_supply': place,
      'invoice_value': value,
      'taxable_value': 40000.0,
      'tax_amount': 7200.0,
    };

    test('classifies registered recipient as B2B', () {
      final result = Gstr1DomesticClassifier.classify(
        [invoice(gstin: '19ABCDE1234F1Z5')],
        supplierState: 'West Bengal',
      );
      expect(result.count(Gstr1SupplyCategory.b2b), 1);
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
