/// Reconciles an invoice's paid amount when payment records arrive from cloud sync.
///
/// The invoice snapshot may already include the incoming payment, while the
/// receiving device may have only a subset of the linked payment rows. The
/// difference between the snapshot and known payment rows is treated as the
/// opening/manual paid amount; known rows plus the incoming row are then
/// applied exactly once.
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

    var existingTotal = 0.0;
    for (final amount in existingLinkedPayments) {
      if (!amount.isFinite || amount <= 0) {
        throw ArgumentError.value(amount, 'existingLinkedPayments');
      }
      existingTotal += amount;
    }
    if (!existingTotal.isFinite) {
      throw ArgumentError('Existing linked payment total is not finite.');
    }

    final openingPaid = (invoicePaidSnapshot - existingTotal).clamp(0.0, double.infinity);
    final reconciled = openingPaid + existingTotal + incomingPayment;
    if (!reconciled.isFinite) {
      throw ArgumentError('Reconciled paid amount is not finite.');
    }
    return (reconciled * 100).roundToDouble() / 100;
  }
}
