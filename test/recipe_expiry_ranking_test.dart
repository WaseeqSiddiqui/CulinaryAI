import 'package:culinary_ai/models/pantry_item_model.dart';
import 'package:culinary_ai/services/recipe_recommendation_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  PantryItemModel item(
    String name,
    DateTime? expiry, {
    double quantity = 1,
    String unit = 'pcs',
  }) => PantryItemModel(
    id: name,
    householdId: 'h',
    name: name,
    quantity: quantity,
    unit: unit,
    location: 'Fridge',
    updatedAt: DateTime(2026, 10, 17),
    expiryDate: expiry,
  );

  test('recipes using soon-to-expire stock receive a zero-waste boost', () {
    final recipes = RecipeRecommendationService.getRecommendedList([
      item(
        'Egg',
        DateTime.now().add(const Duration(days: 1)),
        quantity: 4,
      ),
      item(
        'Bread',
        DateTime.now().add(const Duration(days: 1)),
        quantity: 4,
      ),
      item('Olive Oil', null, quantity: 15, unit: 'ml'),
    ]);
    expect(recipes.first.id, 'rec_avocado_toast');
  });

  test('expired ingredients are not counted as pantry matches', () {
    final recipe = RecipeRecommendationService.catalog.firstWhere(
      (value) => value.id == 'rec_farmhouse_frittata',
    );
    expect(
      recipe.inPantryIngredients([
        item(
          'Egg',
          DateTime.now().subtract(const Duration(days: 1)),
          quantity: 6,
        ),
      ]),
      isEmpty,
    );
  });

  test('pantry-first recommendations exclude recipes with no usable match', () {
    final recipes = RecipeRecommendationService.getRecommendedList([
      item('Fish', null, quantity: 600, unit: 'g'),
    ]);

    expect(recipes, isNotEmpty);
    expect(
      recipes.every(
        (recipe) =>
            recipe.matchedCount([
              item('Fish', null, quantity: 600, unit: 'g'),
            ]) >
            0,
      ),
      isTrue,
    );
  });

  test('per-person meal calorie target changes offline ranking', () {
    final recipes = RecipeRecommendationService.getRecommendedList(
      const [],
      targetCaloriesPerMeal: 340,
    );

    expect(recipes.first.id, 'rec_avocado_toast');
  });
}
