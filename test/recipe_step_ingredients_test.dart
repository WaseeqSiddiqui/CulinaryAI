import 'package:culinary_ai/models/recipe_ingredient.dart';
import 'package:culinary_ai/models/recipe_recommendation_model.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const recipe = RecipeRecommendationModel(
    id: 'sauce',
    title: 'Quick Sauce',
    subtitle: '',
    imageUrl: '',
    cookTimeMinutes: 10,
    calories: 200,
    difficulty: 'Easy',
    mealType: 'Dinner',
    servings: 2,
    ingredientDetails: [
      RecipeIngredient(name: 'Onion', quantity: 1, unit: 'pcs'),
      RecipeIngredient(name: 'Mustard Sauce', quantity: 2, unit: 'tbsp'),
    ],
    instructions: [
      'Chop the onion.',
      'Add the mustard sauce and simmer.',
    ],
  );

  test('serving changes scale the same structured ingredient source', () {
    final scaled = recipe.scaledTo(4);

    expect(scaled.ingredientDetails[0].quantity, 2);
    expect(scaled.ingredientDetails[1].quantity, 4);
    expect(scaled.ingredientsForStep(1).single.quantity, 4);
    expect(scaled.instructionWithQuantities(1), contains('4 tbsp'));
  });

  test('legacy steps receive deterministic measured ingredient mappings', () {
    expect(recipe.ingredientsForStep(0).single.name, 'Onion');
    expect(recipe.ingredientsForStep(1).single.name, 'Mustard Sauce');
  });
}
