import 'package:flutter_test/flutter_test.dart';
import 'package:srk_business_manager/src/data/local/gst_gstr1_hsn_summary.dart';

void main() {
  group('Gstr1HsnRateAggregator', () {
    test('groups by HSN/SAC and GST rate and sums tax components', () {
      final result = Gstr1HsnRateAggregator.aggregate([
        {'hsn_sac':'1001','gst_rate':5,'quantity':2,'unit':'pcs','line_total':105,'tax_amount':5,'cgst_amount':2.5,'sgst_amount':2.5,'igst_amount':0},
        {'hsn_sac':'1001','gst_rate':5,'quantity':4,'unit':'pcs','line_total':210,'tax_amount':10,'cgst_amount':5,'sgst_amount':5,'igst_amount':0},
        {'hsn_sac':'1001','gst_rate':12,'quantity':1,'unit':'pcs','line_total':112,'tax_amount':12,'cgst_amount':0,'sgst_amount':0,'igst_amount':12},
      ]);
      expect(result, hasLength(2));
      expect(result.first.hsnSac, '1001');
      expect(result.first.gstRate, 5);
      expect(result.first.unit, 'pcs');
      expect(result.first.quantity, 6);
      expect(result.first.totalValue, 315);
      expect(result.first.taxableValue, 300);
      expect(result.first.taxAmount, 15);
      expect(result.first.cgst, 7.5);
      expect(result.first.sgst, 7.5);
      expect(result.last.igst, 12);
    });

    test('keeps missing HSN visible and skips invalid rows', () {
      final result = Gstr1HsnRateAggregator.aggregate([
        {'hsn_sac':'','gst_rate':0,'quantity':1,'unit':'kg','line_total':50,'tax_amount':0,'cgst_amount':0,'sgst_amount':0,'igst_amount':0},
        {'hsn_sac':'123','gst_rate':double.nan,'quantity':1,'unit':'kg','line_total':50,'tax_amount':0,'cgst_amount':0,'sgst_amount':0,'igst_amount':0},
      ]);
      expect(result, hasLength(1));
      expect(result.single.hsnSac, 'HSN/SAC অনুল্লিখিত');
    });

    test('skips rows when tax components do not reconcile to total tax', () {
      final result = Gstr1HsnRateAggregator.aggregate([
        {'hsn_sac':'1001','gst_rate':5,'quantity':1,'unit':'pcs','line_total':105,'tax_amount':5,'cgst_amount':2,'sgst_amount':2,'igst_amount':0},
        {'hsn_sac':'1002','gst_rate':5,'quantity':1,'unit':'pcs','line_total':105,'tax_amount':5.01,'cgst_amount':2.5,'sgst_amount':2.5,'igst_amount':0},
      ]);
      expect(result, hasLength(1));
      expect(result.single.hsnSac, '1002');
    });

    test('does not combine different units into one quantity total', () {
      final result = Gstr1HsnRateAggregator.aggregate([
        {'hsn_sac':'1001','gst_rate':5,'quantity':2,'unit':'kg','line_total':105,'tax_amount':5,'cgst_amount':2.5,'sgst_amount':2.5,'igst_amount':0},
        {'hsn_sac':'1001','gst_rate':5,'quantity':3,'unit':'pcs','line_total':105,'tax_amount':5,'cgst_amount':2.5,'sgst_amount':2.5,'igst_amount':0},
      ]);
      expect(result, hasLength(2));
      expect(result.map((row) => row.unit).toSet(), {'kg', 'pcs'});
    });
  });
}
