import 'package:flutter/material.dart';

import '../core/theme/app_theme.dart';
import '../models/nutrition_facts.dart';
import '../models/recipe_ingredient.dart';
import '../models/recipe_recommendation_model.dart';
import '../services/nutrition_calculator_service.dart';

class RecipeNutritionPanel extends StatefulWidget {
  final RecipeRecommendationModel recipe;
  final bool isDark;

  const RecipeNutritionPanel({
    super.key,
    required this.recipe,
    required this.isDark,
  });

  @override
  State<RecipeNutritionPanel> createState() => _RecipeNutritionPanelState();
}

class _RecipeNutritionPanelState extends State<RecipeNutritionPanel> {
  late int _servings;

  @override
  void initState() {
    super.initState();
    _servings = widget.recipe.servings;
  }

  @override
  Widget build(BuildContext context) {
    final ingredients = NutritionCalculatorService.scaleIngredients(
      ingredients: widget.recipe.ingredientDetails,
      baseServings: widget.recipe.servings,
      targetServings: _servings,
    );
    final nutrition = NutritionCalculatorService.calculate(
      ingredients: ingredients,
      servings: _servings,
    );
    final textColor = widget.isDark
        ? AppTheme.textDarkPrimary
        : AppTheme.textLightPrimary;
    final secondary = widget.isDark
        ? AppTheme.textDarkSecondary
        : AppTheme.textLightSecondary;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: widget.isDark ? AppTheme.cardDark : Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: widget.isDark ? AppTheme.borderDark : AppTheme.borderLight,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Portion scaler',
                      style: TextStyle(
                        color: textColor,
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Text(
                      'Ingredients and totals update together',
                      style: TextStyle(color: secondary, fontSize: 12),
                    ),
                  ],
                ),
              ),
              IconButton.filledTonal(
                onPressed: _servings > 1
                    ? () => setState(() => _servings--)
                    : null,
                icon: const Icon(Icons.remove_rounded),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: Column(
                  children: [
                    Text(
                      '$_servings',
                      style: TextStyle(
                        color: textColor,
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Text('servings', style: TextStyle(color: secondary)),
                  ],
                ),
              ),
              IconButton.filledTonal(
                onPressed: _servings < 12
                    ? () => setState(() => _servings++)
                    : null,
                icon: const Icon(Icons.add_rounded),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            'Scaled ingredients',
            style: TextStyle(color: textColor, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          ...ingredients.map(
            (ingredient) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      ingredient.name,
                      style: TextStyle(color: secondary),
                    ),
                  ),
                  Text(
                    _formatIngredient(ingredient),
                    style: TextStyle(
                      color: textColor,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const Divider(height: 28),
          Text(
            'Nutrition',
            style: TextStyle(color: textColor, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _MacroColumn(
                  title: 'Per serving',
                  facts: nutrition.perServing,
                  color: AppTheme.primaryFlame,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _MacroColumn(
                  title: 'Recipe total',
                  facts: nutrition.total,
                  color: AppTheme.freshHerb,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _formatIngredient(RecipeIngredient ingredient) {
    final quantity = ingredient.quantity;
    final digits = quantity == quantity.roundToDouble() ? 0 : 1;
    return '${quantity.toStringAsFixed(digits)} ${ingredient.unit}';
  }
}

class _MacroColumn extends StatelessWidget {
  final String title;
  final NutritionFacts facts;
  final Color color;

  const _MacroColumn({
    required this.title,
    required this.facts,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(color: color, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          Text('${facts.calories.round()} kcal'),
          Text('${facts.proteinGrams.toStringAsFixed(1)}g protein'),
          Text('${facts.carbohydrateGrams.toStringAsFixed(1)}g carbs'),
          Text('${facts.fatGrams.toStringAsFixed(1)}g fat'),
          Text('${facts.fiberGrams.toStringAsFixed(1)}g fiber'),
        ],
      ),
    );
  }
}
