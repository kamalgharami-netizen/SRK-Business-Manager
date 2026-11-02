import 'package:flutter_test/flutter_test.dart';
import 'package:srk_business_manager/src/data/local/gst_rcm_reconciliation_csv_export.dart';

void main() {
  group('GstrRcmReconciliationCsvExport', () {
    test('exports liability, cash payments and tax-head outstanding', () {
      final csv = GstrRcmReconciliationCsvExport.build([
        {
          'document_reference': 'RCM-001',
          'supplier_name': 'Supplier A',
          'taxable_value': 1000,
          'igst': 18,
          'igst_paid': 10,
          'cgst': 9,
          'cgst_paid': 9,
          'sgst': 9,
          'sgst_paid': 0,
          'cess': 0,
          'cess_paid': 0,
          'payment_count': 1,
          'payment_references': '2026-11-01 • CASH-1 • CIN-1',
        },
      ], returnPeriod: '2026-11');
      expect(csv, startsWith('\\uFEFF'));
      expect(csv, contains('RCM-001,Supplier A,1000.00,18.00,10.00,8.00'));
      expect(csv, contains('9.00,9.00,0.00,9.00,0.00,9.00'));
      expect(csv, contains('MANUAL_CHALLAN_VERIFICATION_REQUIRED'));
    });

    test('flags overpayment and rejects invalid values or periods', () {
      final csv = GstrRcmReconciliationCsvExport.build([
        {
          'document_reference': 'RCM-002',
          'igst': 10,
          'igst_paid': 12,
        },
      ], returnPeriod: '2026-11');
      expect(csv, contains('OVERPAYMENT_REVIEW_REQUIRED'));
      expect(
        () => GstrRcmReconciliationCsvExport.build([], returnPeriod: '2026-13'),
        throwsFormatException,
      );
      expect(
        () => GstrRcmReconciliationCsvExport.build([
          {'document_reference': 'BAD', 'igst': -1},
        ], returnPeriod: '2026-11'),
        throwsFormatException,
      );
    });

    test('quotes commas and neutralises formula-like references', () {
      final csv = GstrRcmReconciliationCsvExport.build([
        {'document_reference': '=1+1', 'supplier_name': 'Supplier, Branch'},
      ], returnPeriod: '2026-11');
      expect(csv, contains("'=1+1"));
      expect(csv, contains('"Supplier, Branch"'));
    });
  });
}
