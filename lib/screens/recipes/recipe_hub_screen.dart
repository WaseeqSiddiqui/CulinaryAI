import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../widgets/app_ui.dart';
import '../../models/backend_meal_recommendation.dart';
import '../../models/pantry_item_model.dart';
import '../../models/recipe_recommendation_model.dart';
import '../../providers/auth_provider.dart';
import '../../providers/pantry_provider.dart';
import '../../providers/recipe_experience_provider.dart';
import '../../providers/shopping_provider.dart';
import '../../services/meal_planning_api_service.dart';
import '../../services/recipe_recommendation_service.dart';
import '../cooking/guided_cooking_screen.dart';
import '../scanner/meal_scanner_screen.dart';

enum RecipeSection { pantry, create, macros, weekly, saved }

class RecipeHubScreen extends StatefulWidget {
  final RecipeSection section;

  const RecipeHubScreen({super.key, this.section = RecipeSection.pantry});

  @override
  State<RecipeHubScreen> createState() => _RecipeHubScreenState();
}

class _RecipeHubScreenState extends State<RecipeHubScreen> {
  final _query = TextEditingController();
  final _api = MealPlanningApiService(timeout: const Duration(seconds: 15));
  late final RecipeSection _mode;
  List<BackendMealRecommendation> _generated = const [];
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _mode = widget.section;
  }

  @override
  void dispose() {
    _query.dispose();
    _api.close();
    super.dispose();
  }

  Future<void> _generate({required bool weekly}) async {
    final pantry = context
        .read<PantryProvider>()
        .allItems
        .where((item) => item.expiryStatus != ExpiryStatus.expired)
        .toList();
    final profile = context.read<RecipeExperienceProvider>().preferences;
    final userDiet = context
        .read<AuthProvider>()
        .currentUser
        ?.dietaryPreference;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final plan = await _api.generatePlan(
        question: [
          weekly ? 'Create a varied seven-day meal plan.' : _query.text.trim(),
          'Goal: ${profile.goal}.',
          if (profile.favoriteCuisines.isNotEmpty)
            'Preferred cuisines: ${profile.favoriteCuisines.join(', ')}.',
          if (profile.allergens.isNotEmpty)
            'Never include allergens: ${profile.allergens.join(', ')}.',
          if (profile.dislikedIngredients.isNotEmpty)
            'Avoid: ${profile.dislikedIngredients.join(', ')}.',
          if (_mode == RecipeSection.macros)
            'Daily targets: ${profile.calorieTarget} kcal, ${profile.proteinTarget}g protein, ${profile.carbTarget}g carbs, ${profile.fatTarget}g fat.',
          if (weekly) _query.text.trim(),
        ].where((part) => part.isNotEmpty).join(' '),
        pantryItems: pantry,
        servings: profile.servings,
        mealCount: weekly ? 7 : 1,
        dietaryPreferences: [...profile.dietaryNeeds, ?userDiet],
        maxCookTimeMinutes: profile.maxCookMinutes,
        avoidIngredients: [
          ...profile.allergens,
          ...profile.dislikedIngredients,
        ],
        mealsPerDay: profile.mealsPerDay,
        targetCaloriesPerPersonPerDay: profile.calorieTarget,
        pantryFirst: true,
      );
      if (mounted) setState(() => _generated = plan.meals);
    } on MealPlanningApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _addMissing(List<String> names) async {
    final shopping = context.read<ShoppingProvider>();
    final existing = shopping.items
        .map((item) => item.name.toLowerCase())
        .toSet();
    var added = 0;
    for (final name in names) {
      if (existing.add(name.toLowerCase())) {
        await shopping.addManualItem(name: name, quantity: 1, unit: 'pcs');
        added++;
      }
    }
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('$added missing ingredient(s) added to Restock.'),
        ),
      );
    }
  }

  void _openRecipe(
    RecipeRecommendationModel recipe, {
    List<String> missing = const [],
  }) {
    final experience = context.read<RecipeExperienceProvider>();
    var selectedServings = experience.preferences.servings;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      constraints: const BoxConstraints(maxWidth: 760),
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheetState) => DraggableScrollableSheet(
          expand: false,
          initialChildSize: .82,
          minChildSize: .55,
          maxChildSize: .95,
          builder: (_, controller) => ListView(
            controller: controller,
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 30),
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      recipe.title,
                      style: Theme.of(context).textTheme.headlineSmall
                          ?.copyWith(fontWeight: FontWeight.w600),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Save recipe',
                    onPressed: () async {
                      await experience.toggleFavorite(
                        recipe.id,
                        recipe: recipe,
                      );
                      setSheetState(() {});
                      if (mounted) setState(() {});
                    },
                    icon: Icon(
                      experience.isFavorite(recipe.id)
                          ? Icons.favorite_rounded
                          : Icons.favorite_border_rounded,
                      color: AppTheme.primaryFlame,
                    ),
                  ),
                ],
              ),
              Text(
                '${recipe.cookTimeMinutes} min · $selectedServings servings · ${recipe.calories} kcal',
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  const Text(
                    'Portions',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const Spacer(),
                  IconButton(
                    onPressed: selectedServings <= 1
                        ? null
                        : () => setSheetState(() => selectedServings--),
                    icon: const Icon(Icons.remove_circle_outline_rounded),
                  ),
                  Text(
                    '$selectedServings',
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  IconButton(
                    onPressed: selectedServings >= 12
                        ? null
                        : () => setSheetState(() => selectedServings++),
                    icon: const Icon(Icons.add_circle_outline_rounded),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              const Text(
                'Ingredients',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 8),
              ..._scaledRecipe(recipe, selectedServings).ingredientDetails.map(
                (ingredient) => ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(
                    Icons.check_circle_outline_rounded,
                    size: 19,
                  ),
                  title: Text(ingredient.name),
                  trailing: Text(
                    '${NumberFormat('0.###').format(ingredient.quantity)} ${ingredient.unit}',
                  ),
                ),
              ),
              if (missing.isNotEmpty) ...[
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: () => _addMissing(missing),
                  icon: const Icon(Icons.add_shopping_cart_rounded),
                  label: Text('Add ${missing.length} missing to Restock'),
                ),
                ExpansionTile(
                  tilePadding: EdgeInsets.zero,
                  title: const Text('Optional ingredient swaps'),
                  subtitle: const Text('Review before changing the recipe'),
                  children: missing
                      .map(
                        (name) => ListTile(
                          dense: true,
                          title: Text(name),
                          subtitle: Text(_suggestSwap(name)),
                        ),
                      )
                      .toList(),
                ),
              ],
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.local_drink_outlined),
                title: const Text('Pairing idea'),
                subtitle: Text(_pairingFor(recipe)),
              ),
              const SizedBox(height: 18),
              FilledButton.icon(
                onPressed: () {
                  Navigator.pop(sheetContext);
                  Navigator.push(
                    this.context,
                    MaterialPageRoute(
                      builder: (_) => GuidedCookingScreen(
                        recipe: _scaledRecipe(recipe, selectedServings),
                      ),
                    ),
                  );
                },
                icon: const Icon(Icons.restaurant_menu_rounded),
                label: const Text('Start guided cooking'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final pantry = context.watch<PantryProvider>();
    final experience = context.watch<RecipeExperienceProvider>();
    final today = experience.nutritionFor(DateTime.now());
    final prefs = experience.preferences;
    final localRecipes = RecipeRecommendationService.getRecommendedList(
      pantry.allItems,
      targetCaloriesPerMeal: _mode == RecipeSection.macros
          ? (prefs.calorieTarget / prefs.mealsPerDay).round()
          : null,
    );
    final visibleLocal = _mode == RecipeSection.saved
        ? {
            for (final recipe in [
              ...localRecipes.where(
                (recipe) => experience.isFavorite(recipe.id),
              ),
              ...experience.savedRecipes,
            ])
              recipe.id: recipe,
          }.values.toList()
        : localRecipes;

    return Scaffold(
      appBar: AppBar(
        title: Text(switch (_mode) {
          RecipeSection.pantry => 'Pantry recipes',
          RecipeSection.create => 'Recipe creator',
          RecipeSection.macros => 'Nutrition goals',
          RecipeSection.weekly => '7-day meal plan',
          RecipeSection.saved => 'My cookbook',
        }),
        actions: [
          if (_mode == RecipeSection.macros)
            IconButton(
              tooltip: 'Scan meal nutrition',
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const MealScannerScreen()),
              ),
              icon: const Icon(Icons.add_a_photo_outlined),
            ),
          if (_mode == RecipeSection.pantry)
            IconButton(
              tooltip: 'My cookbook',
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) =>
                      const RecipeHubScreen(section: RecipeSection.saved),
                ),
              ),
              icon: const Icon(Icons.favorite_border_rounded),
            ),
          IconButton(
            tooltip: 'Cooking preferences',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => const CookingPreferencesScreen(),
              ),
            ),
            icon: const Icon(Icons.tune_rounded),
          ),
        ],
      ),
      body: AppPageBody(
        child: RefreshIndicator(
          onRefresh: () async {
            if (_mode == RecipeSection.create ||
                _mode == RecipeSection.macros) {
              await _generate(weekly: false);
            } else if (_mode == RecipeSection.weekly) {
              await _generate(weekly: true);
            }
          },
          child: ListView(
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 40),
            children: [
              PageIntro(
                eyebrow: switch (_mode) {
                  RecipeSection.pantry => 'FROM YOUR PANTRY',
                  RecipeSection.create => 'YOUR OWN INSPIRATION',
                  RecipeSection.macros => 'NUTRITION, IN PERSPECTIVE',
                  RecipeSection.weekly => 'A LITTLE PLANNING',
                  RecipeSection.saved => 'YOUR PERSONAL COLLECTION',
                },
                title: switch (_mode) {
                  RecipeSection.pantry => 'Cook with what you have.',
                  RecipeSection.create => 'Make it your own.',
                  RecipeSection.macros => 'Find your balance.',
                  RecipeSection.weekly => 'Your week, made easier.',
                  RecipeSection.saved => 'The ones worth keeping.',
                },
                subtitle: switch (_mode) {
                  RecipeSection.pantry => 'Fresh ideas, built around the ingredients already in your kitchen.',
                  RecipeSection.create => 'A craving, a cuisine, a little inspiration. Tell us what sounds good.',
                  RecipeSection.macros => 'Keep your daily targets and the meals you enjoy in one place.',
                  RecipeSection.weekly => 'Plan good meals around your pantry, your people and your preferences.',
                  RecipeSection.saved => 'Your saved recipes, ready for the next time you need a good idea.',
                },
              ),
              const SizedBox(height: 26),
              if (_mode == RecipeSection.macros) ...[
                _NutritionTodayCard(
                  calories: today.calories,
                  target: prefs.calorieTarget,
                  protein: today.proteinGrams,
                  proteinTarget: prefs.proteinTarget,
                ),
                const SizedBox(height: 18),
              ],
              if (_mode == RecipeSection.pantry) ...[
                _MessageCard(
                  icon: Icons.kitchen_outlined,
                  message:
                      'Cooking for ${prefs.servings} people. Change portions or preferences to suit your table.',
                ),
                _SeparatedFeatureLinks(
                  onCreate: () => _openSection(RecipeSection.create),
                  onGoals: () => _openSection(RecipeSection.macros),
                  onPlan: () => _openSection(RecipeSection.weekly),
                ),
                const SizedBox(height: 18),
              ],
              if (_mode == RecipeSection.create ||
                  _mode == RecipeSection.macros ||
                  _mode == RecipeSection.weekly) ...[
                TextField(
                  controller: _query,
                  textInputAction: TextInputAction.done,
                  decoration: InputDecoration(
                    hintText: _mode == RecipeSection.create
                        ? 'e.g. spicy pasta, quick Pakistani dinner'
                        : _mode == RecipeSection.macros
                        ? 'Optional: high protein breakfast'
                        : 'Optional: budget, cuisine or family needs',
                    prefixIcon: const Icon(Icons.search_rounded),
                  ),
                  onSubmitted: (_) =>
                      _generate(weekly: _mode == RecipeSection.weekly),
                ),
                const SizedBox(height: 10),
                FilledButton.icon(
                  onPressed: _loading
                      ? null
                      : () => _generate(weekly: _mode == RecipeSection.weekly),
                  icon: _loading
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.auto_awesome_rounded),
                  label: Text(
                    _loading
                        ? 'Building...'
                        : _mode == RecipeSection.weekly
                        ? 'Build my week'
                        : 'Find recipes',
                  ),
                ),
                const SizedBox(height: 18),
              ],
              if (_error != null)
                _MessageCard(
                  icon: Icons.cloud_off_outlined,
                  message: '$_error Showing reliable offline recommendations.',
                ),
              if (_mode == RecipeSection.pantry && pantry.useSoonCount > 0)
                _MessageCard(
                  icon: Icons.eco_outlined,
                  message:
                      '${pantry.useSoonCount} ingredient(s) need using soon, so recipes using them appear first.',
                ),
              Text(
                _mode == RecipeSection.weekly
                    ? 'Your week'
                    : _mode == RecipeSection.saved
                    ? 'Your cookbook'
                    : 'Made for your kitchen',
                style: Theme.of(context).textTheme.titleLarge
                    ?.copyWith(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 10),
              if (_generated.isNotEmpty &&
                  {
                    RecipeSection.create,
                    RecipeSection.macros,
                    RecipeSection.weekly,
                  }.contains(_mode))
                _RecipeGrid(
                  children: _generated
                      .asMap()
                      .entries
                      .map(
                        (entry) => _GeneratedRecipeCard(
                          recommendation: entry.value,
                          dayNumber: _mode == RecipeSection.weekly
                              ? entry.key + 1
                              : null,
                          favorite: experience.isFavorite(
                            entry.value.recipe.id,
                          ),
                          onTap: () => _openRecipe(
                            entry.value.recipe,
                            missing: entry.value.missingIngredients,
                          ),
                          onFavorite: () => experience.toggleFavorite(
                            entry.value.recipe.id,
                            recipe: entry.value.recipe,
                          ),
                        ),
                      )
                      .toList(),
                )
              else if (_mode == RecipeSection.saved && visibleLocal.isEmpty)
                const _MessageCard(
                  icon: Icons.favorite_border_rounded,
                  message: 'No saved recipes yet. Tap the heart on any recipe to build your cookbook.',
                )
              else if (_mode == RecipeSection.pantry && visibleLocal.isEmpty)
                const _MessageCard(
                  icon: Icons.inventory_2_outlined,
                  message: 'No usable pantry item matches a recipe yet. Add an ingredient or restock an expired item first.',
                )
              else if ({
                RecipeSection.create,
                RecipeSection.macros,
                RecipeSection.weekly,
              }.contains(_mode))
                _MessageCard(
                  icon: Icons.kitchen_outlined,
                  message: _mode == RecipeSection.weekly
                      ? 'Build your plan when ready. Pantry availability, people count, and calories per person will be applied.'
                      : 'Enter an optional preference, then find recipes. Your pantry is always checked before a suggestion is shown.',
                )
              else
                _RecipeGrid(
                  children: visibleLocal
                      .map(
                        (recipe) => _LocalRecipeCard(
                          recipe: recipe,
                          pantry: pantry.allItems,
                          favorite: experience.isFavorite(recipe.id),
                          onTap: () => _openRecipe(
                            recipe,
                            missing: recipe.missingIngredients(pantry.allItems),
                          ),
                          onFavorite: () => experience.toggleFavorite(
                            recipe.id,
                            recipe: recipe,
                          ),
                        ),
                      )
                      .toList(),
                ),
              if (_mode == RecipeSection.saved &&
                  experience.history.isNotEmpty) ...[
                const SizedBox(height: 18),
                Text(
                  'Recently cooked',
                  style: Theme.of(context).textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.w600),
                ),
                ...experience.history
                    .take(5)
                    .map(
                      (entry) => ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const CircleAvatar(
                          child: Icon(Icons.check_rounded),
                        ),
                        title: Text(entry.title),
                        subtitle: Text(
                          '${entry.cookedAt.day}/${entry.cookedAt.month}/${entry.cookedAt.year}',
                        ),
                        trailing: Text(
                          '${entry.nutrition.calories.round()} kcal',
                        ),
                      ),
                    ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  void _openSection(RecipeSection section) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => RecipeHubScreen(section: section)),
    );
  }
}

