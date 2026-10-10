import 'package:culinary_ai/providers/pantry_provider.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('recipe ingredients are deducted only when requested', () {
    final pantry = PantryProvider();
    pantry.addItem(
      householdId: 'household-1',
      name: 'Basmati Rice',
      quantity: 1,
      unit: 'kg',
      location: 'Pantry Shelf',
    );
    pantry.addItem(
      householdId: 'household-1',
      name: 'Garlic Cloves',
      quantity: 5,
      unit: 'pcs',
      location: 'Pantry Shelf',
    );

    expect(pantry.allItems.first.quantity, 1);
    final changed = pantry.deductIngredients(['Rice', 'Garlic']);

    expect(changed, 2);
    expect(
      pantry.allItems
          .firstWhere((item) => item.name == 'Basmati Rice')
          .quantity,
      0.8,
    );
    expect(
      pantry.allItems
          .firstWhere((item) => item.name == 'Garlic Cloves')
          .quantity,
      4,
    );
  });
}
