import 'nutrition_facts.dart';

class RecipeNutrition {
  final NutritionFacts total;
  final NutritionFacts perServing;
  final int servings;

  const RecipeNutrition({
    required this.total,
    required this.perServing,
    required this.servings,
  });
}