RecipeRecommendationModel _scaledRecipe(
  RecipeRecommendationModel recipe,
  int servings,
) => recipe.scaledTo(servings);

String _suggestSwap(String ingredient) {
  final value = ingredient.toLowerCase();
  if (value.contains('milk')) return 'plain yogurt + water';
  if (value.contains('butter')) return 'olive oil';
  if (value.contains('cream')) return 'plain yogurt';
  if (value.contains('egg')) return 'flax egg';
  if (value.contains('rice')) return 'couscous or quinoa';
  if (value.contains('cheese')) return 'nutritional yeast';
  return 'tap Restock to keep recipe exact';
}

String _pairingFor(RecipeRecommendationModel recipe) {
  final value = '${recipe.title} ${recipe.mealType}'.toLowerCase();
  if (value.contains('spicy') || value.contains('dal')) {
    return 'Mint raita and chilled lemon water';
  }
  if (value.contains('breakfast') || value.contains('egg')) {
    return 'Fresh fruit and unsweetened tea';
  }
  if (value.contains('pasta') || value.contains('italian')) {
    return 'Green salad and sparkling citrus water';
  }
  return 'Seasonal salad and infused water';
}

class _SeparatedFeatureLinks extends StatelessWidget {
  const _SeparatedFeatureLinks({
    required this.onCreate,
    required this.onGoals,
    required this.onPlan,
  });
  final VoidCallback onCreate;
  final VoidCallback onGoals;
  final VoidCallback onPlan;
  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 8,
    runSpacing: 8,
    children: [
      ActionChip(
        avatar: const Icon(Icons.auto_awesome_outlined, size: 17),
        label: const Text('Create a recipe'),
        onPressed: onCreate,
      ),
      ActionChip(
        avatar: const Icon(Icons.track_changes_outlined, size: 17),
        label: const Text('Nutrition goals'),
        onPressed: onGoals,
      ),
      ActionChip(
        avatar: const Icon(Icons.calendar_month_outlined, size: 17),
        label: const Text('Plan the week'),
        onPressed: onPlan,
      ),
    ],
  );
}

