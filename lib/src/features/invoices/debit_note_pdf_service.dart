import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

/// Generates a local printable working copy of a saved sales debit note.
/// This document is not a GSTN filing or a substitute for professional review.
class DebitNotePdfService {
  static Future<void> printDebitNote({
    required Map<String, Object?> note,
    required List<Map<String, Object?>> items,
    required Map<String, String> business,
  }) async {
    final document = pw.Document();
    final number = note['debit_note_number']?.toString() ?? '';
    final date = (note['note_date']?.toString() ?? '').split('T').first;
    final companyName = business['company_name']?.trim().isNotEmpty == true
        ? business['company_name']!.trim()
        : 'Business';
    final taxable = (note['taxable_value'] as num?)?.toDouble() ?? 0;
    final cgst = (note['cgst_total'] as num?)?.toDouble() ?? 0;
    final sgst = (note['sgst_total'] as num?)?.toDouble() ?? 0;
    final igst = (note['igst_total'] as num?)?.toDouble() ?? 0;
    final cess = (note['cess_total'] as num?)?.toDouble() ?? 0;
    final tax = (note['tax_total'] as num?)?.toDouble() ?? cgst + sgst + igst + cess;
    final total = (note['grand_total'] as num?)?.toDouble() ?? taxable + tax;

    document.addPage(pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(32),
      build: (context) => [
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Expanded(child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(companyName, style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold)),
                if ((business['company_address'] ?? '').isNotEmpty) pw.Text(business['company_address']!),
                if ((business['company_phone'] ?? '').isNotEmpty) pw.Text('Phone: ${business['company_phone']}'),
                if ((business['company_gstin'] ?? '').isNotEmpty) pw.Text('GSTIN: ${business['company_gstin']}'),
              ],
            )),
            pw.Text('SALES DEBIT NOTE', style: pw.TextStyle(fontSize: 17, fontWeight: pw.FontWeight.bold)),
          ],
        ),
        pw.SizedBox(height: 14),
        pw.Divider(),
        pw.Text('Debit Note No: $number', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
        pw.Text('Date: $date'),
        pw.Text('Original Sales Invoice: ${note['original_number'] ?? '-'}'),
        pw.Text('Customer: ${note['party_name'] ?? 'Walk-in customer'}'),
        if ((note['party_gstin']?.toString() ?? '').isNotEmpty) pw.Text('Customer GSTIN: ${note['party_gstin']}'),
        if ((note['party_state']?.toString() ?? '').isNotEmpty) pw.Text('Customer State: ${note['party_state']}'),
        pw.Text('Place of Supply: ${note['place_of_supply'] ?? '-'}'),
        pw.Text('Tax type: ${note['tax_type'] ?? '-'}'),
        pw.Text('Reason: ${note['reason'] ?? '-'}'),
        pw.SizedBox(height: 16),
        pw.Table(
          border: pw.TableBorder.all(color: PdfColors.grey500, width: 0.5),
          columnWidths: {
            0: const pw.FlexColumnWidth(3.4),
            1: const pw.FlexColumnWidth(1.3),
            2: const pw.FlexColumnWidth(1),
            3: const pw.FlexColumnWidth(1.3),
            4: const pw.FlexColumnWidth(1.4),
            5: const pw.FlexColumnWidth(1.5),
          },
          children: [
            pw.TableRow(
              decoration: const pw.BoxDecoration(color: PdfColors.grey200),
              children: ['Description / HSN', 'Qty', 'Unit', 'Rate', 'Taxable', 'Line total']
                  .map((label) => pw.Padding(
                    padding: const pw.EdgeInsets.all(5),
                    child: pw.Text(label, style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold)),
                  )).toList(),
            ),
            ...items.map((item) => pw.TableRow(children: [
              pw.Padding(padding: const pw.EdgeInsets.all(5), child: pw.Text(
                '${item['description'] ?? ''}${(item['hsn_sac']?.toString() ?? '').isEmpty ? '' : '\nHSN/SAC: ${item['hsn_sac']}'}',
                style: const pw.TextStyle(fontSize: 8),
              )),
              _cell('${item['quantity']}'),
              _cell('${item['unit'] ?? ''}'),
              _cell(_money(item['rate'])),
              _cell(_money(item['taxable_value'])),
              _cell(_money(item['line_total'])),
            ])),
          ],
        ),
        pw.SizedBox(height: 14),
        pw.Align(
          alignment: pw.Alignment.centerRight,
          child: pw.SizedBox(width: 230, child: pw.Column(children: [
            _total('Taxable value', taxable),
            if (cgst != 0) _total('CGST', cgst),
            if (sgst != 0) _total('SGST', sgst),
            if (igst != 0) _total('IGST', igst),
            if (cess != 0) _total('Cess', cess),
            _total('Total GST', tax),
            pw.Divider(),
            _total('Debit Note Total', total, bold: true),
          ])),
        ),
        pw.SizedBox(height: 28),
        pw.Text('This is a computer-generated debit note copy. Verify the particulars and applicable GST treatment before use. This document is not a GSTN filing confirmation.',
          style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700)),
      ],
    ));

    await Printing.layoutPdf(
      onLayout: (format) async => document.save(),
      name: 'Debit-Note-$number.pdf',
    );
  }

  static pw.Widget _cell(String value) => pw.Padding(
    padding: const pw.EdgeInsets.all(5),
    child: pw.Text(value, style: const pw.TextStyle(fontSize: 8)),
  );

  static String _money(Object? value) =>
      ((value as num?)?.toDouble() ?? 0).toStringAsFixed(2);

  static pw.Widget _total(String label, double value, {bool bold = false}) {
    final style = pw.TextStyle(
      fontSize: 9,
      fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
    );
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 3),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(label, style: style),
          pw.Text('Rs. ${value.toStringAsFixed(2)}', style: style),
        ],
      ),
    );
  }
}
