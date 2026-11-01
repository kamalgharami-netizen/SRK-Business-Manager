import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Creates balanced, source-linked double-entry journal entries.
class AccountingService {
  AccountingService._();

  static Future<void> postSalesInvoice(Transaction txn, {required int invoiceId, required String invoiceNumber, required String date, required double subtotal, required double tax, required double total, double costOfGoodsSold = 0}) async {
    final lines = <Map<String, Object?>>[
      if (total > 0) {'code': '1100', 'debit': total, 'credit': 0.0, 'description': 'Customer receivable'},
      if (subtotal > 0) {'code': '4000', 'debit': 0.0, 'credit': subtotal, 'description': 'Sales revenue'},
      if (tax > 0) {'code': '2100', 'debit': 0.0, 'credit': tax, 'description': 'Output GST payable'},
      if (costOfGoodsSold > 0) {'code': '5000', 'debit': costOfGoodsSold, 'credit': 0.0, 'description': 'FIFO cost of goods sold'},
      if (costOfGoodsSold > 0) {'code': '1200', 'debit': 0.0, 'credit': costOfGoodsSold, 'description': 'Inventory issued at FIFO cost'},
    ];
    await _post(txn, sourceType: 'sales_invoice', sourceId: invoiceId, date: date, memo: 'Sales invoice $invoiceNumber', lines: lines);
  }


  static Future<void> postSalesReturn(Transaction txn, {
    required int returnId,
    required String returnNumber,
    required String date,
    required double subtotal,
    required double tax,
    required double total,
    required double costOfGoodsReturned,
  }) async {
    final lines = <Map<String, Object?>>[
      if (subtotal > 0) {'code': '4000', 'debit': subtotal, 'credit': 0.0, 'description': 'Sales revenue reversed'},
      if (tax > 0) {'code': '2100', 'debit': tax, 'credit': 0.0, 'description': 'Output GST reversed'},
      if (total > 0) {'code': '1100', 'debit': 0.0, 'credit': total, 'description': 'Customer credit for sales return'},
      if (costOfGoodsReturned > 0) {'code': '1200', 'debit': costOfGoodsReturned, 'credit': 0.0, 'description': 'Returned goods restored to inventory at original FIFO cost'},
      if (costOfGoodsReturned > 0) {'code': '5000', 'debit': 0.0, 'credit': costOfGoodsReturned, 'description': 'Cost of goods sold reversed'},
    ];
    await _post(txn, sourceType: 'sales_return', sourceId: returnId, date: date, memo: 'Sales return $returnNumber', lines: lines);
  }

  static Future<void> postPurchaseInvoice(
    Transaction txn, {
    required int invoiceId,
    required String invoiceNumber,
    required String date,
    required double subtotal,
    required double tax,
    required double total,
    required String itcTreatment,
  }) async {
    if (!subtotal.isFinite || subtotal < 0 ||
        !tax.isFinite || tax < 0 ||
        !total.isFinite || total < 0 ||
        (total - subtotal - tax).abs() > 0.005) {
      throw StateError('Purchase invoice totals are invalid or do not balance.');
    }
    if (!const {'eligible', 'ineligible', 'pendingReview'}.contains(itcTreatment)) {
      throw StateError('Purchase ITC treatment must be assessed before posting.');
    }
    final lines = <Map<String, Object?>>[
      if (subtotal > 0 || (tax > 0 && itcTreatment == 'ineligible'))
        {
          'code': '1200',
          'debit': subtotal + (itcTreatment == 'ineligible' ? tax : 0),
          'credit': 0.0,
          'description': itcTreatment == 'ineligible'
              ? 'Inventory acquired including non-recoverable GST'
              : 'Inventory acquired',
        },
      if (tax > 0 && itcTreatment == 'eligible')
        {'code': '1300', 'debit': tax, 'credit': 0.0, 'description': 'Eligible input GST'},
      if (tax > 0 && itcTreatment == 'pendingReview')
        {'code': '1310', 'debit': tax, 'credit': 0.0, 'description': 'Input GST pending eligibility review'},
      if (total > 0)
        {'code': '2000', 'debit': 0.0, 'credit': total, 'description': 'Supplier payable'},
    ];
    await _post(
      txn,
      sourceType: 'purchase_invoice',
      sourceId: invoiceId,
      date: date,
      memo: 'Purchase invoice $invoiceNumber',
      lines: lines,
    );
  }

  static Future<void> postPurchaseReturn(Transaction txn, {required int returnId, required String returnNumber, required String date, required double subtotal, required double tax, required double total}) async {
    final lines = <Map<String, Object?>>[
      if (total > 0) {'code': '2000', 'debit': total, 'credit': 0.0, 'description': 'Supplier payable reduced'},
      if (subtotal > 0) {'code': '1200', 'debit': 0.0, 'credit': subtotal, 'description': 'Inventory returned to supplier'},
      if (tax > 0) {'code': '1300', 'debit': 0.0, 'credit': tax, 'description': 'Input GST reversed'},
    ];
    await _post(txn, sourceType: 'purchase_return', sourceId: returnId, date: date, memo: 'Purchase return $returnNumber', lines: lines);
  }

