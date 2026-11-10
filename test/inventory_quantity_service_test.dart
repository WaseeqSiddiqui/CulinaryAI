import 'package:culinary_ai/models/pantry_item_model.dart';
import 'package:culinary_ai/models/recipe_ingredient.dart';
import 'package:culinary_ai/services/inventory_quantity_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  PantryItemModel item(String name, double quantity, String unit) =>
      PantryItemModel(
        id: '$name-$unit',
        householdId: 'home',
        name: name,
        quantity: quantity,
        unit: unit,
        location: 'Pantry Shelf',
        updatedAt: DateTime(2026),
      );

  test('converts common compatible recipe units exactly', () {
    expect(
      InventoryQuantityService.convert(
        quantity: 2,
        fromUnit: 'tbsp',
        toUnit: 'ml',
        ingredientName: 'Mustard Sauce',
      ),
      30,
    );
    expect(
      InventoryQuantityService.convert(
        quantity: 1.5,
        fromUnit: 'kg',
        toUnit: 'g',
        ingredientName: 'Rice',
      ),
      1500,
    );
  });

  test('uses ingredient-specific density and refuses unknown density', () {
    expect(
      InventoryQuantityService.convert(
        quantity: 103,
        fromUnit: 'g',
        toUnit: 'ml',
        ingredientName: 'Milk',
      ),
      closeTo(100, 0.0001),
    );
    expect(
      InventoryQuantityService.convert(
        quantity: 100,
        fromUnit: 'g',
        toUnit: 'ml',
        ingredientName: 'Mystery Powder',
      ),
      isNull,
    );
  });

  test('availability is quantity-aware across multiple pantry records', () {
    final check = InventoryQuantityService.availability(
      const RecipeIngredient(name: 'Milk', quantity: 750, unit: 'ml'),
      [item('Whole Milk', 0.5, 'L'), item('Milk', 300, 'ml')],
    );

    expect(check.isSufficient, isTrue);
    expect(check.availableInRecipeUnit, 800);
    expect(check.allocations, hasLength(2));
  });
}
