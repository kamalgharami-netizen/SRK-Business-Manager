import 'package:flutter_test/flutter_test.dart';
import 'package:srk_business_manager/src/data/local/gst_gstr3b_itc.dart';
import 'package:srk_business_manager/src/data/local/gst_gstr3b_itc_repository.dart';

void main() {
  group('GSTR-3B ITC assessment validation', () {
    const tax = Gstr3bTaxAmounts(igst: 18, cess: 2);

    test('accepts valid supplier invoice and period data', () {
      expect(
        Gstr3bItcAssessmentValidator.validate(
          supplierGstin: '27AAPFU0939F1ZV',
          supplierInvoiceNumber: 'INV-100',
          supplierInvoiceDate: '2026-10-12',
          returnPeriod: '2026-10',
          taxableValue: 100,
          tax: tax,
        ),
        isEmpty,
      );
    });

    test('keeps a missing supplier GSTIN visible as an incomplete-data issue', () {
      expect(
        Gstr3bItcAssessmentValidator.validate(
          supplierGstin: '',
          supplierInvoiceNumber: 'INV-100',
          supplierInvoiceDate: '2026-10-12',
          returnPeriod: '2026-10',
          taxableValue: 100,
          tax: tax,
        ),
        contains('Supplier GSTIN is missing.'),
      );
    });

    test('rejects impossible calendar invoice dates', () {
      for (final date in ['2026-02-30', '2026-13-01', '31/10/2026']) {
        final issues = Gstr3bItcAssessmentValidator.validate(
          supplierGstin: '27AAPFU0939F1ZV',
          supplierInvoiceNumber: 'INV-100',
          supplierInvoiceDate: date,
          returnPeriod: '2026-10',
          taxableValue: 100,
          tax: tax,
        );
        expect(issues, contains('Supplier invoice date is invalid.'));
      }
    });

    test('rejects invalid invoice dates, periods and negative taxable value', () {
      final issues = Gstr3bItcAssessmentValidator.validate(
        supplierGstin: '27AAPFU0939F1ZV',
        supplierInvoiceNumber: 'INV-100',
        supplierInvoiceDate: 'not-a-date',
        returnPeriod: '2026-13',
        taxableValue: -1,
        tax: tax,
      );
      expect(issues, hasLength(3));
    });

    test('rejects negative or infinite GST components', () {
      final issues = Gstr3bItcAssessmentValidator.validate(
        supplierGstin: '27AAPFU0939F1ZV',
        supplierInvoiceNumber: 'INV-100',
        supplierInvoiceDate: '2026-10-12',
        returnPeriod: '2026-10',
        taxableValue: 100,
        tax: const Gstr3bTaxAmounts(cgst: double.infinity),
      );
      expect(issues, contains('GST components must be finite and non-negative.'));
    });
  });

  group('GSTR-3B previous reversal reclaim validation', () {
    test('accepts reclaim within the previous unclaimed amount by tax head', () {
      expect(
        Gstr3bItcReclaimValidator.validate(
          documentReference: 'REV-2026-09-01',
          requested: const Gstr3bTaxAmounts(igst: 60, cgst: 20),
          previouslyReversed: const Gstr3bTaxAmounts(igst: 100, cgst: 50),
          alreadyReclaimed: const Gstr3bTaxAmounts(igst: 30, cgst: 10),
        ),
        isEmpty,
      );
    });

    test('rejects reclaim above the remaining amount for each tax head', () {
      final issues = Gstr3bItcReclaimValidator.validate(
        documentReference: 'REV-2026-09-01',
        requested: const Gstr3bTaxAmounts(igst: 71, cgst: 41),
        previouslyReversed: const Gstr3bTaxAmounts(igst: 100, cgst: 50),
        alreadyReclaimed: const Gstr3bTaxAmounts(igst: 30, cgst: 10),
      );
      expect(issues, contains('Reclaim igst exceeds the unclaimed previous reversal amount.'));
      expect(issues, contains('Reclaim cgst exceeds the unclaimed previous reversal amount.'));
    });

    test('requires a source reference, valid history and a positive reclaim', () {
      final issues = Gstr3bItcReclaimValidator.validate(
        documentReference: ' ',
        requested: const Gstr3bTaxAmounts(),
        previouslyReversed: const Gstr3bTaxAmounts(igst: double.infinity),
        alreadyReclaimed: const Gstr3bTaxAmounts(),
      );
      expect(issues, contains('Previous reversal document reference is required.'));
      expect(issues, contains('Reclaim must contain at least one positive, valid tax amount.'));
      expect(issues, contains('Previous reversal history contains invalid tax amounts.'));
    });

    test('does not allow a reclaim without an earlier reversal', () {
      final issues = Gstr3bItcReclaimValidator.validate(
        documentReference: 'REV-NOT-FOUND',
        requested: const Gstr3bTaxAmounts(igst: 1),
        previouslyReversed: const Gstr3bTaxAmounts(),
        alreadyReclaimed: const Gstr3bTaxAmounts(),
      );
      expect(issues, contains('Reclaim igst exceeds the unclaimed previous reversal amount.'));
    });
  });

  group('RCM liability and cash payment validation', () {
    test('accepts a valid RCM liability', () {
      expect(Gstr3bRcmValidator.validateLiability(
        returnPeriod: '2026-10',
        documentReference: 'INV-RCM-1',
        taxableValue: 1000,
        tax: const Gstr3bTaxAmounts(cgst: 90, sgst: 90),
      ), isEmpty);
    });

    test('rejects invalid period, missing reference and zero tax', () {
      final issues = Gstr3bRcmValidator.validateLiability(
        returnPeriod: '2026-13',
        documentReference: '',
        taxableValue: 100,
        tax: const Gstr3bTaxAmounts(),
      );
      expect(issues, hasLength(3));
    });

    test('requires cash ledger and challan references', () {
      final issues = Gstr3bRcmValidator.validatePayment(
        paymentDate: '2026-10-31',
        cashLedgerReference: '',
        challanReference: '',
        tax: const Gstr3bTaxAmounts(igst: 18),
      );
      expect(issues, contains('Cash ledger reference is required.'));
      expect(issues, contains('Challan reference is required.'));
    });

    test('rejects non-calendar and non-ISO payment dates', () {
      for (final date in ['2026-02-30', '31/10/2026', '2026-10-31T10:00:00']) {
        final issues = Gstr3bRcmValidator.validatePayment(
          paymentDate: date,
          cashLedgerReference: 'CASH-1',
          challanReference: 'CIN-1',
          tax: const Gstr3bTaxAmounts(igst: 18),
        );
        expect(issues, contains('Payment date must be a valid calendar date in YYYY-MM-DD format.'));
      }
    });

    test('rejects non-finite and negative RCM amounts', () {
      final issues = Gstr3bRcmValidator.validateLiability(
        returnPeriod: '2026-10',
        documentReference: 'INV-RCM-2',
        taxableValue: double.infinity,
        tax: const Gstr3bTaxAmounts(igst: -1),
      );
      expect(issues, contains('Taxable value must be finite and non-negative.'));
      expect(issues, contains('RCM tax must contain at least one positive, valid tax amount.'));
    });
  });

  group('GSTR-2B CSV import', () {
    test('parses normalized statement rows and quoted references', () {
      final records = Gstr2bCsvImporter.parse(
        'supplier_gstin,invoice_number,invoice_date,return_period,taxable_value,igst,cgst,sgst,cess,source_reference\n'
        '27AAPFU0939F1ZV,INV-100,2026-10-12,2026-10,100,18,0,0,0,"Sheet 1, Row 2"\n',
      );
      expect(records, hasLength(1));
      expect(records.single.invoiceNumber, 'INV-100');
      expect(records.single.sourceReference, 'Sheet 1, Row 2');
    });

    test('accepts a UTF-8 BOM, CRLF rows and escaped quotes', () {
      final records = Gstr2bCsvImporter.parse(
        '\uFEFFsupplier_gstin,invoice_number,invoice_date,return_period,taxable_value,igst,cgst,sgst,cess,source_reference\r\n'
        '27AAPFU0939F1ZV,INV-101,2026-10-12,2026-10,100,18,0,0,0,"Supplier ""A"", branch 2"\r\n',
      );
      expect(records, hasLength(1));
      expect(records.single.sourceReference, 'Supplier "A", branch 2');
    });

    test('rejects quotes embedded in unquoted CSV fields', () {
      expect(
        () => Gstr2bCsvImporter.parse(
          'supplier_gstin,invoice_number,invoice_date,return_period,taxable_value,igst,cgst,sgst,cess\\n'
          '27AAPFU0939F1ZV,INV"102,2026-10-12,2026-10,100,18,0,0,0',
        ),
        throwsFormatException,
      );
    });

    test('rejects characters after a closing quoted CSV field', () {
      expect(
        () => Gstr2bCsvImporter.parse(
          'supplier_gstin,invoice_number,invoice_date,return_period,taxable_value,igst,cgst,sgst,cess\\n'
          '27AAPFU0939F1ZV,"INV-103"x,2026-10-12,2026-10,100,18,0,0,0',
        ),
        throwsFormatException,
      );
    });

    test('rejects duplicate CSV column headers', () {
      expect(
        () => Gstr2bCsvImporter.parse(
          'supplier_gstin,invoice_number,invoice_date,return_period,taxable_value,igst,cgst,sgst,cess,igst\n'
          '27AAPFU0939F1ZV,INV-104,2026-10-12,2026-10,100,18,0,0,0,18',
        ),
        throwsFormatException,
      );
    });

    test('rejects CSV rows with missing or extra columns', () {
      expect(
        () => Gstr2bCsvImporter.parse(
          'supplier_gstin,invoice_number,invoice_date,return_period,taxable_value,igst,cgst,sgst,cess\n'
          '27AAPFU0939F1ZV,INV-105,2026-10-12,2026-10,100,18,0,0',
        ),
        throwsFormatException,
      );
      expect(
        () => Gstr2bCsvImporter.parse(
          'supplier_gstin,invoice_number,invoice_date,return_period,taxable_value,igst,cgst,sgst,cess\n'
          '27AAPFU0939F1ZV,INV-106,2026-10-12,2026-10,100,18,0,0,0,EXTRA',
        ),
        throwsFormatException,
      );
    });

    test('rejects rows with missing supplier identity or invalid invoice dates and periods', () {
      final header = 'supplier_gstin,invoice_number,invoice_date,return_period,taxable_value,igst,cgst,sgst,cess\\n';
      for (final row in [
        ',INV-200,2026-10-12,2026-10,100,18,0,0,0',
        '27AAPFU0939F1ZV,,2026-10-12,2026-10,100,18,0,0,0',
        '27AAPFU0939F1ZV,INV-200,2026-02-30,2026-10,100,18,0,0,0',
        '27AAPFU0939F1ZV,INV-200,2026-10-12,2026-13,100,18,0,0,0',
      ]) {
        expect(() => Gstr2bCsvImporter.parse('$header$row'), throwsFormatException);
      }
    });

    test('rejects CSV rows with negative taxable values or GST components', () {
      const header = 'supplier_gstin,invoice_number,invoice_date,return_period,taxable_value,igst,cgst,sgst,cess\\n';
      expect(
        () => Gstr2bCsvImporter.parse(
          '${header}27AAPFU0939F1ZV,INV-201,2026-10-12,2026-10,-1,18,0,0,0',
        ),
        throwsFormatException,
      );
      expect(
        () => Gstr2bCsvImporter.parse(
          '${header}27AAPFU0939F1ZV,INV-202,2026-10-12,2026-10,100,-1,0,0,0',
        ),
        throwsFormatException,
      );
    });

    test('rejects a CSV without mandatory headers', () {
      expect(
        () => Gstr2bCsvImporter.parse('invoice_number,igst\nINV-1,18'),
        throwsFormatException,
      );
    });
  });

  group('GSTR-2B reconciliation matching', () {
    const statement = Gstr2bImportRecord(
      supplierGstin: '27AAPFU0939F1ZV',
      invoiceNumber: 'inv-100',
      invoiceDate: '2026-10-12',
      returnPeriod: '2026-10',
      taxableValue: 100,
      igst: 18,
    );

    test('matches supplier, document, period and tax values case-insensitively', () {
      expect(
        Gstr2bReconciliationMatcher.matches(
          statement: statement,
          supplierGstin: '27aapfu0939f1zv',
          invoiceNumber: 'INV-100',
          invoiceDate: '2026-10-12T00:00:00',
          returnPeriod: '2026-10',
          taxableValue: 100.005,
          tax: const Gstr3bTaxAmounts(igst: 18),
        ),
        isTrue,
      );
    });

    test('does not match when the tax amount differs', () {
      expect(
        Gstr2bReconciliationMatcher.matches(
          statement: statement,
          supplierGstin: '27AAPFU0939F1ZV',
          invoiceNumber: 'INV-100',
          invoiceDate: '2026-10-12',
          returnPeriod: '2026-10',
          taxableValue: 100,
          tax: const Gstr3bTaxAmounts(igst: 19),
        ),
        isFalse,
      );
    });
  });
  group('RCM audit history query validation', () {
    test('rejects malformed return periods before querying the database', () async {
      for (final period in ['2026-00', '2026-13', '26-10', '2026/10']) {
        await expectLater(
          Gstr3bRcmRepository.listAuditHistory(returnPeriod: period),
          throwsFormatException,
        );
      }
    });

    test('rejects audit history limits outside the supported range', () async {
      for (final limit in [0, -1, 1001]) {
        await expectLater(
          Gstr3bRcmRepository.listAuditHistory(limit: limit),
          throwsRangeError,
        );
      }
    });
  });

}
