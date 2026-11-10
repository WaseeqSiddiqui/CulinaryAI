import 'package:culinary_ai/models/recipe_ingredient.dart';
import 'package:culinary_ai/providers/pantry_provider.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<PantryProvider> pantryFor(String householdId) async {
    SharedPreferences.setMockInitialValues({});
    final pantry = PantryProvider()..bindHousehold(householdId);
    for (var attempt = 0; attempt < 20 && !pantry.hasLoaded; attempt++) {
      await Future<void>.delayed(const Duration(milliseconds: 1));
    }
    return pantry;
  }

  test('deducts only the converted amount from a partially used bottle', () async {
    final pantry = await pantryFor('household-1');
    pantry.addItem(
      householdId: 'household-1',
      name: 'Mustard Sauce',
      quantity: 1000,
      unit: 'ml',
      location: 'Pantry Shelf',
      packageType: 'Bottle',
      packageCount: 1,
      quantityPerPackage: 1000,
    );

    final result = await pantry.consumeIngredients(
      ingredients: const [
        RecipeIngredient(name: 'Mustard Sauce', quantity: 2, unit: 'tbsp'),
      ],
      recipeId: 'mustard-chicken',
      recipeTitle: 'Mustard Chicken',
      actorId: 'cook-1',
    );

    final sauce = pantry.allItems.single;
    expect(result.changedItems, 1);
    expect(sauce.quantity, closeTo(970, 0.0001));
    expect(sauce.packageCount, 1);
    expect(sauce.isOpened, isTrue);
  });

  test('combines compatible stock and never allows a negative balance', () async {
    final pantry = await pantryFor('household-2');
    pantry.addItem(
      householdId: 'household-2',
      name: 'Basmati Rice',
      quantity: 1,
      unit: 'kg',
      location: 'Pantry Shelf',
    );
    pantry.addItem(
      householdId: 'household-2',
      name: 'Rice',
      quantity: 750,
      unit: 'g',
      location: 'Pantry Shelf',
    );

    await pantry.consumeIngredients(
      ingredients: const [
        RecipeIngredient(name: 'Rice', quantity: 1500, unit: 'g'),
      ],
      recipeId: 'rice',
      recipeTitle: 'Rice',
    );

    final remainingGrams = pantry.allItems.fold<double>(0, (total, item) {
      return total + (item.unit == 'kg' ? item.quantity * 1000 : item.quantity);
    });
    expect(remainingGrams, closeTo(250, 0.0001));

    expect(
      () => pantry.consumeIngredients(
        ingredients: const [
          RecipeIngredient(name: 'Rice', quantity: 300, unit: 'g'),
        ],
        recipeId: 'more-rice',
        recipeTitle: 'More Rice',
      ),
      throwsA(isA<StateError>()),
    );
  });
}
