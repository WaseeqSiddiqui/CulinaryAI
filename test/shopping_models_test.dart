import 'package:culinary_ai/models/shopping_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('pending order round-trips without changing item quantities', () {
    final order = ShoppingOrder(
      id: 'order-1',
      householdId: 'home-1',
      items: const [
        ShoppingListItem(
          id: 'milk',
          name: 'Milk',
          quantity: 2,
          unit: 'L',
        ),
      ],
      status: 'pending',
      createdAt: DateTime.utc(2026, 10, 15),
    );

    final restored = ShoppingOrder.fromMap(order.toMap());

    expect(restored.status, 'pending');
    expect(restored.items.single.quantity, 2);
    expect(restored.items.single.unit, 'L');
  });
}