class _NutritionTodayCard extends StatelessWidget {
  final double calories;
  final int target;
  final double protein;
  final int proteinTarget;
  const _NutritionTodayCard({
    required this.calories,
    required this.target,
    required this.protein,
    required this.proteinTarget,
  });

  @override
  Widget build(BuildContext context) => SurfacePanel(
    color: Theme.of(context).colorScheme.primaryContainer,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Today, so far', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 20),
        Wrap(
          spacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(
              '${calories.round()}',
              style: Theme.of(context).textTheme.headlineLarge,
            ),
            Text(
              '/ $target kcal',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ],
        ),
        const SizedBox(height: 14),
        LinearProgressIndicator(
          value: target <= 0 ? 0 : (calories / target).clamp(0, 1),
          minHeight: 7,
          borderRadius: BorderRadius.circular(10),
        ),
        const SizedBox(height: 14),
        Text(
          '${protein.round()} / $proteinTarget g protein',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        const SizedBox(height: 8),
        Text(
          'Completed recipes and meal scans are logged here.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    ),
  );
}

class _MessageCard extends StatelessWidget {
  final IconData icon;
  final String message;
  const _MessageCard({required this.icon, required this.message});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: StatusNotice(message: message, icon: icon),
  );
}

class _LocalRecipeCard extends StatelessWidget {
  final RecipeRecommendationModel recipe;
  final List<PantryItemModel> pantry;
  final bool favorite;
  final VoidCallback onTap;
  final VoidCallback onFavorite;
  const _LocalRecipeCard({
    required this.recipe,
    required this.pantry,
    required this.favorite,
    required this.onTap,
    required this.onFavorite,
  });

