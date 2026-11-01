import 'package:flutter_test/flutter_test.dart';
import 'package:srk_business_manager/src/data/local/inventory_cost_service.dart';

void main() {
  group('Purchase inventory cost and ITC treatment', () {
    test('keeps eligible GST outside FIFO inventory unit cost', () {
      expect(
        InventoryCostService.purchaseInventoryUnitCost(
          unitRate: 100,
          taxAmount: 18,
          quantity: 2,
          itcIneligible: false,
        ),
        100,
      );
    });

    test('capitalises ineligible GST into FIFO inventory unit cost', () {
      expect(
        InventoryCostService.purchaseInventoryUnitCost(
          unitRate: 100,
          taxAmount: 36,
          quantity: 2,
          itcIneligible: true,
        ),
        118,
      );
    });

    test('rejects invalid purchase cost inputs', () {
      expect(
        () => InventoryCostService.purchaseInventoryUnitCost(
          unitRate: 100,
          taxAmount: 18,
          quantity: 0,
          itcIneligible: true,
        ),
        throwsA(isA<StateError>()),
      );
      expect(
        () => InventoryCostService.purchaseInventoryUnitCost(
          unitRate: double.infinity,
          taxAmount: 18,
          quantity: 1,
          itcIneligible: true,
        ),
        throwsA(isA<StateError>()),
      );
    });
  });
}
