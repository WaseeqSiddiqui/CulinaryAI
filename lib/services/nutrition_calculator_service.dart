import '../models/nutrition_facts.dart';
import '../models/recipe_ingredient.dart';
import '../models/recipe_nutrition.dart';
import 'nutrition_data_service.dart';
import 'unit_conversion_service.dart';

class NutritionCalculatorService {
  const NutritionCalculatorService._();

  static RecipeNutrition calculate({
    required List<RecipeIngredient> ingredients,
    required int servings,
  }) {
    if (servings <= 0) throw ArgumentError.value(servings, 'servings');
    var total = const NutritionFacts();
    for (final ingredient in ingredients) {
      final reference = NutritionDataService.find(ingredient.name);
      if (reference == null) continue;
      final grams = UnitConversionService.toGrams(
        ingredient.quantity,
        ingredient.unit,
        gramsPerPiece: reference.gramsPerPiece,
        gramsPerMilliliter: reference.gramsPerMilliliter,
      );
      total = total + reference.per100Grams.scale(grams / 100);
    }
    return RecipeNutrition(
      total: total,
      perServing: total.scale(1 / servings),
      servings: servings,
    );
  }

  static List<RecipeIngredient> scaleIngredients({
    required List<RecipeIngredient> ingredients,
    required int baseServings,
    required int targetServings,
  }) {
    if (baseServings <= 0 || targetServings <= 0) {
      throw ArgumentError('Serving counts must be positive.');
    }
    final factor = targetServings / baseServings;
    return ingredients.map((ingredient) => ingredient.scale(factor)).toList();
  }
}