  @override
  Widget build(BuildContext context) => _RecipeOverviewCard(
    recipe: recipe,
    matchPercent: recipe.matchPercentage(pantry),
    missingCount: recipe.missingIngredients(pantry).length,
    favorite: favorite,
    onTap: onTap,
    onFavorite: onFavorite,
  );
}

class _GeneratedRecipeCard extends StatelessWidget {
  final BackendMealRecommendation recommendation;
  final int? dayNumber;
  final bool favorite;
  final VoidCallback onTap;
  final VoidCallback onFavorite;
  const _GeneratedRecipeCard({
    required this.recommendation,
    required this.dayNumber,
    required this.favorite,
    required this.onTap,
    required this.onFavorite,
  });

  @override
  Widget build(BuildContext context) => _RecipeOverviewCard(
    recipe: recommendation.recipe,
    matchPercent: recommendation.pantryMatchPercent,
    missingCount: recommendation.missingIngredients.length,
    dayNumber: dayNumber,
    favorite: favorite,
    onTap: onTap,
    onFavorite: onFavorite,
  );
}

class _RecipeGrid extends StatelessWidget {
  const _RecipeGrid({required this.children});
  final List<Widget> children;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final columns = constraints.maxWidth >= 760 ? 2 : 1;
      final width = (constraints.maxWidth - (columns - 1) * 16) / columns;
      return Wrap(
        spacing: 16,
        children: [
          for (final child in children) SizedBox(width: width, child: child),
        ],
      );
    },
  );
}

