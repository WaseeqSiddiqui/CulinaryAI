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
import '../chat/chatbot_screen.dart';
import '../cooking/guided_cooking_screen.dart';
import '../pantry/pantry_screen.dart';
import '../profile/profile_screen.dart';
import '../scanner/receipt_scanner_screen.dart';
import '../shopping/shopping_list_screen.dart';

class MainShell extends StatefulWidget {
  const MainShell({super.key});

  static _MainShellState? _of(BuildContext context) =>
      context.findAncestorStateOfType<_MainShellState>();

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _currentIndex = 0;

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
      label: 'Chef Chat',
      icon: Icons.chat_bubble_outline_rounded,
      activeIcon: Icons.chat_bubble_rounded,
    ),
    _NavItem(
      label: 'Restock',
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
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: const [
          _DashboardTab(),
          PantryScreen(),
          _RecipesPlaceholderTab(),
          ShoppingListScreen(),
          ProfileScreen(),
        ],
      ),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: isDark ? AppTheme.surfaceDark : Colors.white,
          border: Border(
            top: BorderSide(
              color: isDark ? AppTheme.borderDark : AppTheme.borderLight,
              width: 1,
            ),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: isDark ? 0.3 : 0.05),
              blurRadius: 12,
              offset: const Offset(0, -2),
            ),
          ],
        ),
        child: NavigationBar(
          height: 60,
          selectedIndex: _currentIndex,
          onDestinationSelected: (idx) => setState(() => _currentIndex = idx),
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
  final _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _openChefChat([String? question]) {
    final cleanQuestion = question?.trim();
    FocusScope.of(context).unfocus();
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ChatbotScreen(
          initialQuestion: cleanQuestion == null || cleanQuestion.isEmpty
              ? null
              : cleanQuestion,
        ),
      ),
    );
    _searchController.clear();
  }

  void _showLogoutDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Log Out'),
        content: const Text('Are you sure you want to log out of CulinaryAI?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.errorRed),
            onPressed: () {
              Navigator.pop(ctx);
              context.read<AuthProvider>().logout();
            },
            child: const Text('Log Out'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final authProvider = context.watch<AuthProvider>();
    final pantry = context.watch<PantryProvider>();
    final themeProvider = context.watch<ThemeProvider>();
    final user = authProvider.currentUser;
    final chefName = ChefNameFormatter.fromUser(user);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? AppTheme.bgDark : AppTheme.bgLight,
      drawer: _KitchenDrawer(
        user: user,
        pantry: pantry,
        themeProvider: themeProvider,
        isDark: isDark,
        onLogout: () => _showLogoutDialog(context),
      ),
      appBar: AppBar(
        titleSpacing: 4,
        leading: Builder(
          builder: (drawerCtx) => IconButton(
            icon: const Icon(Icons.menu_rounded, size: 24),
            tooltip: 'Open Kitchen Menu',
            onPressed: () => Scaffold.of(drawerCtx).openDrawer(),
          ),
        ),
        title: Row(
          children: [
            // User Avatar with chef hat badge
            Stack(
              clipBehavior: Clip.none,
              children: [
                CircleAvatar(
                  radius: 20,
                  backgroundColor: AppTheme.primaryFlame.withValues(
                    alpha: 0.15,
                  ),
                  child: const Icon(
                    Icons.person_rounded,
                    color: AppTheme.primaryFlame,
                    size: 22,
                  ),
                ),
                Positioned(
                  right: -2,
                  bottom: -2,
                  child: Container(
                    padding: const EdgeInsets.all(2),
                    decoration: BoxDecoration(
                      color: AppTheme.primaryFlame,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: isDark ? AppTheme.bgDark : Colors.white,
                        width: 1.5,
                      ),
                    ),
                    child: const Icon(
                      Icons.restaurant,
                      color: Colors.white,
                      size: 10,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Chef $chefName',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.3,
                      color: isDark
                          ? AppTheme.textDarkPrimary
                          : AppTheme.textLightPrimary,
                    ),
                  ),
                  Row(
                    children: [
                      Container(
                        width: 6,
                        height: 6,
                        decoration: const BoxDecoration(
                          color: AppTheme.freshHerb,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 5),
                      Expanded(
                        child: Text(
                          'Main Kitchen • ${pantry.totalCount} items in stock',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 11,
                            color: isDark
                                ? AppTheme.textDarkSecondary
                                : AppTheme.textLightSecondary,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          // Theme Toggle Button
          IconButton(
            icon: Icon(
              themeProvider.isDarkMode
                  ? Icons.light_mode_rounded
                  : Icons.dark_mode_rounded,
              color: themeProvider.isDarkMode
                  ? AppTheme.warmSaffron
                  : AppTheme.primaryFlame,
              size: 22,
            ),
            tooltip: themeProvider.isDarkMode ? 'Light Mode' : 'Dark Mode',
            onPressed: () => themeProvider.toggleTheme(),
          ),
          IconButton(
            icon: const Icon(Icons.logout_rounded, size: 21),
            tooltip: 'Log Out',
            onPressed: () => _showLogoutDialog(context),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(18, 8, 18, 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Search / Ask Chef Chat
            Container(
              height: 44,
              padding: const EdgeInsets.symmetric(horizontal: 4),
              decoration: BoxDecoration(
                color: isDark ? AppTheme.surfaceDark : AppTheme.creamSurface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: isDark ? AppTheme.borderDark : AppTheme.creamBorder,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.03),
                    blurRadius: 10,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: TextField(
                key: const Key('dashboardChefSearch'),
                controller: _searchController,
                textInputAction: TextInputAction.search,
                onSubmitted: _openChefChat,
                style: const TextStyle(fontSize: 13),
                decoration: InputDecoration(
                  hintText: 'Ask what you can cook today…',
                  isDense: true,
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  filled: false,
                  prefixIcon: const Icon(
                    Icons.search_rounded,
                    color: AppTheme.primaryFlame,
                    size: 20,
                  ),
                  prefixIconConstraints: const BoxConstraints(
                    minWidth: 40,
                    minHeight: 40,
                  ),
                  suffixIcon: IconButton(
                    key: const Key('dashboardChefSearchButton'),
                    tooltip: 'Ask Chef Chat',
                    onPressed: () => _openChefChat(_searchController.text),
                    icon: Container(
                      padding: const EdgeInsets.all(5),
                      decoration: BoxDecoration(
                        color: AppTheme.primaryFlame.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(9),
                      ),
                      child: const Icon(
                        Icons.arrow_upward_rounded,
                        size: 16,
                        color: AppTheme.primaryFlame,
                      ),
                    ),
                  ),
                  suffixIconConstraints: const BoxConstraints(
                    minWidth: 40,
                    minHeight: 40,
                  ),
                  contentPadding: const EdgeInsets.symmetric(vertical: 10),
                ),
              ),
            ),

            const SizedBox(height: 20),

            // Hero Interactive Recipe Inspiration Card (With Real Food Photography)
            _HeroRecipeCard(isDark: isDark, pantry: pantry),

            const SizedBox(height: 26),

            // Section 1: Interactive Pantry Storage Zones
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Pantry Storage Zones',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.3,
                    color: isDark
                        ? AppTheme.textDarkPrimary
                        : AppTheme.textLightPrimary,
                  ),
                ),
                GestureDetector(
                  onTap: () {
                    context
                        .findAncestorStateOfType<_MainShellState>()
                        ?.switchToTab(1);
                  },
                  child: const Row(
                    children: [
                      Text(
                        'View All',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.primaryFlame,
                        ),
                      ),
                      Icon(
                        Icons.chevron_right_rounded,
                        size: 18,
                        color: AppTheme.primaryFlame,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _PantryZonesGrid(isDark: isDark),

            const SizedBox(height: 26),

            // Section 2: Quick Receipt Scanner Banner
            _ReceiptScanBanner(
              isDark: isDark,
              onScanTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const ReceiptScannerScreen()),
              ),
            ),

            const SizedBox(height: 26),

            // Section 3: Ingredients Expiring / Low Stock (Interactive Carousel)
            if (pantry.lowStockCount > 0) ...[
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      const Icon(
                        Icons.bolt_rounded,
                        color: AppTheme.warmSaffron,
                        size: 20,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'Pantry Attention & Low Stock',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.3,
                          color: isDark
                              ? AppTheme.textDarkPrimary
                              : AppTheme.textLightPrimary,
                        ),
                      ),
                    ],
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: AppTheme.warmSaffron.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '${pantry.lowStockCount} Low',
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        color: AppTheme.warmSaffron,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _AttentionItemsCarousel(isDark: isDark),
              const SizedBox(height: 26),
            ],

            // Section 4: What You Can Cook Tonight (Interactive Photo Cards)
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Recommended With Your Ingredients',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.3,
                    color: isDark
                        ? AppTheme.textDarkPrimary
                        : AppTheme.textLightPrimary,
                  ),
                ),
                const Icon(
                  Icons.tune_rounded,
                  size: 18,
                  color: AppTheme.primaryFlame,
                ),
              ],
            ),
            const SizedBox(height: 12),
            _RecommendedMealsCarousel(isDark: isDark),
          ],
        ),
      ),
    );
  }
}

// ── Hero Interactive Recipe Card ─────────────────────────────────────────────

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
        onStartCooking: () {
          Navigator.pop(ctx);
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => GuidedCookingScreen(recipe: recipe),
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
    final matchPct = recipe.matchPercentage(widget.pantry.allItems);
    final matchedCount = recipe.matchedCount(widget.pantry.allItems);

    return GestureDetector(
      onTap: () => _showRecipeDetails(context, recipe),
      child: Container(
        height: 245,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: widget.isDark ? 0.5 : 0.12),
              blurRadius: 20,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(24),
          child: Stack(
            fit: StackFit.expand,
            children: [
              // Dynamic Background Food Photography
              Image.network(
                recipe.imageUrl,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => Image.asset(
                  'assets/images/hero_dish.jpg',
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => Container(
                    color: widget.isDark
                        ? const Color(0xFF1C1917)
                        : AppTheme.creamBeige,
                  ),
                ),
              ),
              // Gradient Overlay for text legibility
              DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.black.withValues(alpha: 0.22),
                      Colors.black.withValues(alpha: 0.55),
                      Colors.black.withValues(alpha: 0.94),
                    ],
                    stops: const [0.0, 0.45, 1.0],
                  ),
                ),
              ),
              // Content
              Padding(
                padding: const EdgeInsets.all(18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Top Pills and Interactive Rotation Trigger
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 5,
                          ),
                          decoration: BoxDecoration(
                            color: AppTheme.primaryFlame,
                            borderRadius: BorderRadius.circular(20),
                            boxShadow: [
                              BoxShadow(
                                color: AppTheme.primaryFlame.withValues(
                                  alpha: 0.4,
                                ),
                                blurRadius: 8,
                              ),
                            ],
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                Icons.auto_awesome,
                                color: Colors.white,
                                size: 12,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                _cycleOffset == 0
                                    ? "Today's Best Match"
                                    : 'Option #${_cycleOffset + 1}',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
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
                            color: Colors.black.withValues(alpha: 0.4),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color:
                                  (matchPct >= 80
                                          ? const Color(0xFF6EE7B7)
                                          : AppTheme.warmSaffron)
                                      .withValues(alpha: 0.7),
                              width: 1,
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                matchPct >= 80
                                    ? Icons.check_circle_rounded
                                    : Icons.pie_chart_rounded,
                                color: matchPct >= 80
                                    ? const Color(0xFF6EE7B7)
                                    : AppTheme.warmSaffron,
                                size: 12,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                '$matchPct% In Pantry',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const Spacer(),
                        // Interactive Next / Cycle Shuffle Button
                        GestureDetector(
                          onTap: () {
                            setState(() {
                              _cycleOffset = (_cycleOffset + 1) % 6;
                            });
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 7,
                              vertical: 5,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.22),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: Colors.white.withValues(alpha: 0.35),
                                width: 1,
                              ),
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.sync_rounded,
                                  color: Colors.white,
                                  size: 13,
                                ),
                                SizedBox(width: 4),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                    const Spacer(),
                    // Dish Title & Cuisine Tag
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 7,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.22),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            recipe.cuisine.toUpperCase(),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          recipe.difficulty,
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.8),
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      recipe.title,
                      style: const TextStyle(
                        fontSize: 19,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                        letterSpacing: -0.4,
                        height: 1.25,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 10),
                    // Metadata + Cook Now Button
                    Row(
                      children: [
                        _RecipeMetaChip(
                          icon: Icons.timer_outlined,
                          label: '${recipe.cookTimeMinutes}m',
                        ),
                        const SizedBox(width: 4),
                        _RecipeMetaChip(
                          icon: Icons.local_fire_department_outlined,
                          label: '${recipe.calories}kcal',
                        ),
                        const SizedBox(width: 4),
                        _RecipeMetaChip(
                          icon: Icons.kitchen_rounded,
                          label:
                              '$matchedCount/${recipe.ingredients.length} items',
                        ),
                        const Spacer(),
                        ElevatedButton(
                          onPressed: () => _showRecipeDetails(context, recipe),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppTheme.primaryFlame,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 9,
                              vertical: 9,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                            elevation: 0,
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                'Cook',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              SizedBox(width: 4),
                              Icon(Icons.arrow_forward_rounded, size: 14),
                            ],
                          ),
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

// ── Recipe Detail Interactive Modal Sheet ───────────────────────────────────

class _RecipeDetailModal extends StatelessWidget {
  final RecipeRecommendationModel recipe;
  final List<PantryItemModel> pantryItems;
  final bool isDark;
  final VoidCallback onStartCooking;

  const _RecipeDetailModal({
    required this.recipe,
    required this.pantryItems,
    required this.isDark,
    required this.onStartCooking,
  });

  @override
  Widget build(BuildContext context) {
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

                  RecipeNutritionPanel(recipe: recipe, isDark: isDark),
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
                    onPressed: onStartCooking,
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
  final IconData icon;
  final String label;

  const _RecipeMetaChip({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: Colors.white),
          const SizedBox(width: 4),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Interactive Pantry Storage Zones Grid ─────────────────────────────────────

class _PantryZonesGrid extends StatelessWidget {
  final bool isDark;

  const _PantryZonesGrid({required this.isDark});

  @override
  Widget build(BuildContext context) {
    final pantry = context.watch<PantryProvider>();

    final zones = [
      _ZoneCardData(
        title: 'Fridge',
        count: pantry.itemsByZone['Fridge']?.length ?? 0,
        subtitle: 'Chilled • 3.2°C',
        color: AppTheme.zoneFridge,
        icon: Icons.kitchen_rounded,
      ),
      _ZoneCardData(
        title: 'Freezer',
        count: pantry.itemsByZone['Freezer']?.length ?? 0,
        subtitle: 'Deep Freeze • -18°C',
        color: AppTheme.zoneFreezer,
        icon: Icons.ac_unit_rounded,
      ),
      _ZoneCardData(
        title: 'Pantry Shelf',
        count: pantry.itemsByZone['Pantry Shelf']?.length ?? 0,
        subtitle: 'Grains & Staples',
        color: AppTheme.zonePantry,
        icon: Icons.shelves,
      ),
      _ZoneCardData(
        title: 'Spice Rack',
        count: pantry.itemsByZone['Spice Rack']?.length ?? 0,
        subtitle: 'Seasonings & Herbs',
        color: AppTheme.zoneSpice,
        icon: Icons.grass_rounded,
      ),
    ];

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollMarqueePhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        childAspectRatio: 1.45,
      ),
      itemCount: zones.length,
      itemBuilder: (ctx, i) {
        final zone = zones[i];
        return GestureDetector(
          onTap: () {
            context.findAncestorStateOfType<_MainShellState>()?.switchToTab(
              1,
              zoneFilter: zone.title,
            );
          },
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: isDark ? 0.35 : 0.05),
                  blurRadius: 10,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(18),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Image.asset(
                    'assets/images/pantry_basket.jpg',
                    fit: BoxFit.cover,
                  ),
                  DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.black.withValues(alpha: 0.35),
                          Colors.black.withValues(alpha: 0.82),
                        ],
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Container(
                              padding: const EdgeInsets.all(6),
                              decoration: BoxDecoration(
                                color: zone.color.withValues(alpha: 0.25),
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: zone.color.withValues(alpha: 0.5),
                                ),
                              ),
                              child: Icon(
                                zone.icon,
                                color: Colors.white,
                                size: 14,
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 7,
                                vertical: 3,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.2),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Text(
                                '${zone.count} ${zone.count == 1 ? 'item' : 'items'}',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const Spacer(),
                        Text(
                          zone.title,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.2,
                          ),
                        ),
                        Text(
                          zone.subtitle,
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.75),
                            fontSize: 10,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class NeverScrollableScrollMarqueePhysics extends ScrollPhysics {
  const NeverScrollableScrollMarqueePhysics({super.parent});
  @override
  NeverScrollableScrollMarqueePhysics applyTo(ScrollPhysics? ancestor) =>
      NeverScrollableScrollMarqueePhysics(parent: buildParent(ancestor));
  @override
  bool shouldAcceptUserOffset(ScrollMetrics position) => false;
}

class _ZoneCardData {
  final String title;
  final int count;
  final String subtitle;
  final Color color;
  final IconData icon;

  _ZoneCardData({
    required this.title,
    required this.count,
    required this.subtitle,
    required this.color,
    required this.icon,
  });
}

// ── Receipt Scan Banner ───────────────────────────────────────────────────────

class _ReceiptScanBanner extends StatelessWidget {
  final bool isDark;
  final VoidCallback onScanTap;

  const _ReceiptScanBanner({required this.isDark, required this.onScanTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onScanTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isDark ? AppTheme.surfaceDark : AppTheme.creamSurface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isDark ? AppTheme.borderDark : AppTheme.creamBorder,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: isDark ? 0.3 : 0.04),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 54,
              height: 54,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                image: const DecorationImage(
                  image: AssetImage('assets/images/pantry_basket.jpg'),
                  fit: BoxFit.cover,
                ),
              ),
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  color: Colors.black.withValues(alpha: 0.35),
                ),
                child: const Icon(
                  Icons.document_scanner_rounded,
                  color: Colors.white,
                  size: 24,
                ),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        'Snap Grocery Receipt',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          color: isDark
                              ? AppTheme.textDarkPrimary
                              : AppTheme.textLightPrimary,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: AppTheme.freshHerb.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Text(
                          'AI OCR',
                          style: TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.w800,
                            color: AppTheme.freshHerb,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(
                    'Instantly add bought items to pantry in 1 tap',
                    style: TextStyle(
                      fontSize: 12,
                      color: isDark
                          ? AppTheme.textDarkSecondary
                          : AppTheme.textLightSecondary,
                    ),
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppTheme.primaryFlame.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.arrow_forward_ios_rounded,
                size: 14,
                color: AppTheme.primaryFlame,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Attention Items Horizontal Carousel ───────────────────────────────────────

class _AttentionItemsCarousel extends StatelessWidget {
  final bool isDark;

  const _AttentionItemsCarousel({required this.isDark});

  @override
  Widget build(BuildContext context) {
    final pantry = context.watch<PantryProvider>();
    final attentionItems = pantry.allItems.where((i) => i.isLowStock).toList();
    final displayItems = attentionItems.isNotEmpty
        ? attentionItems
        : pantry.allItems.take(3).toList();

    return SizedBox(
      height: 124,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: displayItems.length,
        separatorBuilder: (_, _) => const SizedBox(width: 12),
        itemBuilder: (ctx, i) {
          final item = displayItems[i];
          return Container(
            width: 176,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: isDark ? AppTheme.surfaceDark : AppTheme.creamSurface,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: item.isLowStock
                    ? AppTheme.warmSaffron.withValues(alpha: 0.4)
                    : (isDark ? AppTheme.borderDark : AppTheme.creamBorder),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: isDark ? 0.25 : 0.04),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Row(
              children: [
                // Item Image Thumbnail
                ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: Image.network(
                    item.displayImageUrl,
                    width: 48,
                    height: 48,
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => Container(
                      width: 48,
                      height: 48,
                      color: AppTheme.primaryFlame.withValues(alpha: 0.1),
                      child: const Icon(
                        Icons.restaurant,
                        color: AppTheme.primaryFlame,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        item.name,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: isDark
                              ? AppTheme.textDarkPrimary
                              : AppTheme.textLightPrimary,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${item.quantity} ${item.unit} in ${item.location}',
                        style: TextStyle(
                          fontSize: 11,
                          color: isDark
                              ? AppTheme.textDarkSecondary
                              : AppTheme.textLightSecondary,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: item.isLowStock
                              ? AppTheme.warmSaffron.withValues(alpha: 0.15)
                              : AppTheme.freshHerb.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          item.isLowStock ? 'Low Stock' : 'In Stock',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: item.isLowStock
                                ? AppTheme.warmSaffron
                                : AppTheme.freshHerb,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

// ── Recommended Meals Carousel ────────────────────────────────────────────────

class _RecommendedMealsCarousel extends StatelessWidget {
  final bool isDark;

  const _RecommendedMealsCarousel({required this.isDark});

  @override
  Widget build(BuildContext context) {
    final pantry = context.watch<PantryProvider>();
    final recipes = RecipeRecommendationService.getAllRecipes();

    return SizedBox(
      height: 195,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: recipes.length,
        separatorBuilder: (_, _) => const SizedBox(width: 14),
        itemBuilder: (ctx, i) {
          final recipe = recipes[i];
          final matchPct = recipe.matchPercentage(pantry.allItems);

          return GestureDetector(
            onTap: () {
              showModalBottomSheet(
                context: context,
                isScrollControlled: true,
                backgroundColor: Colors.transparent,
                builder: (modalCtx) => _RecipeDetailModal(
                  recipe: recipe,
                  pantryItems: pantry.allItems,
                  isDark: isDark,
                  onStartCooking: () {
                    Navigator.pop(modalCtx);
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => GuidedCookingScreen(recipe: recipe),
                      ),
                    );
                  },
                ),
              );
            },
            child: Container(
              width: 220,
              decoration: BoxDecoration(
                color: isDark ? AppTheme.surfaceDark : AppTheme.creamSurface,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: isDark ? AppTheme.borderDark : AppTheme.creamBorder,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: isDark ? 0.3 : 0.05),
                    blurRadius: 10,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Stack(
                      children: [
                        Image.network(
                          recipe.imageUrl,
                          height: 110,
                          width: double.infinity,
                          fit: BoxFit.cover,
                          errorBuilder: (_, _, _) => Container(
                            height: 110,
                            color: isDark
                                ? AppTheme.cardDark
                                : AppTheme.creamBeige,
                          ),
                        ),
                        Positioned(
                          top: 8,
                          right: 8,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.72),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              '$matchPct% Match',
                              style: TextStyle(
                                color: matchPct >= 80
                                    ? const Color(0xFF6EE7B7)
                                    : AppTheme.warmSaffron,
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            recipe.title,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: isDark
                                  ? AppTheme.textDarkPrimary
                                  : AppTheme.textLightPrimary,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              Icon(
                                Icons.schedule,
                                size: 12,
                                color: isDark
                                    ? AppTheme.textDarkMuted
                                    : AppTheme.textLightMuted,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                '${recipe.cookTimeMinutes} min',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: isDark
                                      ? AppTheme.textDarkSecondary
                                      : AppTheme.textLightSecondary,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Icon(
                                Icons.local_fire_department,
                                size: 12,
                                color: isDark
                                    ? AppTheme.textDarkMuted
                                    : AppTheme.textLightMuted,
                              ),
                              const SizedBox(width: 4),
                              Expanded(
                                child: Text(
                                  '${recipe.calories} kcal',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: isDark
                                        ? AppTheme.textDarkSecondary
                                        : AppTheme.textLightSecondary,
                                  ),
                                ),
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
        },
      ),
    );
  }
}

// ── Placeholder Tabs (Recipes & Restock) ──────────────────────────────────────

class _RecipesPlaceholderTab extends StatelessWidget {
  const _RecipesPlaceholderTab();

  @override
  Widget build(BuildContext context) => const ChatbotScreen();
}

// ── Kitchen Navigation Drawer (Hamburger Slider) ─────────────────────────────

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
                    icon: Icons.restaurant_menu_rounded,
                    title: 'Recipes',
                    subtitle: 'Find something to cook',
                    isDark: isDark,
                    onTap: () {
                      Navigator.pop(context);
                      shell?.switchToTab(2);
                    },
                  ),
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
