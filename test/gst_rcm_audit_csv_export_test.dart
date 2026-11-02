import 'package:flutter_test/flutter_test.dart';
import 'package:srk_business_manager/src/data/local/gst_rcm_audit_csv_export.dart';

void main() {
  group('RCM audit CSV export', () {
    test('exports audit fields with UTF-8 BOM and spreadsheet headings', () {
      final csv = GstrRcmAuditCsvExport.build([
        {
          'changed_at': '2026-11-02 10:00:00',
          'entity_type': 'payment',
          'record_id': 7,
          'action': 'insert',
          'document_reference': 'RCM-INV-7',
          'payment_date': '2026-11-01',
          'cash_ledger_reference': 'CASH-1',
          'challan_reference': 'CIN-1',
          'taxable_value': null,
          'igst': 18,
          'cgst': 0,
          'sgst': 0,
          'cess': 0,
          'notes': 'Paid, verified',
        },
      ], returnPeriod: '2026-11');

      expect(csv.startsWith('\uFEFF'), isTrue);
      expect(csv, contains('Return Period,2026-11'));
      expect(csv, contains('payment,7,insert,RCM-INV-7'));
      expect(csv, contains('"Paid, verified"'));
      expect(csv, contains('18.00'));
    });

    test('escapes quotes and protects formula-like text fields', () {
      final csv = GstrRcmAuditCsvExport.build([
        {
          'changed_at': '2026-11-02',
          'entity_type': 'liability',
          'record_id': 1,
          'action': 'insert',
          'document_reference': '=HYPERLINK("https://example.invalid")',
          'notes': 'Supplier "A"',
          'igst': 0,
          'cgst': 0,
          'sgst': 0,
          'cess': 0,
        },
      ], returnPeriod: '2026-11');

      expect(csv, contains('"\u0027=HYPERLINK(""https://example.invalid"")"'));
      expect(csv, contains('"Supplier ""A"""'));
    });

    test('exports an empty audit history without fabricating rows', () {
      final csv = GstrRcmAuditCsvExport.build(
        const [],
        returnPeriod: '2026-11',
      );

      expect(csv, contains('Changed At,Entity Type,Record ID,Action'));
      expect(csv.trim().split('\r\n'), hasLength(4));
    });
  });
}
