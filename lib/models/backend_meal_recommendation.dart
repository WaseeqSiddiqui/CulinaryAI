import 'recipe_ingredient.dart';
import 'recipe_recommendation_model.dart';

class BackendMealRecommendation {
  final RecipeRecommendationModel recipe;
  final int pantryMatchPercent;
  final double retrievalScore;
  final List<String> availableIngredients;
  final List<String> missingIngredients;
  final String source;

  const BackendMealRecommendation({
    required this.recipe,
    required this.pantryMatchPercent,
    required this.retrievalScore,
    required this.availableIngredients,
    required this.missingIngredients,
    required this.source,
  });

  factory BackendMealRecommendation.fromJson(Map<String, dynamic> json) {
    final ingredientRecords = _mapList(json['ingredients_required']);
    final stepRecords = _mapList(json['steps'])
      ..sort(
        (left, right) =>
            _integer(left['step_number'])
                .compareTo(_integer(right['step_number'])),
      );
    final cuisine = _string(json['cuisine'], fallback: 'Verified recipe');

    return BackendMealRecommendation(
      recipe: RecipeRecommendationModel(
        id: _string(json['recipe_id']),
        title: _string(json['name'], fallback: 'Chef recommendation'),
        subtitle: '$cuisine recipe selected from the verified kitchen catalog.',
        imageUrl: '',
        cookTimeMinutes: _integer(json['cook_time_minutes']),
        calories: _integer(json['calories_per_serving']),
        difficulty: 'Chef verified',
        mealType: cuisine,
        servings: _integer(json['servings'], fallback: 4),
        ingredientDetails: ingredientRecords
            .map(
              (ingredient) => RecipeIngredient(
                name: _string(ingredient['name']),
                quantity: _number(ingredient['quantity']),
                unit: _string(ingredient['unit'], fallback: 'pcs'),
              ),
            )
            .toList(),
        instructions: stepRecords
            .map((step) => _string(step['instruction']))
            .where((instruction) => instruction.isNotEmpty)
            .toList(),
      ),
      pantryMatchPercent: _integer(json['pantry_match_percent']),
      retrievalScore: _number(json['retrieval_score']),
      availableIngredients: _strings(json['available_ingredients']),
      missingIngredients: _strings(json['missing_ingredients']),
      source: _string(json['source'], fallback: 'CulinaryAI verified catalog'),
    );
  }
}

class BackendMealPlan {
  final List<BackendMealRecommendation> meals;
  final int pantryItemCount;
  final String retrievalMethod;

  const BackendMealPlan({
    required this.meals,
    required this.pantryItemCount,
    required this.retrievalMethod,
  });

  factory BackendMealPlan.fromJson(Map<String, dynamic> json) =>
      BackendMealPlan(
        meals: _mapList(json['meals'])
            .map(BackendMealRecommendation.fromJson)
            .toList(),
        pantryItemCount: _integer(json['pantry_item_count']),
        retrievalMethod: _string(
          json['retrieval_method'],
          fallback: 'verified recipe retrieval',
        ),
      );
}

List<Map<String, dynamic>> _mapList(Object? value) {
  if (value is! List) return [];
  return value
      .whereType<Map>()
      .map((record) => Map<String, dynamic>.from(record))
      .toList();
}

List<String> _strings(Object? value) => value is List
    ? value
          .map((item) => item.toString())
          .where((item) => item.isNotEmpty)
          .toList()
    : const [];

String _string(Object? value, {String fallback = ''}) {
  final text = value?.toString().trim() ?? '';
  return text.isEmpty ? fallback : text;
}

int _integer(Object? value, {int fallback = 0}) => value is num
    ? value.toInt()
    : int.tryParse(value?.toString() ?? '') ?? fallback;

double _number(Object? value) => value is num
    ? value.toDouble()
    : double.tryParse(value?.toString() ?? '') ?? 0;
