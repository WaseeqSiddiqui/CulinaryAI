import 'package:culinary_ai/models/store_models.dart';
import 'package:culinary_ai/services/automation_failure_guard.dart';
import 'package:culinary_ai/services/cart_comparison.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('cart comparison', () {
    const intendedMilk = AutomationItemResult(
      wantedItemId: 'shopping-milk',
      wantedName: 'Milk',
      wantedQuantity: 2,
      wantedUnit: 'L',
      status: AddStatus.added,
      reason: 'Added',
      productName: 'Fresh Milk 1L',
      unitsAdded: 2,
      unitPrice: 300,
    );

    test('verifies an exact product and quantity match', () {
      final result = compareCart(
        const [intendedMilk],
        const [CartLine(name: 'Fresh Milk 1L', quantity: 2, price: 300)],
      );

      expect(result.matched, hasLength(1));
      expect(result.missing, isEmpty);
      expect(result.quantityMismatches, isEmpty);
      expect(result.unexpected, isEmpty);
      expect(result.isVerified, isTrue);
    });

    test('reports an intended product that is missing from the cart', () {
      final result = compareCart(const [intendedMilk], const []);

      expect(result.matched, isEmpty);
      expect(result.missing, ['Milk']);
      expect(result.isVerified, isFalse);
    });

    test('reports a quantity below the intended quantity', () {
      final result = compareCart(
        const [intendedMilk],
        const [CartLine(name: 'Fresh Milk 1L', quantity: 1, price: 300)],
      );

      expect(result.matched, isEmpty);
      expect(result.missing, isEmpty);
      expect(result.quantityMismatches, hasLength(1));
      expect(result.quantityMismatches.single.name, 'Milk');
      expect(result.quantityMismatches.single.expected, 2);
      expect(result.quantityMismatches.single.actual, 1);
      expect(result.isVerified, isFalse);
    });

    test('reports a quantity above the intended quantity', () {
      final result = compareCart(
        const [intendedMilk],
        const [CartLine(name: 'Fresh Milk 1L', quantity: 3, price: 300)],
      );

      expect(result.matched, isEmpty);
      expect(result.quantityMismatches, hasLength(1));
      expect(result.quantityMismatches.single.expected, 2);
      expect(result.quantityMismatches.single.actual, 3);
      expect(result.isVerified, isFalse);
    });

    test('verifies the quantity delta above a pre-existing cart line', () {
      final result = compareCart(
        const [intendedMilk],
        const [CartLine(name: 'Fresh Milk 1L', quantity: 3, price: 300)],
        baseline: const [
          CartLine(name: 'Fresh Milk 1L', quantity: 1, price: 300),
        ],
      );

      expect(result.matched, hasLength(1));
      expect(result.missing, isEmpty);
      expect(result.quantityMismatches, isEmpty);
      expect(result.unexpected, isEmpty);
      expect(result.isVerified, isTrue);
    });

    test('does not report an unchanged pre-existing line as unexpected', () {
      final result = compareCart(
        const [intendedMilk],
        const [
          CartLine(name: 'Bananas 1kg', quantity: 1, price: 250),
          CartLine(name: 'Fresh Milk 1L', quantity: 2, price: 300),
        ],
        baseline: const [
          CartLine(name: 'Bananas 1kg', quantity: 1, price: 250),
        ],
      );

      expect(result.unexpected, isEmpty);
      expect(result.isVerified, isTrue);
    });

    test('reports and rejects a newly introduced unexpected cart line', () {
      final result = compareCart(
        const [intendedMilk],
        const [
          CartLine(name: 'Fresh Milk 1L', quantity: 2, price: 300),
          CartLine(name: 'Potato Chips', quantity: 1, price: 150),
        ],
      );

      expect(result.unexpected, hasLength(1));
      expect(result.unexpected.single.name, 'Potato Chips');
      expect(result.isVerified, isFalse);
    });

    test('does not confuse products with different pack sizes', () {
      final result = compareCart(
        const [intendedMilk],
        const [CartLine(name: 'Fresh Milk 2L', quantity: 2, price: 500)],
      );
      expect(result.isVerified, isFalse);
      expect(result.missing, ['Milk']);
    });

    test(
      'adds quantities when two shopping rows resolve to the same product',
      () {
        final result = compareCart(
          const [intendedMilk, intendedMilk],
          const [CartLine(name: 'Fresh Milk 1L', quantity: 5, price: 300)],
          baseline: const [
            CartLine(name: 'Fresh Milk 1L', quantity: 1, price: 300),
          ],
        );
        expect(result.isVerified, isTrue);
        expect(result.matched.single.quantity, 5);
      },
    );

    test('rejects changed or removed pre-existing cart items', () {
      const baseline = [CartLine(name: 'Bananas 1kg', quantity: 1, price: 250)];
      final changed = compareCart(
        const [intendedMilk],
        const [
          CartLine(name: 'Fresh Milk 1L', quantity: 2, price: 300),
          CartLine(name: 'Bananas 1kg', quantity: 2, price: 250),
        ],
        baseline: baseline,
      );
      expect(changed.isVerified, isFalse);
      expect(changed.quantityMismatches.single.name, 'Bananas 1kg');
      final removed = compareCart(
        const [intendedMilk],
        const [CartLine(name: 'Fresh Milk 1L', quantity: 2, price: 300)],
        baseline: baseline,
      );
      expect(removed.isVerified, isFalse);
      expect(removed.missing, contains('Bananas 1kg'));
    });
  });

  group('automation failure guard', () {
    test('stops at three consecutive selector failures', () {
      final guard = AutomationFailureGuard();

      expect(guard.record(selectorSucceeded: false), isFalse);
      expect(guard.record(selectorSucceeded: false), isFalse);
      expect(guard.record(selectorSucceeded: false), isTrue);
      expect(guard.consecutiveFailures, 3);
    });

    test('a successful selector and explicit reset both clear failures', () {
      final guard = AutomationFailureGuard();

      guard.record(selectorSucceeded: false);
      guard.record(selectorSucceeded: false);
      expect(guard.consecutiveFailures, 2);

      expect(guard.record(selectorSucceeded: true), isFalse);
      expect(guard.consecutiveFailures, 0);

      guard.record(selectorSucceeded: false);
      guard.reset();
      expect(guard.consecutiveFailures, 0);
      expect(guard.record(selectorSucceeded: false), isFalse);
    });
  });
}
