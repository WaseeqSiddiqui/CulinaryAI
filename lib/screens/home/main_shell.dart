import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/chef_name_formatter.dart';
import '../../models/pantry_item_model.dart';
import '../../models/recipe_recommendation_model.dart';
import '../../models/user_model.dart';
import '../../providers/auth_provider.dart';
import '../../providers/pantry_provider.dart';
import '../../providers/theme_provider.dart';
import '../../services/recipe_recommendation_service.dart';
import '../../services/nutrition_calculator_service.dart';
import '../../widgets/recipe_nutrition_panel.dart';
import '../../widgets/app_ui.dart';
import '../chat/chatbot_screen.dart';
import '../cooking/guided_cooking_screen.dart';
import '../pantry/pantry_screen.dart';
import '../pantry/expiry_overview_screen.dart';
import 'kitchen_features_screen.dart';
import '../profile/profile_screen.dart';
import '../scanner/fridge_scanner_screen.dart';
import '../scanner/receipt_scanner_screen.dart';
import '../shopping/shopping_list_screen.dart';
import '../recipes/recipe_hub_screen.dart';

class MainShell extends StatefulWidget {
  const MainShell({super.key});

  static _MainShellState? _of(BuildContext context) =>
      context.findAncestorStateOfType<_MainShellState>();

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _currentIndex = 0;
  int _recipesVersion = 0;

  void showRecipes() => setState(() {
    _recipesVersion++;
    _currentIndex = 2;
  });

  void switchToTab(int index, {String? zoneFilter}) {
    setState(() => _currentIndex = index);
    if (zoneFilter != null) {
      context.read<PantryProvider>().setZoneFilter(zoneFilter);
    }
  }

