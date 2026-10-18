import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/nutrition_facts.dart';
import '../models/recipe_recommendation_model.dart';
import '../models/recipe_ingredient.dart';
import '../services/nutrition_calculator_service.dart';

class CookingPreferences {
  final List<String> dietaryNeeds;
  final List<String> allergens;
  final List<String> dislikedIngredients;
  final List<String> favoriteCuisines;
  final String goal;
  final int servings;
  final int maxCookMinutes;
  final int calorieTarget;
  final int proteinTarget;
  final int carbTarget;
  final int fatTarget;
  final int mealsPerDay;

  const CookingPreferences({
    this.dietaryNeeds = const [],
    this.allergens = const [],
    this.dislikedIngredients = const [],
    this.favoriteCuisines = const [],
    this.goal = 'Balanced eating',
    this.servings = 4,
    this.maxCookMinutes = 45,
    this.calorieTarget = 2000,
    this.proteinTarget = 100,
    this.carbTarget = 250,
    this.fatTarget = 65,
    this.mealsPerDay = 3,
  });

  Map<String, dynamic> toJson() => {
    'dietaryNeeds': dietaryNeeds,
    'allergens': allergens,
    'dislikedIngredients': dislikedIngredients,
    'favoriteCuisines': favoriteCuisines,
    'goal': goal,
    'servings': servings,
    'maxCookMinutes': maxCookMinutes,
    'calorieTarget': calorieTarget,
    'proteinTarget': proteinTarget,
    'carbTarget': carbTarget,
    'fatTarget': fatTarget,
    'mealsPerDay': mealsPerDay,
  };

  factory CookingPreferences.fromJson(Map<String, dynamic> json) =>
      CookingPreferences(
        dietaryNeeds: _strings(json['dietaryNeeds']),
        allergens: _strings(json['allergens']),
        dislikedIngredients: _strings(json['dislikedIngredients']),
        favoriteCuisines: _strings(json['favoriteCuisines']),
        goal: json['goal']?.toString() ?? 'Balanced eating',
        servings: _int(json['servings'], 4),
        maxCookMinutes: _int(json['maxCookMinutes'], 45),
        calorieTarget: _int(json['calorieTarget'], 2000),
        proteinTarget: _int(json['proteinTarget'], 100),
        carbTarget: _int(json['carbTarget'], 250),
        fatTarget: _int(json['fatTarget'], 65),
        mealsPerDay: _int(json['mealsPerDay'], 3),
      );
}

class CookedMealEntry {
  final String recipeId;
  final String title;
  final DateTime cookedAt;
  final NutritionFacts nutrition;

  const CookedMealEntry({
    required this.recipeId,
    required this.title,
    required this.cookedAt,
    required this.nutrition,
  });

  Map<String, dynamic> toJson() => {
    'recipeId': recipeId,
    'title': title,
    'cookedAt': cookedAt.toIso8601String(),
    'calories': nutrition.calories,
    'protein': nutrition.proteinGrams,
    'carbs': nutrition.carbohydrateGrams,
    'fat': nutrition.fatGrams,
    'fiber': nutrition.fiberGrams,
  };

  factory CookedMealEntry.fromJson(Map<String, dynamic> json) =>
      CookedMealEntry(
        recipeId: json['recipeId']?.toString() ?? '',
        title: json['title']?.toString() ?? 'Cooked meal',
        cookedAt:
            DateTime.tryParse(json['cookedAt']?.toString() ?? '') ??
            DateTime.now(),
        nutrition: NutritionFacts(
          calories: _double(json['calories']),
          proteinGrams: _double(json['protein']),
          carbohydrateGrams: _double(json['carbs']),
          fatGrams: _double(json['fat']),
          fiberGrams: _double(json['fiber']),
        ),
      );
}

class RecipeExperienceProvider extends ChangeNotifier {
  static const _preferencesKey = 'culinary_cooking_preferences_v1';
  static const _favoritesKey = 'culinary_recipe_favorites_v1';
  static const _historyKey = 'culinary_cooked_history_v1';
  static const _savedRecipesKey = 'culinary_saved_recipes_v1';

  RecipeExperienceProvider() {
    _load();
  }

  CookingPreferences _preferences = const CookingPreferences();
  final Set<String> _favoriteIds = {};
  final Map<String, RecipeRecommendationModel> _savedRecipes = {};
  final List<CookedMealEntry> _history = [];
  bool _ready = false;

