import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'accounting_service.dart';
import 'app_database.dart';

class AdvanceAllocationService {
  AdvanceAllocationService._();

  static Future<int> allocate({required Transaction txn, required int paymentId, required int invoiceId, required double amount, required String allocationDate}) async {
    if (!amount.isFinite || amount <= 0) throw ArgumentError.value(amount, 'amount');
    final ps = await txn.query('payments', where: 'id=?', whereArgs: [paymentId], limit: 1);
    final ins = await txn.query('invoices', where: 'id=?', whereArgs: [invoiceId], limit: 1);
    if (ps.isEmpty || ins.isEmpty) throw StateError('Advance payment or invoice was not found.');
    final p = ps.single, i = ins.single;
    final type = p['payment_type'];
    if ((type == 'receipt' && i['invoice_type'] != 'sale') || (type == 'payment' && i['invoice_type'] != 'purchase') || (type != 'receipt' && type != 'payment')) throw StateError('Advance and invoice types do not match.');
    if (p['invoice_id'] != null || p['party_id'] == null || p['party_id'] != i['party_id']) throw StateError('Advance and invoice must belong to the same party; only unallocated advances are accepted.');
    final rows = await txn.rawQuery('SELECT COALESCE(SUM(amount),0) AS total FROM payment_allocations WHERE payment_id=?', [paymentId]);
    final allocated = (rows.single['total'] as num).toDouble();
    final advance = (p['amount'] as num).toDouble();
    final total = (i['grand_total'] as num).toDouble();
    final paid = ((i['amount_paid'] as num?) ?? 0).toDouble();
    if (![allocated, advance, total, paid].every((v) => v.isFinite) || allocated < 0 || advance <= 0 || total <= 0 || paid < 0 || paid > total + .005) throw StateError('Advance or invoice balance is invalid.');
    final available = advance - allocated, due = total - paid;
    if (amount > available + .005) throw StateError('Allocation exceeds available advance ₹${available.toStringAsFixed(2)}.');
    if (amount > due + .005) throw StateError('Allocation exceeds invoice due ₹${due.toStringAsFixed(2)}.');
    final paymentSyncId = p['sync_id'] as String?, invoiceSyncId = i['sync_id'] as String?;
    if (paymentSyncId == null || paymentSyncId.isEmpty || invoiceSyncId == null || invoiceSyncId.isEmpty) throw StateError('Advance and invoice need cloud identifiers.');
    final syncId = AppDatabase.instance.createSyncId();
    final id = await txn.insert('payment_allocations', {'sync_id': syncId, 'payment_id': paymentId, 'invoice_id': invoiceId, 'amount': amount, 'allocation_date': allocationDate});
    final paidAfter = (paid + amount).clamp(0, total).toDouble();
    await txn.update('invoices', {'amount_paid': paidAfter, 'status': paidAfter >= total - .005 ? 'paid' : 'partial'}, where: 'id=?', whereArgs: [invoiceId]);
    await AccountingService.postAdvanceAllocation(txn, allocationId: id, date: allocationDate, paymentType: type as String, amount: amount);
    await AppDatabase.instance.enqueueSyncOperation(executor: txn, tableName: 'payment_allocations', recordId: syncId, operation: 'insert', payload: {'sync_id': syncId, 'payment_sync_id': paymentSyncId, 'invoice_sync_id': invoiceSyncId, 'amount': amount, 'allocation_date': allocationDate});
    return id;
  }
}
