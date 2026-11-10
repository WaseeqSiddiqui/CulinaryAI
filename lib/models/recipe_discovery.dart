class RecipeIngredientCheck {
  final String name;
  final String measure;
  final String status;
  final double? missingQuantity;
  final String unit;

  const RecipeIngredientCheck({
    required this.name,
    required this.measure,
    required this.status,
    this.missingQuantity,
    this.unit = '',
  });

  factory RecipeIngredientCheck.fromJson(Map<String, dynamic> json) =>
      RecipeIngredientCheck(
        name: json['name'] as String,
        measure: json['measure'] as String? ?? 'Amount not specified',
        status: json['status'] as String? ?? 'check_quantity',
        missingQuantity: (json['missing_quantity'] as num?)?.toDouble(),
        unit: json['unit'] as String? ?? '',
      );
}

class DiscoveredRecipe {
  final String id;
  final String name;
  final String cuisine;
  final String category;
  final String imageUrl;
  final String source;
  final Uri sourceUrl;
  final List<RecipeIngredientCheck> ingredients;
  final int pantryMatchPercent;
  final bool canCookNow;

  const DiscoveredRecipe({
    required this.id,
    required this.name,
    required this.cuisine,
    required this.category,
    required this.imageUrl,
    required this.source,
    required this.sourceUrl,
    required this.ingredients,
    required this.pantryMatchPercent,
    required this.canCookNow,
  });

  factory DiscoveredRecipe.fromJson(Map<String, dynamic> json) {
    final uri = Uri.parse(json['source_url'] as String);
    if (uri.scheme != 'https' || uri.host.isEmpty || uri.userInfo.isNotEmpty) {
      throw const FormatException('Recipe source must use HTTPS.');
    }
    final ingredients = (json['ingredients'] as List)
        .map(
          (item) => RecipeIngredientCheck.fromJson(
            Map<String, dynamic>.from(item as Map),
          ),
        )
        .toList();
    return DiscoveredRecipe(
      id: json['recipe_id'] as String,
      name: json['name'] as String,
      cuisine: json['cuisine'] as String? ?? '',
      category: json['category'] as String? ?? '',
      imageUrl: json['image_url'] as String? ?? '',
      source: json['source'] as String? ?? 'Recipe website',
      sourceUrl: uri,
      ingredients: ingredients,
      pantryMatchPercent: ((json['pantry_match_percent'] as num?)?.toInt() ?? 0)
          .clamp(0, 100),
      // Do not turn an inconsistent provider response into a ready-to-cook claim.
      canCookNow:
          json['can_cook_now'] == true &&
          ingredients.isNotEmpty &&
          ingredients.every((item) => item.status == 'available'),
    );
  }
}

class RecipeDiscoveryResult {
  final List<DiscoveredRecipe> recipes;
  final String message;
  final DateTime planningDate;
  final int pantryItemCount;
  final List<String> excludedExpiredItems;
  final String quantitiesNote;
  final int checkedRecipeCount;

  const RecipeDiscoveryResult({
    required this.recipes,
    required this.message,
    required this.planningDate,
    required this.pantryItemCount,
    required this.excludedExpiredItems,
    required this.quantitiesNote,
    required this.checkedRecipeCount,
  });

  factory RecipeDiscoveryResult.fromJson(
    Map<String, dynamic> json,
  ) => RecipeDiscoveryResult(
    recipes: (json['meals'] as List)
        .map(
          (item) =>
              DiscoveredRecipe.fromJson(Map<String, dynamic>.from(item as Map)),
        )
        .toList(),
    message: json['message'] as String,
    planningDate: DateTime.parse(json['planning_date'] as String),
    pantryItemCount: (json['pantry_item_count'] as num).toInt(),
    excludedExpiredItems: (json['excluded_expired_items'] as List? ?? [])
        .cast<String>(),
    quantitiesNote: json['source_quantities_note'] as String? ?? '',
    checkedRecipeCount: (json['checked_recipe_count'] as num?)?.toInt() ?? 0,
  );
}