  CookingPreferences get preferences => _preferences;
  Set<String> get favoriteIds => Set.unmodifiable(_favoriteIds);
  List<RecipeRecommendationModel> get savedRecipes =>
      List.unmodifiable(_savedRecipes.values);
  List<CookedMealEntry> get history => List.unmodifiable(_history);
  bool get ready => _ready;

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    try {
      final raw = prefs.getString(_preferencesKey);
      if (raw != null) {
        _preferences = CookingPreferences.fromJson(
          Map<String, dynamic>.from(jsonDecode(raw) as Map),
        );
      }
      _favoriteIds.addAll(prefs.getStringList(_favoritesKey) ?? const []);
      final savedRaw = prefs.getString(_savedRecipesKey);
      if (savedRaw != null) {
        for (final value in (jsonDecode(savedRaw) as List).whereType<Map>()) {
          final recipe = _recipeFromJson(Map<String, dynamic>.from(value));
          _savedRecipes[recipe.id] = recipe;
        }
      }
      final historyRaw = prefs.getString(_historyKey);
      if (historyRaw != null) {
        _history.addAll(
          (jsonDecode(historyRaw) as List).whereType<Map>().map(
            (value) =>
                CookedMealEntry.fromJson(Map<String, dynamic>.from(value)),
          ),
        );
      }
    } catch (_) {
      // Keep defaults if old local data is malformed.
    }
    _ready = true;
    notifyListeners();
  }

  Future<void> updatePreferences(CookingPreferences value) async {
    _preferences = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_preferencesKey, jsonEncode(value.toJson()));
  }

  Future<void> toggleFavorite(
    String recipeId, {
    RecipeRecommendationModel? recipe,
  }) async {
    if (_favoriteIds.remove(recipeId)) {
      _savedRecipes.remove(recipeId);
    } else {
      _favoriteIds.add(recipeId);
      if (recipe != null) _savedRecipes[recipeId] = recipe;
    }
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_favoritesKey, _favoriteIds.toList());
    await prefs.setString(
      _savedRecipesKey,
      jsonEncode(_savedRecipes.values.map(_recipeToJson).toList()),
    );
  }

  bool isFavorite(String recipeId) => _favoriteIds.contains(recipeId);

  Future<void> recordCooked(RecipeRecommendationModel recipe) async {
    final calculated = NutritionCalculatorService.calculate(
      ingredients: recipe.ingredientDetails,
      servings: recipe.servings,
    );
    _history.insert(
      0,
      CookedMealEntry(
        recipeId: recipe.id,
        title: recipe.title,
        cookedAt: DateTime.now(),
        nutrition: calculated.perServing,
      ),
    );
    if (_history.length > 100) _history.removeRange(100, _history.length);
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _historyKey,
      jsonEncode(_history.map((entry) => entry.toJson()).toList()),
    );
  }

  Future<void> recordNutrition({
    required String title,
    required NutritionFacts nutrition,
  }) async {
    _history.insert(
      0,
      CookedMealEntry(
        recipeId: 'meal_${DateTime.now().millisecondsSinceEpoch}',
        title: title,
        cookedAt: DateTime.now(),
        nutrition: nutrition,
      ),
    );
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _historyKey,
      jsonEncode(_history.map((entry) => entry.toJson()).toList()),
    );
  }

  NutritionFacts nutritionFor(DateTime day) {
    return _history
        .where((entry) => _sameDay(entry.cookedAt, day))
        .fold(const NutritionFacts(), (sum, entry) => sum + entry.nutrition);
  }

  static bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;
}

Map<String, dynamic> _recipeToJson(RecipeRecommendationModel recipe) => {
  'id': recipe.id,
  'title': recipe.title,
  'subtitle': recipe.subtitle,
  'imageUrl': recipe.imageUrl,
  'cookTimeMinutes': recipe.cookTimeMinutes,
  'calories': recipe.calories,
  'difficulty': recipe.difficulty,
  'mealType': recipe.mealType,
  'servings': recipe.servings,
  'ingredients': recipe.ingredientDetails
      .map(
        (item) => {
          'name': item.name,
          'quantity': item.quantity,
          'unit': item.unit,
        },
      )
      .toList(),
  'instructions': recipe.instructions,
};

RecipeRecommendationModel _recipeFromJson(Map<String, dynamic> json) =>
    RecipeRecommendationModel(
      id: json['id']?.toString() ?? '',
      title: json['title']?.toString() ?? 'Saved recipe',
      subtitle: json['subtitle']?.toString() ?? '',
      imageUrl: json['imageUrl']?.toString() ?? '',
      cookTimeMinutes: _int(json['cookTimeMinutes'], 0),
      calories: _int(json['calories'], 0),
      difficulty: json['difficulty']?.toString() ?? 'Easy',
      mealType: json['mealType']?.toString() ?? 'Meal',
      servings: _int(json['servings'], 4),
      ingredientDetails: json['ingredients'] is List
          ? (json['ingredients'] as List).whereType<Map>().map((item) {
              final value = Map<String, dynamic>.from(item);
              return RecipeIngredient(
                name: value['name']?.toString() ?? '',
                quantity: _double(value['quantity']),
                unit: value['unit']?.toString() ?? 'pcs',
              );
            }).toList()
          : const [],
      instructions: _strings(json['instructions']),
    );

List<String> _strings(Object? value) => value is List
    ? value
          .map((item) => item.toString())
          .where((item) => item.isNotEmpty)
          .toList()
    : const [];
int _int(Object? value, int fallback) =>
    value is num ? value.toInt() : int.tryParse('$value') ?? fallback;
double _double(Object? value) =>
    value is num ? value.toDouble() : double.tryParse('$value') ?? 0;
