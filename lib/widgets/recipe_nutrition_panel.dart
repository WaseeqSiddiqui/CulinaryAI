import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'app_ui.dart';
import '../models/nutrition_facts.dart';
import '../models/recipe_ingredient.dart';
import '../models/recipe_recommendation_model.dart';
import '../services/nutrition_calculator_service.dart';

class RecipeNutritionPanel extends StatefulWidget {
  final RecipeRecommendationModel recipe;
  final bool isDark;
  final ValueChanged<int>? onServingsChanged;

  const RecipeNutritionPanel({
    super.key,
    required this.recipe,
    required this.isDark,
    this.onServingsChanged,
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

    final colors = Theme.of(context).colorScheme;
    return SurfacePanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Make enough for everyone.',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 6),
          Text(
            'Ingredients and nutrition adjust with your portions.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 18),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton.filledTonal(
                tooltip: 'Fewer servings',
                onPressed: _servings > 1
                    ? () {
                        setState(() => _servings--);
                        widget.onServingsChanged?.call(_servings);
                      }
                    : null,
                icon: const Icon(Icons.remove_rounded),
              ),
              Expanded(
                child: Column(
                  children: [
                    Text(
                      '$_servings',
                      style: Theme.of(context).textTheme.headlineMedium,
                    ),
                    Text(
                      'servings',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              IconButton.filledTonal(
                tooltip: 'More servings',
                onPressed: _servings < 12
                    ? () {
                        setState(() => _servings++);
                        widget.onServingsChanged?.call(_servings);
                      }
                    : null,
                icon: const Icon(Icons.add_rounded),
              ),
            ],
          ),
          const SizedBox(height: 22),
          const Divider(),
          const SizedBox(height: 20),
          Text(
            'What you will need',
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const SizedBox(height: 12),
          for (final ingredient in ingredients)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                children: [
                  Expanded(
                    flex: 3,
                    child: Text(
                      ingredient.name,
                      style: Theme.of(context).textTheme.bodyMedium
                          ?.copyWith(color: colors.onSurfaceVariant),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Flexible(
                    child: Text(
                      _formatIngredient(ingredient),
                      textAlign: TextAlign.end,
                      style: Theme.of(context).textTheme.labelLarge,
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 22),
          Text(
            'Nutrition at a glance',
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const SizedBox(height: 14),
          FormFieldPair(
            first: _MacroColumn(
              title: 'Per serving',
              facts: nutrition.perServing,
              color: colors.primary,
            ),
            second: _MacroColumn(
              title: 'Whole recipe',
              facts: nutrition.total,
              color: colors.primary,
            ),
          ),
        ],
      ),
    );
  }

  String _formatIngredient(RecipeIngredient ingredient) {
    return '${NumberFormat('0.###').format(ingredient.quantity)} ${ingredient.unit}';
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
