import 'package:flutter_test/flutter_test.dart';
import 'package:srk_business_manager/src/data/local/payment_reconciliation.dart';

void main() {
  group('PaymentReconciliation', () {
    test('adds a cloud payment when invoice snapshot does not yet include it', () {
      final paid = PaymentReconciliation.calculatePaidAmount(
        invoicePaidSnapshot: 100,
        existingLinkedPayments: [100],
        incomingPayment: 50,
      );
      expect(paid, 150);
    });

    test('does not double-count a payment already included in invoice snapshot', () {
      final paid = PaymentReconciliation.calculatePaidAmount(
        invoicePaidSnapshot: 150,
        existingLinkedPayments: [100],
        incomingPayment: 50,
      );
      expect(paid, 150);
    });

    test('preserves an invoice paid snapshot above known payment allocations', () {
      final paid = PaymentReconciliation.calculatePaidAmount(
        invoicePaidSnapshot: 25,
        existingLinkedPayments: const [],
        incomingPayment: 5,
      );
      expect(paid, 25);
    });

    test('reconciles multiple existing payments with the incoming payment', () {
      final paid = PaymentReconciliation.calculatePaidAmount(
        invoicePaidSnapshot: 225,
        existingLinkedPayments: [50, 75],
        incomingPayment: 100,
      );
      expect(paid, 225);
    });

    test('rejects invalid invoice snapshots and payment amounts', () {
      expect(
        () => PaymentReconciliation.calculatePaidAmount(
          invoicePaidSnapshot: double.nan,
          existingLinkedPayments: const [],
          incomingPayment: 10,
        ),
        throwsArgumentError,
      );
      expect(
        () => PaymentReconciliation.calculatePaidAmount(
          invoicePaidSnapshot: 0,
          existingLinkedPayments: const [],
          incomingPayment: 0,
        ),
        throwsArgumentError,
      );
      expect(
        () => PaymentReconciliation.calculatePaidAmount(
          invoicePaidSnapshot: 10,
          existingLinkedPayments: [double.infinity],
          incomingPayment: 1,
        ),
        throwsArgumentError,
      );
    });
  });
}
