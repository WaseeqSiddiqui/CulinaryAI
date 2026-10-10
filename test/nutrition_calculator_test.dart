import 'package:culinary_ai/models/recipe_ingredient.dart';
import 'package:culinary_ai/services/nutrition_calculator_service.dart';
import 'package:culinary_ai/services/unit_conversion_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('UnitConversionService', () {
    test('normalizes mass, volume and count units to grams', () {
      expect(UnitConversionService.toGrams(1, 'kg'), 1000);
      expect(UnitConversionService.toGrams(2, 'cups'), 480);
      expect(UnitConversionService.toGrams(1, 'dozen', gramsPerPiece: 50), 600);
      expect(UnitConversionService.convertMass(750, 'g', 'kg'), 0.75);
    });
  });

  group('NutritionCalculatorService', () {
    const ingredients = [
      RecipeIngredient(name: 'Chicken', quantity: 100, unit: 'g'),
      RecipeIngredient(name: 'Rice', quantity: 100, unit: 'g'),
    ];

    test('calculates total and per-serving macros', () {
      final result = NutritionCalculatorService.calculate(
        ingredients: ingredients,
        servings: 2,
      );

      expect(result.total.calories, closeTo(295, 0.01));
      expect(result.total.proteinGrams, closeTo(33.7, 0.01));
      expect(result.total.carbohydrateGrams, closeTo(28, 0.01));
      expect(result.perServing.calories, closeTo(147.5, 0.01));
    });

    test('scales every ingredient by the requested serving count', () {
      final scaled = NutritionCalculatorService.scaleIngredients(
        ingredients: ingredients,
        baseServings: 4,
        targetServings: 6,
      );

      expect(scaled[0].quantity, 150);
      expect(scaled[1].quantity, 150);
    });

    test('rejects non-positive serving counts', () {
      expect(
        () => NutritionCalculatorService.calculate(
          ingredients: ingredients,
          servings: 0,
        ),
        throwsArgumentError,
      );
    });
  });
}
