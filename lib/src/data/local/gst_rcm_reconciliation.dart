import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Read-only reconciliation of recorded reverse-charge liabilities and
/// their challan/cash-ledger payment records. This is not a GSTN cash-ledger
/// balance check and does not create accounting journals.
class GstRcmReconciliation {
  GstRcmReconciliation._();

  static Future<Map<String, Object?>> load(
    DatabaseExecutor db, {
    String? startDate,
    String? endDate,
  }) async {
    final startPeriod = startDate == null ? null : startDate.substring(0, 7);
    final endPeriod = endDate == null ? null : endDate.substring(0, 7);
    final where = <String>[];
    final args = <Object?>[];
    if (startPeriod != null) {
      where.add('return_period >= ?');
      args.add(startPeriod);
    }
    if (endPeriod != null) {
      where.add('return_period <= ?');
      args.add(endPeriod);
    }
    final liabilities = await db.query(
      'gst_rcm_liabilities',
      where: where.isEmpty ? null : where.join(' AND '),
      whereArgs: where.isEmpty ? null : args,
      orderBy: 'return_period, id',
    );
    final ids = liabilities.map((row) => row['id'] as int).toSet();
    final payments = ids.isEmpty
        ? <Map<String, Object?>>[]
        : await db.query(
            'gst_rcm_payments',
            where: 'liability_id IN (${List.filled(ids.length, '?').join(',')})',
            whereArgs: ids.toList(),
            orderBy: 'payment_date, id',
          );

    const heads = ['igst', 'cgst', 'sgst', 'cess'];
    final paidByLiability = <int, Map<String, double>>{};
    for (final payment in payments) {
      final id = payment['liability_id'] as int;
      final paid = paidByLiability.putIfAbsent(
        id, () => {for (final head in heads) head: 0.0},
      );
      for (final head in heads) {
        final amount = (payment[head] as num).toDouble();
        final next = paid[head]! + amount;
        if (!amount.isFinite || amount < 0 || !next.isFinite) {
          throw StateError('RCM payment amounts contain an invalid or overflowing value.');
        }
        paid[head] = next;
      }
    }

    var liabilityTotal = 0.0;
    var paidTotal = 0.0;
    var outstandingTotal = 0.0;
    var overpaidCount = 0;
    var unpaidCount = 0;
    var fullyPaidCount = 0;
    for (final liability in liabilities) {
      final id = liability['id'] as int;
      final paid = paidByLiability[id] ?? const <String, double>{};
      var liabilityAmount = 0.0;
      var paymentAmount = 0.0;
      var overpaid = false;
      var outstanding = 0.0;
      for (final head in heads) {
        final due = (liability[head] as num).toDouble();
        final received = paid[head] ?? 0.0;
        if (!due.isFinite || due < 0 || !received.isFinite) {
          throw StateError('RCM liability contains an invalid amount.');
        }
        liabilityAmount += due;
        paymentAmount += received;
        final balance = due - received;
        if (balance < -0.01) overpaid = true;
        if (balance > 0.01) outstanding += balance;
      }
      if (![liabilityAmount, paymentAmount, outstanding].every((v) => v.isFinite)) {
        throw StateError('RCM reconciliation totals exceed the supported numeric range.');
      }
      liabilityTotal += liabilityAmount;
      paidTotal += paymentAmount;
      outstandingTotal += outstanding;
      if (overpaid) overpaidCount++;
      if (outstanding > 0.01) unpaidCount++;
      if (!overpaid && outstanding <= 0.01) fullyPaidCount++;
    }

    final auditWhere = <String>[];
    final auditArgs = <Object?>[];
    if (startPeriod != null) {
      auditWhere.add('return_period >= ?');
      auditArgs.add(startPeriod);
    }
    if (endPeriod != null) {
      auditWhere.add('return_period <= ?');
      auditArgs.add(endPeriod);
    }
    final auditRows = await db.rawQuery(
      'SELECT COUNT(*) AS count FROM gst_rcm_audit${auditWhere.isEmpty ? '' : ' WHERE ${auditWhere.join(' AND ')}'}',
      auditArgs,
    );
    final difference = liabilityTotal - paidTotal - outstandingTotal;
    final allFinite = [liabilityTotal, paidTotal, outstandingTotal, difference].every((v) => v.isFinite);
    return {
      'liability_count': liabilities.length,
      'payment_count': payments.length,
      'liability_total': liabilityTotal,
      'paid_total': paidTotal,
      'outstanding_total': outstandingTotal,
      'overpaid_count': overpaidCount,
      'unpaid_count': unpaidCount,
      'fully_paid_count': fullyPaidCount,
      'audit_event_count': (auditRows.single['count'] as num).toInt(),
      'is_reconciled': allFinite && overpaidCount == 0 &&
          (difference).abs() <= 0.01,
    };
  }
}
