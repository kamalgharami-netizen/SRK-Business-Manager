import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'accounting_service.dart';
import 'app_database.dart';

/// Applies an existing customer/supplier advance to an outstanding invoice.
/// Allocation rows are immutable cloud entities; the source payment is retained.
class AdvanceAllocationService {
  AdvanceAllocationService._();

  static Future<int> allocate({
    required DatabaseExecutor txn,
    required int paymentId,
    required int invoiceId,
    required double amount,
    required String allocationDate,
  }) async {
    if (!amount.isFinite || amount <= 0) {
      throw ArgumentError.value(amount, 'amount', 'Allocation must be positive and finite.');
    }
    final payments = await txn.query('payments', where: 'id = ?', whereArgs: [paymentId], limit: 1);
    final invoices = await txn.query('invoices', where: 'id = ?', whereArgs: [invoiceId], limit: 1);
    if (payments.isEmpty || invoices.isEmpty) throw StateError('Advance payment or invoice was not found.');
    final payment = payments.single;
    final invoice = invoices.single;
    final type = payment['payment_type'];
    final expectedInvoiceType = type == 'receipt' ? 'sale' : type == 'payment' ? 'purchase' : null;
    if (expectedInvoiceType == null || invoice['invoice_type'] != expectedInvoiceType) {
      throw StateError('Advance and invoice transaction types do not match.');
    }
    final paymentPartyId = payment['party_id'] as int?;
    final invoicePartyId = invoice['party_id'] as int?;
    if (paymentPartyId == null || invoicePartyId == null || paymentPartyId != invoicePartyId) {
      throw StateError('Advance and invoice must belong to the same party.');
    }
    final paymentAmount = (payment['amount'] as num).toDouble();
    final allocatedRows = await txn.rawQuery(
      'SELECT COALESCE(SUM(amount), 0) AS total FROM payment_allocations WHERE payment_id = ?',
      [paymentId],
    );
    final alreadyAllocated = (allocatedRows.single['total'] as num).toDouble();
    final invoiceTotal = (invoice['grand_total'] as num).toDouble();
    final invoicePaid = ((invoice['amount_paid'] as num?) ?? 0).toDouble();
    if (!paymentAmount.isFinite || !alreadyAllocated.isFinite ||
        !invoiceTotal.isFinite || !invoicePaid.isFinite ||
        paymentAmount <= 0 || alreadyAllocated < 0 || invoiceTotal <= 0 ||
        invoicePaid < 0 || invoicePaid > invoiceTotal + 0.005) {
      throw StateError('Advance or invoice balances are invalid.');
    }
    final availableAdvance = paymentAmount - alreadyAllocated;
    final outstanding = invoiceTotal - invoicePaid;
    if (amount > availableAdvance + 0.005) {
      throw StateError('Allocation exceeds the available advance of ₹${availableAdvance.toStringAsFixed(2)}.');
    }
    if (amount > outstanding + 0.005) {
      throw StateError('Allocation exceeds the invoice due of ₹${outstanding.toStringAsFixed(2)}.');
    }
    final paymentSyncId = payment['sync_id'] as String?;
    final invoiceSyncId = invoice['sync_id'] as String?;
    if (paymentSyncId == null || paymentSyncId.isEmpty || invoiceSyncId == null || invoiceSyncId.isEmpty) {
      throw StateError('Advance and invoice must have cloud identifiers before allocation.');
    }
    final syncId = AppDatabase.instance.createSyncId();
    final allocationId = await txn.insert('payment_allocations', {
      'sync_id': syncId,
      'payment_id': paymentId,
      'invoice_id': invoiceId,
      'amount': amount,
      'allocation_date': allocationDate,
    });
    final updatedPaid = (invoicePaid + amount).clamp(0, invoiceTotal).toDouble();
    await txn.update('invoices', {
      'amount_paid': updatedPaid,
      'status': updatedPaid >= invoiceTotal - 0.005 ? 'paid' : 'partial',
    }, where: 'id = ?', whereArgs: [invoiceId]);

    await AccountingService.postAdvanceAllocation(
      txn,
      allocationId: allocationId,
      date: allocationDate,
      paymentType: type as String,
      amount: amount,
    );

    await AppDatabase.instance.enqueueSyncOperation(
      executor: txn,
      tableName: 'payment_allocations',
      recordId: syncId,
      operation: 'insert',
      payload: {
        'sync_id': syncId,
        'payment_sync_id': paymentSyncId,
        'invoice_sync_id': invoiceSyncId,
        'amount': amount,
        'allocation_date': allocationDate,
      },
    );
    return allocationId;
  }
}
