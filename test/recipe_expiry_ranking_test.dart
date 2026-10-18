import 'package:culinary_ai/models/pantry_item_model.dart';
import 'package:culinary_ai/services/recipe_recommendation_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  PantryItemModel item(String name, DateTime? expiry) => PantryItemModel(
    id: name,
    householdId: 'h',
    name: name,
    quantity: 2,
    unit: 'pcs',
    location: 'Fridge',
    updatedAt: DateTime(2026, 10, 17),
    expiryDate: expiry,
  );

  test('recipes using soon-to-expire stock receive a zero-waste boost', () {
    final recipes = RecipeRecommendationService.getRecommendedList([
      item('Egg', DateTime.now().add(const Duration(days: 1))),
      item('Bread', DateTime.now().add(const Duration(days: 1))),
      item('Olive Oil', null),
    ]);
    expect(recipes.first.id, 'rec_avocado_toast');
  });

  test('expired ingredients are not counted as pantry matches', () {
    final recipe = RecipeRecommendationService.catalog.firstWhere(
      (value) => value.id == 'rec_farmhouse_frittata',
    );
    expect(
      recipe.inPantryIngredients([
        item('Egg', DateTime.now().subtract(const Duration(days: 1))),
      ]),
      isEmpty,
    );
  });

  test('pantry-first recommendations exclude recipes with no usable match', () {
    final recipes = RecipeRecommendationService.getRecommendedList([
      item('Fish', null),
    ]);

    expect(recipes, isNotEmpty);
    expect(
      recipes.every((recipe) => recipe.matchedCount([item('Fish', null)]) > 0),
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
