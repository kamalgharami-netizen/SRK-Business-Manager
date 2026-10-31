/// Reconciles a linked invoice against its synced payment records.
///
/// The invoice record is synced before payment records are downloaded. Its
/// amount_paid snapshot may therefore already include the incoming payment.
/// Taking the greater of the invoice snapshot and the known allocation total
/// avoids double-counting while repairing a stale lower snapshot.
class PaymentReconciliation {
  PaymentReconciliation._();

  static double calculatePaidAmount({
    required double invoicePaidSnapshot,
    required Iterable<double> existingLinkedPayments,
    required double incomingPayment,
  }) {
    if (!invoicePaidSnapshot.isFinite || invoicePaidSnapshot < 0) {
      throw ArgumentError.value(invoicePaidSnapshot, 'invoicePaidSnapshot');
    }
    if (!incomingPayment.isFinite || incomingPayment <= 0) {
      throw ArgumentError.value(incomingPayment, 'incomingPayment');
    }

    var allocatedTotal = incomingPayment;
    for (final amount in existingLinkedPayments) {
      if (!amount.isFinite || amount <= 0) {
        throw ArgumentError.value(amount, 'existingLinkedPayments');
      }
      allocatedTotal += amount;
    }
    if (!allocatedTotal.isFinite) {
      throw ArgumentError('Linked payment total is not finite.');
    }

    final reconciled = invoicePaidSnapshot > allocatedTotal
        ? invoicePaidSnapshot
        : allocatedTotal;
    return (reconciled * 100).roundToDouble() / 100;
  }
}
