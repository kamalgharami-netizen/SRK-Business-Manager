import 'package:flutter_test/flutter_test.dart';
import 'package:srk_business_manager/src/data/local/gst_gstr1_credit_note_audit.dart';

void main() {
  group('Gstr1CreditNoteAuditCsv', () {
    test('exports original invoice link and separate GST components', () {
      final csv = Gstr1CreditNoteAuditCsv.build([
        {
          'note_number': 'SR-001',
          'original_invoice_number': 'INV-001',
          'note_date': '2026-11-02',
          'review_status': 'MANUAL_GST_REVIEW_REQUIRED',
          'note_value': 118,
          'taxable_value': 100,
          'tax_amount': 18,
          'cgst_amount': 9,
          'sgst_amount': 9,
          'igst_amount': 0,
        },
      ], supplierGstin: '19ABCDE1234F1Z5',
          periodStart: '2026-11-01', periodEnd: '2026-11-30');

      expect(csv, startsWith('\uFEFF'));
      expect(csv, contains('Supplier GSTIN,19ABCDE1234F1Z5'));
      expect(csv, contains('SR-001,INV-001,2026-11-02,MANUAL_GST_REVIEW_REQUIRED,118.00,100.00,18.00,9.00,9.00,0.00'));
    });

    test('neutralises formula-like note numbers and quotes commas', () {
      final csv = Gstr1CreditNoteAuditCsv.build([
        {
          'note_number': '=HYPERLINK("https://example.com")',
          'original_invoice_number': 'INV,002',
          'note_date': '2026-11-02',
          'review_status': 'REVIEW',
          'note_value': 0,
        },
      ], supplierGstin: '', periodStart: 'start', periodEnd: 'end');

      expect(csv, contains("'=HYPERLINK("));
      expect(csv, contains('"INV,002"'));
    });
  });
}
