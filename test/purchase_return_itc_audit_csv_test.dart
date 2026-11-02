import 'package:flutter_test/flutter_test.dart';
import 'package:srk_business_manager/src/data/local/purchase_return_itc_audit_csv.dart';

void main() {
  group('PurchaseReturnItcAuditCsv', () {
    test('exports original purchase link and separate GST components', () {
      final csv = PurchaseReturnItcAuditCsv.build([
        {
          'return_number': 'PR-001',
          'original_invoice_number': 'PUR-001',
          'return_date': '2026-11-02',
          'review_status': 'MANUAL_ITC_REVERSAL_REVIEW_REQUIRED',
          'return_value': 118,
          'taxable_value': 100,
          'tax_amount': 18,
          'cgst_amount': 9,
          'sgst_amount': 9,
          'igst_amount': 0,
        },
      ], recipientGstin: '19ABCDE1234F1Z5',
          periodStart: '2026-11-01', periodEnd: '2026-11-30');

      expect(csv, startsWith('\uFEFF'));
      expect(csv, contains('Recipient GSTIN,19ABCDE1234F1Z5'));
      expect(csv, contains('PR-001,PUR-001,2026-11-02,MANUAL_ITC_REVERSAL_REVIEW_REQUIRED,118.00,100.00,18.00,9.00,9.00,0.00'));
    });

    test('neutralises formula-like values and quotes commas', () {
      final csv = PurchaseReturnItcAuditCsv.build([
        {
          'return_number': '=1+1',
          'original_invoice_number': 'PUR,002',
          'return_date': '2026-11-02',
          'review_status': 'REVIEW',
        },
      ], recipientGstin: '', periodStart: 'start', periodEnd: 'end');

      expect(csv, contains("'=1+1"));
      expect(csv, contains('"PUR,002"'));
    });
  });
}
