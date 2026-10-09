import 'pantry_item_model.dart';

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
  final List<String> requiredIngredients;
  final List<String> instructions;

  const RecipeRecommendationModel({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.imageUrl,
    required this.cookTimeMinutes,
    required this.calories,
    required this.difficulty,
    required this.mealType,
    required this.requiredIngredients,
    required this.instructions,
  });

  String get description => subtitle;
  String get cuisine => mealType;
  List<String> get ingredients => requiredIngredients;

  /// Computes how many of the recipe's required ingredients exist in the pantry
  int matchedCount(List<PantryItemModel> pantryItems) {
    int matched = 0;
    for (final req in requiredIngredients) {
      final reqLower = req.toLowerCase();
      final hasIt = pantryItems.any((item) {
        final nameLower = item.name.toLowerCase();
        return nameLower.contains(reqLower) || reqLower.contains(nameLower);
      });
      if (hasIt) matched++;
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
    return requiredIngredients.where((req) {
      final reqLower = req.toLowerCase();
      return pantryItems.any((item) {
        final nameLower = item.name.toLowerCase();
        return nameLower.contains(reqLower) || reqLower.contains(nameLower);
      });
    }).toList();
  }

  /// List of ingredients needed that are not in the pantry
  List<String> missingIngredients(List<PantryItemModel> pantryItems) {
    return requiredIngredients.where((req) {
      final reqLower = req.toLowerCase();
      return !pantryItems.any((item) {
        final nameLower = item.name.toLowerCase();
        return nameLower.contains(reqLower) || reqLower.contains(nameLower);
      });
    }).toList();
  }
}
