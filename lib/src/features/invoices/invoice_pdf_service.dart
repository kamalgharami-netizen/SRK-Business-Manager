import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

/// Builds and opens a printable PDF copy of a saved sales invoice.
/// PDF generation is local and does not require a network connection.
class InvoicePdfService {
  static Future<void> printInvoice({
    required Map<String, Object?> invoice,
    required List<Map<String, Object?>> items,
    required Map<String, String> business,
    bool isPurchase = false,
    bool isPurchaseReturn = false,
  }) async {
    final document = pw.Document();
    final companyName = business['company_name']?.trim().isNotEmpty == true
        ? business['company_name']!.trim()
        : 'Business';
    final invoiceNumber = invoice['invoice_number']?.toString() ?? '';
    final invoiceDate =
        (invoice['invoice_date']?.toString() ?? '').split('T').first;
    final partyName = invoice['party_name']?.toString() ??
        (isPurchase ? 'Supplier not selected' : 'Walk-in customer');
    final documentTitle = isPurchaseReturn
        ? 'PURCHASE RETURN'
        : (isPurchase ? 'PURCHASE INVOICE' : 'TAX INVOICE');
    final partyLabel = (isPurchase || isPurchaseReturn) ? 'Supplier' : 'Customer';
    final subtotal = (invoice['subtotal'] as num?)?.toDouble() ?? 0;
    final tax = (invoice['tax_total'] as num?)?.toDouble() ?? 0;
    final total = (invoice['grand_total'] as num?)?.toDouble() ?? 0;
    final paid = (invoice['amount_paid'] as num?)?.toDouble() ?? 0;
    final balance = (total - paid).clamp(0, double.infinity).toDouble();

    document.addPage(pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(32),
      build: (context) => [
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Expanded(
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(
                    companyName,
                    style: const pw.TextStyle(
                      fontSize: 20,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                  if ((business['company_address'] ?? '').isNotEmpty)
                    pw.Text(business['company_address']!),
                  if ((business['company_phone'] ?? '').isNotEmpty)
                    pw.Text('Phone: ${business['company_phone']}'),
                  if ((business['company_gstin'] ?? '').isNotEmpty)
                    pw.Text('GSTIN: ${business['company_gstin']}'),
                ],
              ),
            ),
            pw.Text(
              documentTitle,
              style: const pw.TextStyle(
                fontSize: 18,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
          ],
        ),
        pw.SizedBox(height: 20),
        pw.Divider(),
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  'Invoice No: $invoiceNumber',
                  style: const pw.TextStyle(fontWeight: pw.FontWeight.bold),
                ),
                pw.Text('Date: $invoiceDate'),
                pw.Text('$partyLabel: $partyName'),
                if ((invoice['party_gstin']?.toString() ?? '').isNotEmpty)
                  pw.Text('$partyLabel GSTIN: ${invoice['party_gstin']}'),
                if ((invoice['party_state']?.toString() ?? '').isNotEmpty)
                  pw.Text('$partyLabel State: ${invoice['party_state']}'),
                if ((invoice['place_of_supply']?.toString() ?? '').isNotEmpty)
                  pw.Text('Place of Supply: ${invoice['place_of_supply']}'),
                if ((invoice['tax_type']?.toString() ?? '').isNotEmpty)
                  pw.Text('Tax type: ${invoice['tax_type']}'),
                if ((invoice['original_invoice_number']?.toString() ?? '').isNotEmpty)
                  pw.Text('Original purchase: ${invoice['original_invoice_number']}'),
              ],
            ),
            pw.Text('Status: ${invoice['status'] ?? 'unpaid'}'),
          ],
        ),
        pw.SizedBox(height: 18),
        pw.Table(
          border: pw.TableBorder.all(color: PdfColors.grey400, width: 0.5),
          columnWidths: {
            0: const pw.FlexColumnWidth(4),
            1: const pw.FlexColumnWidth(1.2),
            2: const pw.FlexColumnWidth(1.5),
            3: const pw.FlexColumnWidth(1.2),
            4: const pw.FlexColumnWidth(1.8),
          },
          children: [
            pw.TableRow(
              decoration: const pw.BoxDecoration(color: PdfColors.grey200),
              children: ['Item', 'Qty', 'Rate', 'GST %', 'Amount']
                  .map(
                    (label) => pw.Padding(
                      padding: const pw.EdgeInsets.all(7),
                      child: pw.Text(
                        label,
                        style: const pw.TextStyle(
                          fontWeight: pw.FontWeight.bold,
                          fontSize: 9,
                        ),
                      ),
                    ),
                  )
                  .toList(),
            ),
            ...items.map(
              (item) => pw.TableRow(
                children: [
                  pw.Padding(
                    padding: const pw.EdgeInsets.all(7),
                    child: pw.Text(
                      '${item['description']?.toString() ?? ''}${(item['hsn_sac']?.toString() ?? '').isEmpty ? '' : '\nHSN/SAC: ${item['hsn_sac']}'}',
                      style: const pw.TextStyle(fontSize: 9),
                    ),
                  ),
                  pw.Padding(
                    padding: const pw.EdgeInsets.all(7),
                    child: pw.Text(
                      '${item['quantity']}',
                      style: const pw.TextStyle(fontSize: 9),
                    ),
                  ),
                  pw.Padding(
                    padding: const pw.EdgeInsets.all(7),
                    child: pw.Text(
                      'Rs. ${((item['rate'] as num?)?.toDouble() ?? 0).toStringAsFixed(2)}',
                      style: const pw.TextStyle(fontSize: 9),
                    ),
                  ),
                  pw.Padding(
                    padding: const pw.EdgeInsets.all(7),
                    child: pw.Text(
                      '${item['gst_rate']}%',
                      style: const pw.TextStyle(fontSize: 9),
                    ),
                  ),
                  pw.Padding(
                    padding: const pw.EdgeInsets.all(7),
                    child: pw.Text(
                      'Rs. ${((item['line_total'] as num?)?.toDouble() ?? 0).toStringAsFixed(2)}',
                      style: const pw.TextStyle(fontSize: 9),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        pw.SizedBox(height: 16),
        pw.Align(
          alignment: pw.Alignment.centerRight,
          child: pw.SizedBox(
            width: 220,
            child: pw.Column(
              children: [
                _totalLine('Taxable subtotal', subtotal),
                _totalLine('GST', tax),
                _totalLine('CGST', (invoice['cgst_total'] as num?)?.toDouble() ?? 0),
                _totalLine('SGST', (invoice['sgst_total'] as num?)?.toDouble() ?? 0),
                _totalLine('IGST', (invoice['igst_total'] as num?)?.toDouble() ?? 0),
                pw.Divider(),
                _totalLine(isPurchaseReturn ? 'Return total' : 'Grand total', total, bold: true),
                if (!isPurchaseReturn) ...[
                  _totalLine('Amount received', paid),
                  _totalLine('Balance due', balance, bold: true),
                ],
              ],
            ),
          ),
        ),
        if ((invoice['notes']?.toString() ?? '').trim().isNotEmpty) ...[
          pw.SizedBox(height: 18),
          pw.Text('Notes: ${invoice['notes']}'),
        ],
        pw.SizedBox(height: 30),
        pw.Text(
          'This is a computer-generated invoice.',
          style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700),
        ),
      ],
    ));

    await Printing.layoutPdf(
      onLayout: (format) async => document.save(),
      name: '${isPurchaseReturn ? 'Purchase-Return' : (isPurchase ? 'Purchase' : 'Invoice')}-$invoiceNumber.pdf',
    );
  }

  static pw.Widget _totalLine(String label, double value, {bool bold = false}) {
    final style = pw.TextStyle(
      fontSize: 10,
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