class _RecipeOverviewCard extends StatelessWidget {
  const _RecipeOverviewCard({
    required this.recipe,
    required this.matchPercent,
    required this.missingCount,
    required this.favorite,
    required this.onTap,
    required this.onFavorite,
    this.dayNumber,
  });
  final RecipeRecommendationModel recipe;
  final num matchPercent;
  final int missingCount;
  final int? dayNumber;
  final bool favorite;
  final VoidCallback onTap;
  final VoidCallback onFavorite;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final placeholder = Container(
      color: colors.primaryContainer,
      child: Icon(Icons.restaurant_outlined, color: colors.primary, size: 30),
    );
    return Card(
      margin: const EdgeInsets.only(bottom: 14),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: SizedBox(
                  width: 84,
                  height: 104,
                  child: Image.network(
                    recipe.imageUrl,
                    fit: BoxFit.cover,
                    frameBuilder: (_, child, frame, _) =>
                        frame == null ? placeholder : child,
                    errorBuilder: (_, _, _) => placeholder,
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            dayNumber == null
                                ? '$matchPercent% pantry match'
                                : 'DAY $dayNumber',
                            style: Theme.of(context).textTheme.labelSmall
                                ?.copyWith(
                                  color: colors.primary,
                                  fontWeight: FontWeight.w600,
                                ),
                          ),
                        ),
                        IconButton(
                          tooltip: favorite
                              ? 'Remove saved recipe'
                              : 'Save recipe',
                          onPressed: onFavorite,
                          constraints: const BoxConstraints(
                            minWidth: 32,
                            minHeight: 32,
                          ),
                          padding: EdgeInsets.zero,
                          icon: Icon(
                            favorite
                                ? Icons.favorite_rounded
                                : Icons.favorite_border_rounded,
                            size: 20,
                            color: colors.primary,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      recipe.title,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium
                          ?.copyWith(fontSize: 15),
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 10,
                      runSpacing: 4,
                      children: [
                        Text(
                          '${recipe.cookTimeMinutes} min',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                        Text(
                          '${recipe.calories} kcal',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                        Text(
                          missingCount == 0
                              ? 'Ready to cook'
                              : '$missingCount to pick up',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class CookingPreferencesScreen extends StatefulWidget {
  const CookingPreferencesScreen({super.key});
  @override
  State<CookingPreferencesScreen> createState() =>
      _CookingPreferencesScreenState();
}

class _CookingPreferencesScreenState extends State<CookingPreferencesScreen> {
  late final TextEditingController _diet;
  late final TextEditingController _allergens;
  late final TextEditingController _dislikes;
  late final TextEditingController _cuisines;
  late final TextEditingController _calories;
  late final TextEditingController _protein;
  late final TextEditingController _carbs;
  late final TextEditingController _fat;
  late int _servings;
  late int _mealsPerDay;
  late int _maxTime;
  late String _goal;

  @override
  void initState() {
    super.initState();
    final value = context.read<RecipeExperienceProvider>().preferences;
    _diet = TextEditingController(text: value.dietaryNeeds.join(', '));
    _allergens = TextEditingController(text: value.allergens.join(', '));
    _dislikes = TextEditingController(
      text: value.dislikedIngredients.join(', '),
    );
    _cuisines = TextEditingController(text: value.favoriteCuisines.join(', '));
    _calories = TextEditingController(text: '${value.calorieTarget}');
    _protein = TextEditingController(text: '${value.proteinTarget}');
    _carbs = TextEditingController(text: '${value.carbTarget}');
    _fat = TextEditingController(text: '${value.fatTarget}');
    _servings = value.servings;
    _mealsPerDay = value.mealsPerDay;
    _maxTime = value.maxCookMinutes;
    _goal = value.goal;
  }

  List<String> _list(TextEditingController value) => value.text
      .split(',')
      .map((item) => item.trim())
      .where((item) => item.isNotEmpty)
      .toList();

  Future<void> _save() async {
    await context.read<RecipeExperienceProvider>().updatePreferences(
      CookingPreferences(
        dietaryNeeds: _list(_diet),
        allergens: _list(_allergens),
        dislikedIngredients: _list(_dislikes),
        favoriteCuisines: _list(_cuisines),
        goal: _goal,
        servings: _servings,
        mealsPerDay: _mealsPerDay,
        maxCookMinutes: _maxTime,
        calorieTarget: int.tryParse(_calories.text) ?? 2000,
        proteinTarget: int.tryParse(_protein.text) ?? 100,
        carbTarget: int.tryParse(_carbs.text) ?? 250,
        fatTarget: int.tryParse(_fat.text) ?? 65,
      ),
    );
    if (mounted) Navigator.pop(context);
  }

  @override
  void dispose() {
    for (final controller in [
      _diet,
      _allergens,
      _dislikes,
      _cuisines,
      _calories,
      _protein,
      _carbs,
      _fat,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Cooking preferences')),
    body: AppPageBody(
      maxWidth: 760,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
        children: [
          const PageIntro(
            eyebrow: 'MAKE IT PERSONAL',
            title: 'Good food, your way.',
            subtitle: 'Shape your recipes around the people, tastes and goals that matter to you.',
          ),
          const SizedBox(height: 26),
          FormSection(
            title: 'At your table',
            description:
                'Set a goal, your usual portions and the time you have.',
            children: [
              DropdownButtonFormField<String>(
                initialValue: _goal,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Your goal'),
                items:
                    const [
                          'Balanced eating',
                          'Lose weight',
                          'Build muscle',
                          'Save time',
                          'Reduce food waste',
                        ]
                        .map(
                          (value) => DropdownMenuItem(
                            value: value,
                            child: Text(value),
                          ),
                        )
                        .toList(),
                onChanged: (value) => setState(() => _goal = value!),
              ),
              const SizedBox(height: 16),
              FormFieldPair(
                first: DropdownButtonFormField<int>(
                  initialValue: _servings,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'People eating'),
                  items: [1, 2, 3, 4, 5, 6, 8, 10, 12]
                      .map(
                        (value) => DropdownMenuItem(
                          value: value,
                          child: Text('$value'),
                        ),
                      )
                      .toList(),
                  onChanged: (value) => setState(() => _servings = value!),
                ),
                second: DropdownButtonFormField<int>(
                  initialValue: _maxTime,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Time to cook'),
                  items: [15, 20, 30, 45, 60, 90]
                      .map(
                        (value) => DropdownMenuItem(
                          value: value,
                          child: Text('$value min'),
                        ),
                      )
                      .toList(),
                  onChanged: (value) => setState(() => _maxTime = value!),
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          FormSection(
            title: 'Tastes & dietary needs',
            description: 'Separate entries with commas. Allergens and avoided ingredients are applied to suggestions.',
            children: [
              _field(_diet, 'Dietary needs', 'halal, vegetarian, gluten-free'),
              _field(_allergens, 'Allergens', 'peanuts, shellfish'),
              _field(_dislikes, 'Ingredients to avoid', 'mushrooms, olives'),
              _field(_cuisines, 'Favourite cuisines', 'Pakistani, Italian'),
            ],
          ),
          const SizedBox(height: 18),
          FormSection(
            title: 'Daily targets',
            description: 'Your targets are applied per person.',
            children: [
              DropdownButtonFormField<int>(
                initialValue: _mealsPerDay,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Meals per day'),
                items: [1, 2, 3, 4, 5, 6]
                    .map(
                      (value) => DropdownMenuItem(
                        value: value,
                        child: Text('$value meals'),
                      ),
                    )
                    .toList(),
                onChanged: (value) => setState(() => _mealsPerDay = value!),
              ),
              const SizedBox(height: 16),
              FormFieldPair(
                first: _number(_calories, 'Daily calories'),
                second: _number(_protein, 'Protein (g)'),
              ),
              const SizedBox(height: 16),
              FormFieldPair(
                first: _number(_carbs, 'Carbs (g)'),
                second: _number(_fat, 'Fat (g)'),
              ),
              const SizedBox(height: 12),
              Text(
                'About ${((int.tryParse(_calories.text) ?? 2000) / _mealsPerDay).round()} kcal per meal, per person',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ],
      ),
    ),
    bottomNavigationBar: SafeArea(
      child: AppPageBody(
        maxWidth: 760,
        shrinkWrap: true,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 16),
          child: FilledButton.icon(
            onPressed: _save,
            icon: const Icon(Icons.check_rounded),
            label: const Text('Save preferences'),
          ),
        ),
      ),
    ),
  );

  Widget _field(TextEditingController controller, String label, String hint) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: TextField(
          controller: controller,
          decoration: InputDecoration(labelText: label, hintText: hint),
        ),
      );
  Widget _number(TextEditingController controller, String label) => TextField(
    controller: controller,
    keyboardType: TextInputType.number,
    decoration: InputDecoration(labelText: label),
  );
}