  static Future<void> postStockAdjustment(Transaction txn, {required int movementId, required String date, required String reason, required double quantityChange, required double inventoryCost}) async {
    if (!inventoryCost.isFinite || inventoryCost < 0 || quantityChange == 0) {
      throw StateError('Stock adjustment accounting values are invalid.');
    }
    if (inventoryCost <= 0) return;
    final isIncrease = quantityChange > 0;
    final lines = isIncrease
        ? <Map<String, Object?>>[
            {'code': '1200', 'debit': inventoryCost, 'credit': 0.0, 'description': 'Inventory added by adjustment'},
            {'code': '4100', 'debit': 0.0, 'credit': inventoryCost, 'description': 'Stock adjustment gain: $reason'},
          ]
        : <Map<String, Object?>>[
            {'code': '5200', 'debit': inventoryCost, 'credit': 0.0, 'description': 'Stock adjustment loss: $reason'},
            {'code': '1200', 'debit': 0.0, 'credit': inventoryCost, 'description': 'Inventory removed by adjustment'},
          ];
    await _post(txn, sourceType: 'stock_adjustment', sourceId: movementId, date: date, memo: 'Stock adjustment: $reason', lines: lines);
  }

  static Future<void> postPayment(Transaction txn, {required int paymentId, required String date, required String paymentType, required String mode, required double amount, required String? reference}) async {
    final cashCode = mode.toLowerCase() == 'cash' ? '1000' : '1010';
    final isReceipt = paymentType == 'receipt';
    final lines = <Map<String, Object?>>[
      if (isReceipt) ...[
        {'code': cashCode, 'debit': amount, 'credit': 0.0, 'description': 'Money received'},
        {'code': '1100', 'debit': 0.0, 'credit': amount, 'description': 'Customer balance reduced'},
      ] else ...[
        {'code': '2000', 'debit': amount, 'credit': 0.0, 'description': 'Supplier balance reduced'},
        {'code': cashCode, 'debit': 0.0, 'credit': amount, 'description': 'Money paid'},
      ],
    ];
    await _post(txn, sourceType: isReceipt ? 'receipt' : 'payment', sourceId: paymentId, date: date, memo: reference?.trim().isNotEmpty == true ? reference!.trim() : (isReceipt ? 'Customer receipt' : 'Supplier payment'), lines: lines);
  }

  static Future<void> postExpense(Transaction txn, {required int expenseId, required String date, required String category, required String description, required String mode, required double amount}) async {
    final cashCode = mode.toLowerCase() == 'cash' ? '1000' : '1010';
    await _post(txn, sourceType: 'expense', sourceId: expenseId, date: date, memo: '$category: $description', lines: [
      {'code': '5200', 'debit': amount, 'credit': 0.0, 'description': category},
      {'code': cashCode, 'debit': 0.0, 'credit': amount, 'description': 'Expense paid'},
    ]);
  }

  static Future<void> voidSource(Transaction txn, {required String sourceType, required int sourceId}) async {
    await txn.update('journal_entries', {'status': 'void'}, where: 'source_type = ? AND source_id = ? AND status = ?', whereArgs: [sourceType, sourceId, 'posted']);
  }

  static Future<void> _post(Transaction txn, {required String sourceType, required int sourceId, required String date, required String memo, required List<Map<String, Object?>> lines}) async {
    final existing = await txn.query(
      'journal_entries',
      columns: ['id'],
      where: 'source_type = ? AND source_id = ? AND status = ?',
      whereArgs: [sourceType, sourceId, 'posted'],
      limit: 1,
    );
    if (existing.isNotEmpty) {
      throw StateError('This source transaction already has a posted journal entry. Void the existing entry before reposting.');
    }
    if (sourceId <= 0) throw StateError('A journal source ID must be positive.');
    if (lines.length < 2) throw StateError('A journal entry must contain at least two ledger lines.');
    for (final line in lines) {
      final debitValue = line['debit'];
      final creditValue = line['credit'];
      if (debitValue is! num || creditValue is! num ||
          !debitValue.toDouble().isFinite || !creditValue.toDouble().isFinite ||
          debitValue < 0 || creditValue < 0 ||
          ((debitValue > 0) == (creditValue > 0))) {
        throw StateError('Each journal line must have one finite, non-negative debit or credit amount.');
      }
    }
    final debit = lines.fold<double>(0, (sum, line) => sum + (line['debit'] as num).toDouble());
    final credit = lines.fold<double>(0, (sum, line) => sum + (line['credit'] as num).toDouble());
    if (!debit.isFinite || !credit.isFinite || debit <= 0 || (debit - credit).abs() > 0.005) {
      throw StateError('Journal entry is not balanced. Debit and credit must match.');
    }
    final entryId = await txn.insert('journal_entries', {
      'entry_number': 'JE-${DateTime.now().microsecondsSinceEpoch}',
      'entry_date': date,
      'source_type': sourceType,
      'source_id': sourceId,
      'memo': memo,
      'status': 'draft',
    });
    for (final line in lines) {
      final account = await txn.query('accounts', columns: ['id'], where: 'account_code = ? AND is_active = 1', whereArgs: [line['code']], limit: 1);
      if (account.isEmpty) throw StateError('Required ledger account ${line['code']} is missing or inactive.');
      await txn.insert('journal_lines', {
        'journal_entry_id': entryId,
        'account_id': account.first['id'],
        'description': line['description'],
        'debit': line['debit'],
        'credit': line['credit'],
      });
    }
    await txn.update('journal_entries', {'status': 'posted'}, where: 'id = ?', whereArgs: [entryId]);
  }
}