  static const List<_NavItem> _navItems = [
    _NavItem(
      label: 'Home',
      icon: Icons.cottage_outlined,
      activeIcon: Icons.cottage_rounded,
    ),
    _NavItem(
      label: 'My Pantry',
      icon: Icons.kitchen_outlined,
      activeIcon: Icons.kitchen_rounded,
    ),
    _NavItem(
      label: 'Recipes',
      icon: Icons.restaurant_menu_outlined,
      activeIcon: Icons.restaurant_menu,
    ),
    _NavItem(
      label: 'Shopping',
      icon: Icons.shopping_bag_outlined,
      activeIcon: Icons.shopping_bag_rounded,
    ),
    _NavItem(
      label: 'Profile',
      icon: Icons.person_outline_rounded,
      activeIcon: Icons.person_rounded,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 1000;
        final pages = IndexedStack(
          index: _currentIndex,
          children: [
            const _DashboardTab(),
            const PantryScreen(),
            RecipeHubScreen(key: ValueKey('recipes-$_recipesVersion')),
            const ShoppingListScreen(),
            const ProfileScreen(),
          ],
        );
        return Scaffold(
          body: Row(
            children: [
              if (wide)
                Container(
                  width: 232,
                  decoration: BoxDecoration(
                    color: colors.surface,
                    border: Border(
                      right: BorderSide(color: colors.outlineVariant),
                    ),
                  ),
                  child: SafeArea(
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const SizedBox(height: 12),
                          const BrandMark(),
                          const SizedBox(height: 46),
                          Padding(
                            padding: const EdgeInsets.only(
                              left: 12,
                              bottom: 18,
                            ),
                            child: Text(
                              'YOUR KITCHEN',
                              style: Theme.of(context).textTheme.labelSmall
                                  ?.copyWith(
                                    letterSpacing: 1.5,
                                    color: colors.onSurfaceVariant,
                                  ),
                            ),
                          ),
                          for (var i = 0; i < _navItems.length; i++)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: Material(
                                color: i == _currentIndex
                                    ? colors.primaryContainer
                                    : Colors.transparent,
                                borderRadius: BorderRadius.circular(12),
                                child: InkWell(
                                  borderRadius: BorderRadius.circular(12),
                                  onTap: () => switchToTab(i),
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 14,
                                      vertical: 16,
                                    ),
                                    child: Row(
                                      children: [
                                        Icon(
                                          i == _currentIndex
                                              ? _navItems[i].activeIcon
                                              : _navItems[i].icon,
                                          size: 21,
                                          color: i == _currentIndex
                                              ? colors.primary
                                              : colors.onSurfaceVariant,
                                        ),
                                        const SizedBox(width: 13),
                                        Text(
                                          _navItems[i].label,
                                          style: TextStyle(
                                            fontWeight: i == _currentIndex
                                                ? FontWeight.w700
                                                : FontWeight.w500,
                                            color: i == _currentIndex
                                                ? colors.primary
                                                : colors.onSurfaceVariant,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          const Spacer(),
                          SurfacePanel(
                            padding: const EdgeInsets.all(14),
                            color: colors.primaryContainer,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Icon(Icons.eco_outlined, color: colors.primary),
                                const SizedBox(height: 12),
                                const Text(
                                  'A little less waste.',
                                  style: TextStyle(fontWeight: FontWeight.w600),
                                ),
                                const SizedBox(height: 5),
                                Text(
                                  'A little more possibility.',
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 16),
                          TextButton.icon(
                            onPressed: () =>
                                context.read<ThemeProvider>().toggleTheme(),
                            icon: const Icon(Icons.contrast_rounded, size: 18),
                            label: const Text('Switch appearance'),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              Expanded(
                child: Align(
                  alignment: Alignment.topCenter,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 1200),
                    child: pages,
                  ),
                ),
              ),
            ],
          ),
          bottomNavigationBar: wide
              ? null
              : DecoratedBox(
                  decoration: BoxDecoration(
                    border: Border(
                      top: BorderSide(color: colors.outlineVariant),
                    ),
                  ),
                  child: NavigationBar(
                    selectedIndex: _currentIndex,
                    onDestinationSelected: switchToTab,
                    destinations: _navItems
                        .map(
                          (item) => NavigationDestination(
                            icon: Icon(item.icon),
                            selectedIcon: Icon(item.activeIcon),
                            label: item.label,
                          ),
                        )
                        .toList(),
                  ),
                ),
        );
      },
    );
  }
}

class _NavItem {
  final String label;
  final IconData icon;
  final IconData activeIcon;
  const _NavItem({
    required this.label,
    required this.icon,
    required this.activeIcon,
  });
}

// ── Dashboard Tab (Commercial Food App Architecture) ──────────────────────────

class _DashboardTab extends StatefulWidget {
  const _DashboardTab();

  @override
  State<_DashboardTab> createState() => _DashboardTabState();
}

class _DashboardTabState extends State<_DashboardTab> {
  void _open(Widget screen) =>
      Navigator.of(context)
          .push<void>(MaterialPageRoute(builder: (_) => screen));

  void _logout() {
    showDialog<void>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: const Text('Log out?'),
        content: const Text('You can sign back in whenever you are ready.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialog),
            child: const Text('Stay here'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(dialog);
              context.read<AuthProvider>().logout();
            },
            child: const Text('Log out'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final pantry = context.watch<PantryProvider>();
    final user = context.watch<AuthProvider>().currentUser;
    final theme = context.watch<ThemeProvider>();
    final dark = Theme.of(context).brightness == Brightness.dark;
    final shell = MainShell._of(context);
    return Scaffold(
      drawer: _KitchenDrawer(
        user: user,
        pantry: pantry,
        themeProvider: theme,
        isDark: dark,
        onLogout: _logout,
      ),
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: const Text('Home'),
        actions: [
          TextButton.icon(
            onPressed: () => _open(const KitchenFeaturesScreen()),
            icon: const Icon(Icons.grid_view_outlined, size: 18),
            label: const Text('All features'),
          ),
          Builder(
            builder: (drawer) => IconButton(
              tooltip: 'Account and appearance',
              onPressed: () => Scaffold.of(drawer).openDrawer(),
              icon: const Icon(Icons.menu_rounded),
            ),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: SingleChildScrollView(
        key: const PageStorageKey('home-tasks'),
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Hi, ${ChefNameFormatter.fromUser(user)}',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 6),
            Text(
              'What would you like to do?',
              style: Theme.of(context).textTheme.headlineSmall
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 18),
            KitchenTaskGrid(
              tasks: [
                KitchenTask(
                  title: 'Add food',
                  description: 'Type it or scan groceries',
                  icon: Icons.add_circle_outline,
                  onTap: () => showAddFoodOptions(context),
                ),
                KitchenTask(
                  title: 'Check expiry',
                  description: 'View dates and scan labels',
                  icon: Icons.event_outlined,
                  onTap: () => _open(const ExpiryOverviewScreen()),
                ),
                KitchenTask(
                  title: 'Find recipes',
                  description: 'Cook with your pantry',
                  icon: Icons.restaurant_menu,
                  onTap: () => shell?.showRecipes(),
                ),
                KitchenTask(
                  title: 'Shopping list',
                  description: 'See what you need to buy',
                  icon: Icons.shopping_bag_outlined,
                  onTap: () => shell?.switchToTab(3),
                ),
                KitchenTask(
                  title: 'Scan receipt',
                  description: 'Add a grocery receipt',
                  icon: Icons.receipt_long_outlined,
                  onTap: () => _open(const ReceiptScannerScreen()),
                ),
                KitchenTask(
                  title: 'Ask Chef',
                  description: 'Get help with cooking',
                  icon: Icons.chat_bubble_outline,
                  onTap: () => _open(const ChatbotScreen()),
                ),
              ],
            ),
            const SizedBox(height: 28),
            _HomeSectionHeader(
              title: 'Your pantry',
              action: 'View pantry',
              onAction: () => shell?.switchToTab(1),
            ),
            const SizedBox(height: 12),
            _KitchenPulse(pantry: pantry, isDark: dark),
            const SizedBox(height: 28),
            _HomeSectionHeader(
              title: 'A recipe to try',
              action: 'Browse recipes',
              onAction: () => shell?.showRecipes(),
            ),
            const SizedBox(height: 12),
            _HeroRecipeCard(isDark: dark, pantry: pantry),
            const SizedBox(height: 24),
            SurfacePanel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Plan ahead',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Make a meal plan or keep track of your daily nutrition.',
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      OutlinedButton.icon(
                        onPressed: () => _open(
                          const RecipeHubScreen(section: RecipeSection.weekly),
                        ),
                        icon: const Icon(
                          Icons.calendar_month_outlined,
                          size: 18,
                        ),
                        label: const Text('Meal plan'),
                      ),
                      OutlinedButton.icon(
                        onPressed: () => _open(
                          const RecipeHubScreen(section: RecipeSection.macros),
                        ),
                        icon: const Icon(
                          Icons.monitor_heart_outlined,
                          size: 18,
                        ),
                        label: const Text('Nutrition goals'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HeroRecipeCard extends StatefulWidget {
  final bool isDark;
  final PantryProvider pantry;

  const _HeroRecipeCard({required this.isDark, required this.pantry});

  @override
  State<_HeroRecipeCard> createState() => _HeroRecipeCardState();
}

class _HeroRecipeCardState extends State<_HeroRecipeCard> {
  int _cycleOffset = 0;

  void _showRecipeDetails(
    BuildContext context,
    RecipeRecommendationModel recipe,
  ) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _RecipeDetailModal(
        recipe: recipe,
        pantryItems: widget.pantry.allItems,
        isDark: widget.isDark,
        onStartCooking: (scaledRecipe) {
          Navigator.pop(ctx);
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => GuidedCookingScreen(recipe: scaledRecipe),
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final recipe = RecipeRecommendationService.getHeroRecommendation(
      widget.pantry.allItems,
      cycleOffset: _cycleOffset,
    );
    final match = recipe.matchPercentage(widget.pantry.allItems);
    return Material(
      color: Theme.of(context).colorScheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
        side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _showRecipeDetails(context, recipe),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              height: MediaQuery.sizeOf(context).width < 600 ? 180 : 218,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Image.network(
                    recipe.imageUrl,
                    fit: BoxFit.cover,
                    frameBuilder:
                        (context, child, frame, synchronouslyLoaded) =>
                            frame == null
                            ? Image.asset(
                                'assets/images/hero_dish.jpg',
                                fit: BoxFit.cover,
                              )
                            : child,
                    errorBuilder: (_, _, _) => Image.asset(
                      'assets/images/hero_dish.jpg',
                      fit: BoxFit.cover,
                    ),
                  ),
                  Positioned(
                    top: 16,
                    left: 16,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(9),
                      ),
                      child: Text(
                        '$match% pantry match',
                        style: const TextStyle(
                          color: AppTheme.primaryDark,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    top: 10,
                    right: 10,
                    child: IconButton.filled(
                      tooltip: 'Show another recipe idea',
                      style: IconButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: AppTheme.primaryDark,
                      ),
                      onPressed: () =>
                          setState(() => _cycleOffset = (_cycleOffset + 1) % 6),
                      icon: const Icon(Icons.refresh_rounded, size: 20),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(22),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    recipe.cuisine.toUpperCase(),
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      letterSpacing: 1.6,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    recipe.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.headlineMedium
                        ?.copyWith(fontSize: 25),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      _RecipeMetaChip(
                        icon: Icons.schedule_outlined,
                        label: '${recipe.cookTimeMinutes} min',
                      ),
                      const SizedBox(width: 14),
                      _RecipeMetaChip(
                        icon: Icons.local_fire_department_outlined,
                        label: '${recipe.calories} kcal',
                      ),
                      const Spacer(),
                      Icon(
                        Icons.arrow_forward_rounded,
                        color: Theme.of(context).colorScheme.primary,
                        size: 21,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RecipeDetailModal extends StatefulWidget {
  final RecipeRecommendationModel recipe;
  final List<PantryItemModel> pantryItems;
  final bool isDark;
  final ValueChanged<RecipeRecommendationModel> onStartCooking;

  const _RecipeDetailModal({
    required this.recipe,
    required this.pantryItems,
    required this.isDark,
    required this.onStartCooking,
  });

  @override
  State<_RecipeDetailModal> createState() => _RecipeDetailModalState();
}

class _RecipeDetailModalState extends State<_RecipeDetailModal> {
  late int _servings;

  @override
  void initState() {
    super.initState();
    _servings = widget.recipe.servings;
  }

  @override
  Widget build(BuildContext context) {
    final recipe = widget.recipe.scaledTo(_servings);
    final pantryItems = widget.pantryItems;
    final isDark = widget.isDark;
    final matchPct = recipe.matchPercentage(pantryItems);
    final inPantry = recipe.inPantryIngredients(pantryItems);
    final missing = recipe.missingIngredients(pantryItems);
    final nutrition = NutritionCalculatorService.calculate(
      ingredients: recipe.ingredientDetails,
      servings: recipe.servings,
    );

    return DraggableScrollableSheet(
      initialChildSize: 0.88,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      builder: (ctx, scrollController) => Container(
        decoration: BoxDecoration(
          color: isDark ? AppTheme.surfaceDark : AppTheme.creamSurface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.3),
              blurRadius: 25,
              offset: const Offset(0, -5),
            ),
          ],
        ),
        child: Column(
          children: [
            // Handle bar
            const SizedBox(height: 12),
            Container(
              width: 44,
              height: 5,
              decoration: BoxDecoration(
                color: isDark ? Colors.white24 : AppTheme.creamBorder,
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            const SizedBox(height: 8),
            // Header
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: AppTheme.primaryFlame.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      '${recipe.cuisine} • ${recipe.difficulty}',
                      style: const TextStyle(
                        color: AppTheme.primaryFlame,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close_rounded),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                controller: scrollController,
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 8,
                ),
                children: [
                  // Hero Photo
                  ClipRRect(
                    borderRadius: BorderRadius.circular(20),
                    child: Stack(
                      children: [
                        Image.network(
                          recipe.imageUrl,
                          height: 200,
                          width: double.infinity,
                          fit: BoxFit.cover,
                          errorBuilder: (_, _, _) => Container(
                            height: 200,
                            color: isDark
                                ? AppTheme.cardDark
                                : AppTheme.creamBeige,
                            child: const Center(
                              child: Icon(
                                Icons.restaurant_rounded,
                                size: 48,
                                color: AppTheme.primaryFlame,
                              ),
                            ),
                          ),
                        ),
                        Positioned(
                          top: 12,
                          right: 12,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.75),
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  matchPct >= 80
                                      ? Icons.check_circle
                                      : Icons.pie_chart,
                                  color: matchPct >= 80
                                      ? const Color(0xFF6EE7B7)
                                      : AppTheme.warmSaffron,
                                  size: 14,
                                ),
                                const SizedBox(width: 5),
                                Text(
                                  '$matchPct% Match',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    recipe.title,
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.4,
                      color: isDark
                          ? AppTheme.textDarkPrimary
                          : AppTheme.textLightPrimary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    recipe.description,
                    style: TextStyle(
                      fontSize: 14,
                      height: 1.4,
                      color: isDark
                          ? AppTheme.textDarkSecondary
                          : AppTheme.textLightSecondary,
                    ),
                  ),
                  const SizedBox(height: 14),

                  // Quick specs row (Warm Cream Cards)
                  Row(
                    children: [
                      _specCard(
                        icon: Icons.timer_outlined,
                        title: 'Time',
                        value: '${recipe.cookTimeMinutes}m',
                        isDark: isDark,
                      ),
                      const SizedBox(width: 10),
                      _specCard(
                        icon: Icons.local_fire_department_outlined,
                        title: 'Per serving',
                        value: '${nutrition.perServing.calories.round()} kcal',
                        isDark: isDark,
                      ),
                      const SizedBox(width: 10),
                      _specCard(
                        icon: Icons.kitchen_rounded,
                        title: 'Available',
                        value:
                            '${inPantry.length}/${recipe.ingredients.length}',
                        isDark: isDark,
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),

                  RecipeNutritionPanel(
                    recipe: widget.recipe,
                    isDark: isDark,
                    onServingsChanged: (value) =>
                        setState(() => _servings = value),
                  ),
                  const SizedBox(height: 18),

                  // Why This Dish Banner (Explaining the daily rotation and inventory algorithm)
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: isDark
                          ? AppTheme.cardDark
                          : AppTheme.creamBeige.withValues(alpha: 0.6),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: isDark
                            ? AppTheme.borderDark
                            : AppTheme.creamBorder,
                      ),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(
                          Icons.auto_awesome_rounded,
                          color: AppTheme.primaryFlame,
                          size: 20,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'How AI Picked This Today',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  color: isDark
                                      ? AppTheme.textDarkPrimary
                                      : AppTheme.textLightPrimary,
                                ),
                              ),
                              const SizedBox(height: 3),
                              Text(
                                'Calculated from live pantry inventory ($matchPct% in stock) and daily calendar rotation to ensure variety every morning.',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: isDark
                                      ? AppTheme.textDarkSecondary
                                      : AppTheme.textLightSecondary,
                                  height: 1.35,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 18),

                  // Ingredients Breakdown
                  Text(
                    'Ingredients Breakdown',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: isDark
                          ? AppTheme.textDarkPrimary
                          : AppTheme.textLightPrimary,
                    ),
                  ),
                  const SizedBox(height: 10),
                  // In Pantry Section
                  if (inPantry.isNotEmpty) ...[
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFF10B981).withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: const Color(0xFF10B981)
                              .withValues(alpha: 0.25),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Icon(
                                Icons.check_circle_rounded,
                                color: Color(0xFF10B981),
                                size: 16,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                'Ready in Your Pantry (${inPantry.length})',
                                style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  color: Color(0xFF059669),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: inPantry
                                .map(
                                  (item) => Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 10,
                                      vertical: 5,
                                    ),
                                    decoration: BoxDecoration(
                                      color: isDark
                                          ? AppTheme.surfaceDark
                                          : Colors.white,
                                      borderRadius: BorderRadius.circular(20),
                                      border: Border.all(
                                        color: const Color(0xFF10B981)
                                            .withValues(alpha: 0.3),
                                      ),
                                    ),
                                    child: Text(
                                      item,
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                        color: isDark
                                            ? AppTheme.textDarkPrimary
                                            : AppTheme.textLightPrimary,
                                      ),
                                    ),
                                  ),
                                )
                                .toList(),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],

                  // Missing Items Section
                  if (missing.isNotEmpty) ...[
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppTheme.warmSaffron.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: AppTheme.warmSaffron.withValues(alpha: 0.3),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Icon(
                                Icons.shopping_cart_outlined,
                                color: AppTheme.warmSaffron,
                                size: 16,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                'Missing Ingredients (${missing.length})',
                                style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  color: AppTheme.warmSaffron,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: missing
                                .map(
                                  (item) => Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 10,
                                      vertical: 5,
                                    ),
                                    decoration: BoxDecoration(
                                      color: isDark
                                          ? AppTheme.surfaceDark
                                          : Colors.white,
                                      borderRadius: BorderRadius.circular(20),
                                      border: Border.all(
                                        color: AppTheme.warmSaffron.withValues(
                                          alpha: 0.3,
                                        ),
                                      ),
                                    ),
                                    child: Text(
                                      item,
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                        color: isDark
                                            ? AppTheme.textDarkPrimary
                                            : AppTheme.textLightPrimary,
                                      ),
                                    ),
                                  ),
                                )
                                .toList(),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],

                  // Cooking Steps Section
                  Text(
                    'Step-by-Step Method',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: isDark
                          ? AppTheme.textDarkPrimary
                          : AppTheme.textLightPrimary,
                    ),
                  ),
                  const SizedBox(height: 10),
                  ...recipe.instructions.asMap().entries.map((entry) {
                    final idx = entry.key + 1;
                    final step = entry.value;
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            width: 26,
                            height: 26,
                            decoration: BoxDecoration(
                              color: AppTheme.primaryFlame,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            alignment: Alignment.center,
                            child: Text(
                              '$idx',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              step,
                              style: TextStyle(
                                fontSize: 13,
                                height: 1.4,
                                color: isDark
                                    ? AppTheme.textDarkSecondary
                                    : AppTheme.textLightSecondary,
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  }),
                  const SizedBox(height: 20),

                  // Bottom Action Button
                  ElevatedButton(
                    onPressed: () => widget.onStartCooking(recipe),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.primaryFlame,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      elevation: 2,
                    ),
                    child: const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.restaurant_menu_rounded, size: 20),
                        SizedBox(width: 8),
                        Text(
                          'Start Guided Cooking',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _specCard({
    required IconData icon,
    required String title,
    required String value,
    required bool isDark,
  }) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        decoration: BoxDecoration(
          color: isDark
              ? AppTheme.cardDark
              : AppTheme.creamBeige.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isDark ? AppTheme.borderDark : AppTheme.creamBorder,
          ),
        ),
        child: Column(
          children: [
            Icon(icon, color: AppTheme.primaryFlame, size: 20),
            const SizedBox(height: 4),
            Text(
              value,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w800,
                color: isDark
                    ? AppTheme.textDarkPrimary
                    : AppTheme.textLightPrimary,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              title,
              style: TextStyle(
                fontSize: 11,
                color: isDark
                    ? AppTheme.textDarkMuted
                    : AppTheme.textLightMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RecipeMetaChip extends StatelessWidget {
  const _RecipeMetaChip({required this.icon, required this.label});
  final IconData icon;
  final String label;
  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(
        icon,
        size: 15,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
      const SizedBox(width: 5),
      Text(label, style: Theme.of(context).textTheme.bodySmall),
    ],
  );
}

class _HomeSectionHeader extends StatelessWidget {
  final String title;
  final String? action;
  final VoidCallback? onAction;

  const _HomeSectionHeader({required this.title, this.action, this.onAction});

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.end,
    children: [
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontSize: 19,
                fontWeight: FontWeight.w600,
                letterSpacing: -.4,
              ),
            ),
          ],
        ),
      ),
      if (action != null)
        TextButton(
          onPressed: onAction,
          style: TextButton.styleFrom(
            foregroundColor: AppTheme.primaryFlame,
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
            textStyle: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w800,
            ),
          ),
          child: Text(
            action!,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: Theme.of(context).colorScheme.primary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
    ],
  );
}

class _KitchenPulse extends StatelessWidget {
  final PantryProvider pantry;
  final bool isDark;

  const _KitchenPulse({required this.pantry, required this.isDark});

  @override
  Widget build(BuildContext context) {
    final shell = context.findAncestorStateOfType<_MainShellState>();
    final hasAttention = pantry.useSoonCount + pantry.expiredCount > 0;

    return Column(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
          decoration: BoxDecoration(
            color: isDark ? AppTheme.surfaceDark : Colors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: isDark ? AppTheme.borderDark : AppTheme.creamBorder,
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: _PulseStat(
                  value: '${pantry.totalCount}',
                  label: 'Current Stock',
                  icon: Icons.inventory_2_rounded,
                  color: AppTheme.primaryFlame,
                  isDark: isDark,
                  onTap: () => shell?.switchToTab(1),
                ),
              ),
              SizedBox(
                height: 58,
                child: VerticalDivider(
                  width: 1,
                  color: isDark ? AppTheme.borderDark : AppTheme.creamBorder,
                ),
              ),
              Expanded(
                child: _PulseStat(
                  value: '${pantry.useSoonCount + pantry.expiredCount}',
                  label: 'Expiry alerts',
                  icon: Icons.schedule_rounded,
                  color: AppTheme.warmSaffron,
                  isDark: isDark,
                  isAlert: hasAttention,
                  onTap: () => Navigator.of(context).push<void>(
                    MaterialPageRoute(
                      builder: (_) => const ExpiryOverviewScreen(),
                    ),
                  ),
                ),
              ),
              SizedBox(
                height: 58,
                child: VerticalDivider(
                  width: 1,
                  color: isDark ? AppTheme.borderDark : AppTheme.creamBorder,
                ),
              ),
              Expanded(
                child: _PulseStat(
                  value: '${pantry.lowStockCount}',
                  label: 'Low Stock',
                  icon: Icons.shopping_basket_rounded,
                  color: AppTheme.freshHerb,
                  isDark: isDark,
                  onTap: () => shell?.switchToTab(3),
                ),
              ),
            ],
          ),
        ),
        if (hasAttention) ...[
          const SizedBox(height: 10),
          GestureDetector(
            onTap: () => Navigator.of(context).push<void>(
              MaterialPageRoute(builder: (_) => const ExpiryOverviewScreen()),
            ),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
              decoration: BoxDecoration(
                color: AppTheme.warmSaffron.withValues(
                  alpha: isDark ? 0.16 : 0.10,
                ),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: AppTheme.warmSaffron.withValues(
                    alpha: isDark ? 0.35 : 0.25,
                  ),
                ),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: AppTheme.warmSaffron.withValues(alpha: 0.2),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.eco_rounded,
                      color: AppTheme.warmSaffron,
                      size: 16,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          pantry.expiredCount > 0
                              ? '${pantry.expiredCount} expired & ${pantry.useSoonCount} expiring item(s)'
                              : '${pantry.useSoonCount} item(s) need attention soon',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                            color: isDark
                                ? AppTheme.textDarkPrimary
                                : AppTheme.textLightPrimary,
                          ),
                        ),
                        const SizedBox(height: 1),
                        Text(
                          'Review these dates before using the ingredients.',
                          style: TextStyle(
                            fontSize: 11,
                            color: isDark
                                ? AppTheme.textDarkSecondary
                                : AppTheme.textLightSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: AppTheme.warmSaffron,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Text(
                      'Use Food',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _PulseStat extends StatelessWidget {
  final String value;
  final String label;
  final IconData icon;
  final Color color;
  final bool isDark;
  final bool isAlert;
  final VoidCallback? onTap;

  const _PulseStat({
    required this.value,
    required this.label,
    required this.icon,
    required this.color,
    required this.isDark,
    this.isAlert = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) => Material(
    color: Colors.transparent,
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Ink(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: isDark ? 0.16 : 0.10),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(icon, size: 15, color: color),
                ),
                if (isAlert) ...[
                  const SizedBox(width: 5),
                  Container(
                    width: 6,
                    height: 6,
                    decoration: const BoxDecoration(
                      color: AppTheme.warmSaffron,
                      shape: BoxShape.circle,
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 7),
            Text(
              value,
              style: TextStyle(
                color: isDark
                    ? AppTheme.textDarkPrimary
                    : AppTheme.textLightPrimary,
                fontSize: 18,
                fontWeight: FontWeight.w900,
                letterSpacing: -0.5,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: isDark
                    ? AppTheme.textDarkSecondary
                    : AppTheme.textLightSecondary,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _KitchenDrawer extends StatelessWidget {
  final UserModel? user;
  final PantryProvider pantry;
  final ThemeProvider themeProvider;
  final bool isDark;
  final VoidCallback onLogout;

  const _KitchenDrawer({
    required this.user,
    required this.pantry,
    required this.themeProvider,
    required this.isDark,
    required this.onLogout,
  });

  @override
  Widget build(BuildContext context) {
    final shell = MainShell._of(context);
    final drawerBg = isDark ? AppTheme.bgDark : Colors.white;
    final itemColor = isDark
        ? AppTheme.textDarkPrimary
        : AppTheme.textLightPrimary;
    final subColor = isDark
        ? AppTheme.textDarkSecondary
        : AppTheme.textLightSecondary;
    final borderColor = isDark ? AppTheme.borderDark : AppTheme.borderLight;

    return Drawer(
      backgroundColor: drawerBg,
      child: SafeArea(
        child: Column(
          children: [
            // Chef Profile Header Card with ambient gradient
            Container(
              margin: const EdgeInsets.fromLTRB(16, 12, 16, 10),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: isDark
                      ? [AppTheme.surfaceDark2, AppTheme.surfaceDark]
                      : [AppTheme.bgLight, Colors.white],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: borderColor),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: isDark ? 0.3 : 0.04),
                    blurRadius: 10,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Stack(
                        children: [
                          CircleAvatar(
                            radius: 25,
                            backgroundColor: AppTheme.primaryFlame.withValues(
                              alpha: 0.15,
                            ),
                            child: const Icon(
                              Icons.person_rounded,
                              color: AppTheme.primaryFlame,
                              size: 28,
                            ),
                          ),
                          Positioned(
                            right: 0,
                            bottom: 0,
                            child: Container(
                              padding: const EdgeInsets.all(3),
                              decoration: const BoxDecoration(
                                color: AppTheme.primaryFlame,
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Icons.restaurant,
                                color: Colors.white,
                                size: 9,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Chef ${ChefNameFormatter.fromUser(user)}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w800,
                                color: itemColor,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              user?.email ?? 'chef@culinary.ai',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(fontSize: 12, color: subColor),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  // Kitchen Status Badges Row
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 9,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: AppTheme.freshHerb.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.inventory_2_outlined,
                              size: 12,
                              color: AppTheme.freshHerb,
                            ),
                            const SizedBox(width: 5),
                            Text(
                              '${pantry.totalCount} items stocked',
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: AppTheme.freshHerb,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      if (pantry.lowStockCount > 0)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: AppTheme.warmAmber.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            '${pantry.lowStockCount} low',
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: AppTheme.warmAmber,
                            ),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),

            // Navigation List Items
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 4,
                ),
                children: [
                  _DrawerNavTile(
                    icon: Icons.cottage_rounded,
                    title: 'Home',
                    subtitle: 'Overview',
                    isDark: isDark,
                    onTap: () {
                      Navigator.pop(context);
                      shell?.switchToTab(0);
                    },
                  ),
                  _DrawerNavTile(
                    icon: Icons.kitchen_rounded,
                    title: 'Pantry',
                    subtitle: '${pantry.totalCount} items',
                    isDark: isDark,
                    onTap: () {
                      Navigator.pop(context);
                      shell?.switchToTab(1);
                    },
                  ),
                  _DrawerNavTile(
                    icon: Icons.chat_bubble_rounded,
                    title: 'Chef Chat',
                    subtitle: 'Ask one focused question',
                    isDark: isDark,
                    onTap: () {
                      Navigator.pop(context);
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const ChatbotScreen(),
                        ),
                      );
                    },
                  ),
                  ExpansionTile(
                    leading: const Icon(Icons.restaurant_menu_rounded),
                    title: const Text(
                      'Cooking tools',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                    subtitle: const Text('Recipes, goals and weekly plan'),
                    children: [
                      _DrawerNavTile(
                        icon: Icons.restaurant_menu_rounded,
                        title: 'Pantry recipes',
                        subtitle: 'Cook with what you already have',
                        isDark: isDark,
                        onTap: () {
                          Navigator.pop(context);
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const RecipeHubScreen(),
                            ),
                          );
                        },
                      ),
                      _DrawerNavTile(
                        icon: Icons.auto_awesome_rounded,
                        title: 'Recipe creator',
                        subtitle: 'Create one pantry-aware recipe',
                        isDark: isDark,
                        onTap: () {
                          Navigator.pop(context);
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const RecipeHubScreen(
                                section: RecipeSection.create,
                              ),
                            ),
                          );
                        },
                      ),
                      _DrawerNavTile(
                        icon: Icons.track_changes_rounded,
                        title: 'Nutrition goals',
                        subtitle: 'Calories and macros per person',
                        isDark: isDark,
                        onTap: () {
                          Navigator.pop(context);
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const RecipeHubScreen(
                                section: RecipeSection.macros,
                              ),
                            ),
                          );
                        },
                      ),
                      _DrawerNavTile(
                        icon: Icons.calendar_view_week_rounded,
                        title: '7-day meal plan',
                        subtitle: 'A pantry-first weekly plan',
                        isDark: isDark,
                        onTap: () {
                          Navigator.pop(context);
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const RecipeHubScreen(
                                section: RecipeSection.weekly,
                              ),
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                  ExpansionTile(
                    leading: const Icon(Icons.inventory_2_rounded),
                    title: const Text(
                      'Stock & shopping',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                    subtitle: const Text('List, fridge and receipt scans'),
                    children: [
                      _DrawerNavTile(
                        icon: Icons.shopping_bag_rounded,
                        title: 'Shopping list',
                        subtitle: 'Items to pick up',
                        isDark: isDark,
                        onTap: () {
                          Navigator.pop(context);
                          shell?.switchToTab(3);
                        },
                      ),
                      _DrawerNavTile(
                        icon: Icons.kitchen_rounded,
                        title: 'Scan fridge',
                        subtitle: 'Detect visible food on messy shelves',
                        isDark: isDark,
                        onTap: () {
                          Navigator.pop(context);
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const FridgeScannerScreen(),
                            ),
                          );
                        },
                      ),
                      _DrawerNavTile(
                        icon: Icons.receipt_long_rounded,
                        title: 'Scan receipt',
                        subtitle: 'Add items from a receipt',
                        isDark: isDark,
                        onTap: () {
                          Navigator.pop(context);
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const ReceiptScannerScreen(),
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                  _DrawerNavTile(
                    icon: Icons.person_rounded,
                    title: 'Profile',
                    subtitle: 'Account and preferences',
                    isDark: isDark,
                    onTap: () {
                      Navigator.pop(context);
                      shell?.switchToTab(4);
                    },
                  ),

                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 8),
                    child: Divider(height: 1),
                  ),

                  // Mode Switcher inside Drawer
                  Container(
                    margin: const EdgeInsets.symmetric(vertical: 4),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: isDark ? AppTheme.surfaceDark2 : AppTheme.bgLight,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: borderColor),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          themeProvider.isDarkMode
                              ? Icons.dark_mode_rounded
                              : Icons.light_mode_rounded,
                          size: 20,
                          color: themeProvider.isDarkMode
                              ? AppTheme.warmSaffron
                              : AppTheme.primaryFlame,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Appearance',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  color: itemColor,
                                ),
                              ),
                              Text(
                                themeProvider.isDarkMode
                                    ? 'Dark mode'
                                    : 'Light mode',
                                style: TextStyle(fontSize: 11, color: subColor),
                              ),
                            ],
                          ),
                        ),
                        Switch(
                          value: themeProvider.isDarkMode,
                          activeThumbColor: AppTheme.warmSaffron,
                          activeTrackColor: AppTheme.warmSaffron.withValues(
                            alpha: 0.3,
                          ),
                          onChanged: (_) => themeProvider.toggleTheme(),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // Drawer Footer with Logout
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 6, 16, 12),
              child: Column(
                children: [
                  InkWell(
                    borderRadius: BorderRadius.circular(14),
                    onTap: () {
                      Navigator.pop(context);
                      onLogout();
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      decoration: BoxDecoration(
                        color: AppTheme.errorRed.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: AppTheme.errorRed.withValues(alpha: 0.25),
                        ),
                      ),
                      child: const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.logout_rounded,
                            size: 18,
                            color: AppTheme.errorRed,
                          ),
                          SizedBox(width: 8),
                          Text(
                            'Sign out',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: AppTheme.errorRed,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'CulinaryAI Pro • v2.4 Smart Kitchen',
                    style: TextStyle(
                      fontSize: 10,
                      color: subColor.withValues(alpha: 0.6),
                      letterSpacing: 0.5,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DrawerNavTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool isDark;
  final VoidCallback onTap;

  const _DrawerNavTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.isDark,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      dense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      leading: Icon(icon, size: 22),
      title: Text(
        title,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: isDark ? AppTheme.textDarkPrimary : AppTheme.textLightPrimary,
        ),
      ),
      subtitle: Text(
        subtitle,
        style: TextStyle(
          fontSize: 11,
          color: isDark
              ? AppTheme.textDarkSecondary
              : AppTheme.textLightSecondary,
        ),
      ),
      onTap: onTap,
    );
  }
}
