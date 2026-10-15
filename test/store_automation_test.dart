import 'package:culinary_ai/models/store_models.dart';
import 'package:culinary_ai/services/automation_failure_guard.dart';
import 'package:culinary_ai/services/cart_comparison.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('cart comparison reports added products missing from cart', () {
    const intended = [
      AutomationItemResult(
        wantedName: 'Milk',
        wantedQuantity: 2,
        wantedUnit: 'L',
        status: AddStatus.added,
        reason: 'Added',
        productName: 'Fresh Milk 1L',
        unitsAdded: 2,
      ),
    ];
    final result = compareCart(intended, const []);
    expect(result.missing, ['Milk']);
  });

  test('selector guard stops at three consecutive failures and resets', () {
    final guard = AutomationFailureGuard();
    expect(guard.record(selectorSucceeded: false), isFalse);
    expect(guard.record(selectorSucceeded: true), isFalse);
    expect(guard.record(selectorSucceeded: false), isFalse);
    expect(guard.record(selectorSucceeded: false), isFalse);
    expect(guard.record(selectorSucceeded: false), isTrue);
  });
}
