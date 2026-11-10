import 'pantry_item_model.dart';
import 'recipe_ingredient.dart';
import '../services/inventory_quantity_service.dart';

/// Model representing a culinary recipe recommendation
class RecipeRecommendationModel {
  final String id;
  final String title;
  final String subtitle;
  final String imageUrl;
  final int cookTimeMinutes;
  final int calories;
  final String difficulty;
  final String mealType;
  final int servings;
  final List<RecipeIngredient> ingredientDetails;
  final List<String> instructions;
  final List<List<RecipeIngredient>> explicitStepIngredients;

  const RecipeRecommendationModel({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.imageUrl,
    required this.cookTimeMinutes,
    required this.calories,
    required this.difficulty,
    required this.mealType,
    required this.servings,
    required this.ingredientDetails,
    required this.instructions,
    this.explicitStepIngredients = const [],
  });

  String get description => subtitle;
  String get cuisine => mealType;
  List<String> get requiredIngredients =>
      ingredientDetails.map((ingredient) => ingredient.name).toList();
  List<String> get ingredients => requiredIngredients;

  RecipeRecommendationModel scaledTo(int targetServings) {
    if (targetServings <= 0) {
      throw ArgumentError.value(targetServings, 'targetServings');
    }
    if (targetServings == servings) return this;
    final factor = targetServings / servings;
    return RecipeRecommendationModel(
      id: id,
      title: title,
      subtitle: subtitle,
      imageUrl: imageUrl,
      cookTimeMinutes: cookTimeMinutes,
      calories: calories,
      difficulty: difficulty,
      mealType: mealType,
      servings: targetServings,
      ingredientDetails: ingredientDetails
          .map((ingredient) => ingredient.scale(factor))
          .toList(),
      instructions: instructions,
      explicitStepIngredients: explicitStepIngredients
          .map(
            (step) =>
                step.map((ingredient) => ingredient.scale(factor)).toList(),
          )
          .toList(),
    );
  }

  List<List<RecipeIngredient>> get stepIngredientDetails {
    if (instructions.isEmpty) return const [];
    if (explicitStepIngredients.length == instructions.length) {
      return explicitStepIngredients
          .map((step) => List<RecipeIngredient>.unmodifiable(step))
          .toList();
    }
    final result = List.generate(
      instructions.length,
      (_) => <RecipeIngredient>[],
    );
    for (final ingredient in ingredientDetails) {
      final ingredientName = _normalized(ingredient.name);
      final meaningfulWords = ingredientName
          .split(' ')
          .where((word) => word.length > 2)
          .toList();
      var target = -1;
      for (var index = 0; index < instructions.length; index++) {
        final instruction = _normalized(instructions[index]);
        if (instruction.contains(ingredientName) ||
            meaningfulWords.any(instruction.contains)) {
          target = index;
          break;
        }
      }
      // Legacy recipes have unstructured instruction strings. Unmentioned
      // ingredients are surfaced in step one as mise en place, never guessed
      // into a later cooking action.
      result[target < 0 ? 0 : target].add(ingredient);
    }
    return result;
  }

  List<RecipeIngredient> ingredientsForStep(int stepIndex) {
    final steps = stepIngredientDetails;
    if (stepIndex < 0 || stepIndex >= steps.length) return const [];
    return List.unmodifiable(steps[stepIndex]);
  }

  String instructionWithQuantities(int stepIndex) {
    if (stepIndex < 0 || stepIndex >= instructions.length) return '';
    final ingredients = ingredientsForStep(stepIndex);
    if (ingredients.isEmpty) return instructions[stepIndex];
    final measured = ingredients
        .map(
          (ingredient) =>
              '${_formatQuantity(ingredient.quantity)} ${ingredient.unit} ${ingredient.name}',
        )
        .join(', ');
    return '${instructions[stepIndex]} Ingredients for this step: $measured.';
  }

  String stepTitle(int stepIndex) {
    if (stepIndex < 0 || stepIndex >= instructions.length) {
      return 'Cooking step';
    }
    final clean = instructions[stepIndex].trim().replaceAll(
      RegExp(r'[.!?].*'),
      '',
    );
    final words = clean.split(RegExp(r'\s+'));
    final title = words.take(7).join(' ');
    return title.isEmpty ? 'Cooking step' : title;
  }

  List<IngredientAvailability> availabilityChecks(
    List<PantryItemModel> pantryItems,
  ) => ingredientDetails
      .map(
        (ingredient) =>
            InventoryQuantityService.availability(ingredient, pantryItems),
      )
      .toList();

  /// Computes how many of the recipe's required ingredients exist in the pantry
  int matchedCount(List<PantryItemModel> pantryItems) {
    int matched = 0;
    for (final check in availabilityChecks(pantryItems)) {
      if (check.isSufficient) matched++;
    }
    return matched;
  }

  /// Match percentage from 0 to 100%
  int matchPercentage(List<PantryItemModel> pantryItems) {
    if (requiredIngredients.isEmpty) return 100;
    final matched = matchedCount(pantryItems);
    return ((matched / requiredIngredients.length) * 100).round();
  }

  /// List of ingredients available in the pantry
  List<String> inPantryIngredients(List<PantryItemModel> pantryItems) {
    return availabilityChecks(pantryItems)
        .where((check) => check.isSufficient)
        .map((check) => check.ingredient.name)
        .toList();
  }

  /// List of ingredients needed that are not in the pantry
  List<String> missingIngredients(List<PantryItemModel> pantryItems) {
    return availabilityChecks(pantryItems)
        .where((check) => !check.isSufficient)
        .map((check) => check.ingredient.name)
        .toList();
  }
}

String _normalized(String value) => value
    .trim()
    .toLowerCase()
    .replaceAll(RegExp(r'[^a-z0-9 ]'), ' ')
    .replaceAll(RegExp(r'\s+'), ' ');

String _formatQuantity(double value) {
  if (value == value.roundToDouble()) return value.toInt().toString();
  return value
      .toStringAsFixed(value < 1 ? 2 : 1)
      .replaceFirst(RegExp(r'0+$'), '')
      .replaceFirst(RegExp(r'\.$'), '');
}
