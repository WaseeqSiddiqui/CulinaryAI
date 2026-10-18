import 'nutrition_facts.dart';

class MealNutritionEstimate {
  final String dishName;
  final String portionDescription;
  final NutritionFacts nutrition;
  final double confidence;
  final List<String> assumptions;

  const MealNutritionEstimate({
    required this.dishName,
    required this.portionDescription,
    required this.nutrition,
    required this.confidence,
    required this.assumptions,
  });

  factory MealNutritionEstimate.fromJson(Map<String, dynamic> json) =>
      MealNutritionEstimate(
        dishName: json['dish_name']?.toString() ?? 'Meal',
        portionDescription:
            json['portion_description']?.toString() ?? 'Visible portion',
        nutrition: NutritionFacts(
          calories: _number(json['calories']),
          proteinGrams: _number(json['protein_grams']),
          carbohydrateGrams: _number(json['carbohydrate_grams']),
          fatGrams: _number(json['fat_grams']),
          fiberGrams: _number(json['fiber_grams']),
        ),
        confidence: _number(json['confidence']),
        assumptions: json['assumptions'] is List
            ? (json['assumptions'] as List).map((item) => '$item').toList()
            : const [],
      );
}

double _number(Object? value) => value is num
    ? value.toDouble()
    : double.tryParse(value?.toString() ?? '') ?? 0;
