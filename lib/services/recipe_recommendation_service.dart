import '../models/pantry_item_model.dart';
import '../models/recipe_ingredient.dart';
import '../models/recipe_recommendation_model.dart';

/// Intelligent Culinary Recommendation Service.
/// Determines the daily Hero Recipe and recommended meals on the basis of:
/// 1. Current Pantry Inventory overlap (100% matches prioritized)
/// 2. Daily Rotation Seed (Changes automatically day-to-day using calendar day)
/// 3. Perishability / Expiry Urgency weighting (zero-waste pantry optimization)
/// 4. User on-demand cycle / shuffle index
class RecipeRecommendationService {
  RecipeRecommendationService._();

  static const List<RecipeRecommendationModel> catalog = [
    RecipeRecommendationModel(
      id: 'rec_chicken_skillet',
      title: 'Lemon Garlic Chicken Skillet with Basmati Rice',
      subtitle: 'Crispy golden chicken pan-seared with fragrant aromatics and citrus rice.',
      imageUrl: 'https://images.unsplash.com/photo-1598515214211-89d3c73ae83b?w=800&q=80',
      cookTimeMinutes: 25,
      calories: 480,
      difficulty: 'Easy',
      mealType: 'Dinner',
      servings: 4,
      ingredientDetails: [
        RecipeIngredient(name: 'Chicken', quantity: 500, unit: 'g'),
        RecipeIngredient(name: 'Garlic', quantity: 4, unit: 'cloves'),
        RecipeIngredient(name: 'Rice', quantity: 300, unit: 'g'),
        RecipeIngredient(name: 'Olive Oil', quantity: 30, unit: 'ml'),
      ],
      instructions: [
        'Season chicken breast with salt, pepper, and crushed garlic.',
        'Heat olive oil in a wide skillet over medium-high heat until shimmering.',
        'Sear chicken for 6-7 minutes per side until golden and cooked through.',
        'Squeeze fresh lemon over the pan and serve over warm fluffy basmati rice.',
      ],
    ),
    RecipeRecommendationModel(
      id: 'rec_tomato_pasta',
      title: 'Rustic San Marzano Tomato & Garlic Basil Pasta',
      subtitle: 'Al dente pasta tossed in rich slow-simmered garlic oil and vine tomatoes.',
      imageUrl: 'https://images.unsplash.com/photo-1551183053-bf91a1d81141?w=800&q=80',
      cookTimeMinutes: 20,
      calories: 420,
      difficulty: 'Easy',
      mealType: 'Dinner',
      servings: 4,
      ingredientDetails: [
        RecipeIngredient(name: 'Pasta', quantity: 400, unit: 'g'),
        RecipeIngredient(name: 'Tomato', quantity: 4, unit: 'pcs'),
        RecipeIngredient(name: 'Garlic', quantity: 4, unit: 'cloves'),
        RecipeIngredient(name: 'Olive Oil', quantity: 30, unit: 'ml'),
        RecipeIngredient(name: 'Cheese', quantity: 80, unit: 'g'),
      ],
      instructions: [
        'Boil pasta in salted water until perfectly al dente.',
        'In a heavy skillet, gently saute minced garlic in extra virgin olive oil.',
        'Add chopped ripe tomatoes and simmer until sweet and thickened.',
        'Toss pasta into sauce, sprinkle generous cheese and torn basil leaves.',
      ],
    ),
    RecipeRecommendationModel(
      id: 'rec_farmhouse_frittata',
      title: 'Farmhouse Cheddar & Fresh Herb Frittata',
      subtitle: 'Fluffy organic eggs whisked with dairy cream, caramelized onions, and aged cheese.',
      imageUrl: 'https://images.unsplash.com/photo-1525351484163-7529414344d8?w=800&q=80',
      cookTimeMinutes: 18,
      calories: 360,
      difficulty: 'Quick',
      mealType: 'Breakfast / Brunch',
      servings: 4,
      ingredientDetails: [
        RecipeIngredient(name: 'Egg', quantity: 6, unit: 'pcs'),
        RecipeIngredient(name: 'Milk', quantity: 120, unit: 'ml'),
        RecipeIngredient(name: 'Cheese', quantity: 100, unit: 'g'),
        RecipeIngredient(name: 'Onion', quantity: 1, unit: 'pcs'),
      ],
      instructions: [
        'Whisk farm eggs with milk, salt, pepper, and chopped fresh herbs.',
        'Saute sliced onions in butter until tender and sweet.',
        'Pour egg mixture over the pan and top with grated cheddar.',
        'Cook on low until edges set, then broil 2 minutes until puffy and golden.',
      ],
    ),
    RecipeRecommendationModel(
      id: 'rec_spiced_lentils',
      title: 'Golden Cumin & Turmeric Spiced Dal with Steamed Rice',
      subtitle: 'Comforting simmered yellow lentils tempered with blooming cumin seeds and garlic.',
      imageUrl: 'https://images.unsplash.com/photo-1546833999-b9f581a1996d?w=800&q=80',
      cookTimeMinutes: 30,
      calories: 390,
      difficulty: 'Easy',
      mealType: 'Dinner',
      servings: 4,
      ingredientDetails: [
        RecipeIngredient(name: 'Lentils', quantity: 300, unit: 'g'),
        RecipeIngredient(name: 'Rice', quantity: 300, unit: 'g'),
        RecipeIngredient(name: 'Cumin', quantity: 2, unit: 'tsp'),
        RecipeIngredient(name: 'Garlic', quantity: 4, unit: 'cloves'),
        RecipeIngredient(name: 'Onion', quantity: 1, unit: 'pcs'),
        RecipeIngredient(name: 'Olive Oil', quantity: 30, unit: 'ml'),
      ],
      instructions: [
        'Rinse and simmer yellow lentils until completely tender.',
        'In a separate tadka pan, bloom cumin seeds and garlic in hot oil.',
        'Pour aromatic oil over the simmering dal and stir vigorously.',
        'Serve hot alongside steamed basmati rice and fresh lime wedges.',
      ],
    ),
    RecipeRecommendationModel(
      id: 'rec_pan_salmon',
      title: 'Crispy Skin Atlantic Salmon with Garlic Greens',
      subtitle: 'Tender flaky salmon fillet pan-crisped with garlic-tossed garden greens.',
      imageUrl: 'https://images.unsplash.com/photo-1519708227418-c8fd9a32b7a2?w=800&q=80',
      cookTimeMinutes: 20,
      calories: 520,
      difficulty: 'Medium',
      mealType: 'Dinner',
      servings: 4,
      ingredientDetails: [
        RecipeIngredient(name: 'Fish', quantity: 600, unit: 'g'),
        RecipeIngredient(name: 'Garlic', quantity: 3, unit: 'cloves'),
        RecipeIngredient(name: 'Olive Oil', quantity: 25, unit: 'ml'),
        RecipeIngredient(name: 'Peas', quantity: 300, unit: 'g'),
      ],
      instructions: [
        'Pat salmon skin dry and season generously with sea salt.',
        'Place skin-down in a hot oiled skillet and press gently for 5 minutes.',
        'Flip once and cook for 2 more minutes until translucent pink inside.',
        'Saute peas and garlic in the residual pan juices and plate together.',
      ],
    ),
    RecipeRecommendationModel(
      id: 'rec_avocado_toast',
      title: 'Artisan Sourdough Toast with Poached Egg',
      subtitle: 'Rustic toasted sourdough topped with creamy mashed avocado and a rich soft egg.',
      imageUrl: 'https://images.unsplash.com/photo-1525351484163-7529414344d8?w=800&q=80',
      cookTimeMinutes: 12,
      calories: 340,
      difficulty: 'Quick',
      mealType: 'Breakfast',
      servings: 4,
      ingredientDetails: [
        RecipeIngredient(name: 'Bread', quantity: 4, unit: 'pcs'),
        RecipeIngredient(name: 'Egg', quantity: 4, unit: 'pcs'),
        RecipeIngredient(name: 'Olive Oil', quantity: 15, unit: 'ml'),
      ],
      instructions: [
        'Toast thick slices of artisan sourdough until deeply crunchy.',
        'Fry or soft-poach eggs in simmering water with a drop of vinegar.',
        'Drizzle toast with olive oil, flake sea salt, and top with warm egg.',
      ],
    ),
    RecipeRecommendationModel(
      id: 'rec_parmesan_risotto',
      title: 'Creamy Garlic & Parmesan Rice Skillet',
      subtitle: 'Velvety slow-stirred rice enriched with cultured butter and aged parmesan.',
      imageUrl: 'https://images.unsplash.com/photo-1633964913295-ceb43826e7c9?w=800&q=80',
      cookTimeMinutes: 28,
      calories: 460,
      difficulty: 'Medium',
      mealType: 'Dinner',
      servings: 4,
      ingredientDetails: [
        RecipeIngredient(name: 'Rice', quantity: 320, unit: 'g'),
        RecipeIngredient(name: 'Cheese', quantity: 100, unit: 'g'),
        RecipeIngredient(name: 'Butter', quantity: 40, unit: 'g'),
        RecipeIngredient(name: 'Garlic', quantity: 4, unit: 'cloves'),
      ],
      instructions: [
        'Saute garlic and rice in melted butter until grains become translucent.',
        'Add hot broth gradually, stirring until liquid is absorbed before adding more.',
        'Finish with extra butter and folded aged parmesan cheese until glossy.',
      ],
    ),
  ];

  /// Dynamically computes the #1 Hero Recommendation based on:
  /// 1. Highest pantry match percentage
  /// 2. Day-of-month rotation seed (ensures tomorrow naturally features a fresh meal)
  /// 3. User cycle / shuffle index
  static RecipeRecommendationModel getHeroRecommendation(
    List<PantryItemModel> pantryItems, {
    int cycleOffset = 0,
  }) {
    if (catalog.isEmpty) {
      throw StateError('Catalog cannot be empty');
    }

    // Score all catalog recipes against active pantry inventory
    final scoredList = List<RecipeRecommendationModel>.from(catalog);
    scoredList.sort((a, b) {
      return _score(b, pantryItems).compareTo(_score(a, pantryItems));
    });

    // Identify top contenders (recipes with equal top score or >= 70%)
    final topScore = _score(scoredList.first, pantryItems);
    final topContenders = scoredList
        .where(
          (r) => _score(r, pantryItems) >= (topScore > 50 ? topScore - 25 : 0),
        )
        .toList();

    // Use calendar day + cycleOffset to deterministically rotate recipes day-to-day
    final todayDay = DateTime.now().day;
    final index = (todayDay + cycleOffset) % topContenders.length;
    return topContenders[index];
  }

  /// Returns recommended recipes ordered by match score
  static List<RecipeRecommendationModel> getRecommendedList(
    List<PantryItemModel> pantryItems, {
    int? targetCaloriesPerMeal,
    bool pantryFirst = true,
  }) {
    final usablePantry = pantryItems
        .where(
          (item) =>
              item.quantity > 0 && item.expiryStatus != ExpiryStatus.expired,
        )
        .toList();
    var list = List<RecipeRecommendationModel>.from(catalog);
    if (pantryFirst && usablePantry.isNotEmpty) {
      list = list
          .where((recipe) => recipe.matchedCount(usablePantry) > 0)
          .toList();
    }
    list.sort((a, b) {
      final scoreA = _score(
        a,
        usablePantry,
        targetCaloriesPerMeal: targetCaloriesPerMeal,
      );
      final scoreB = _score(
        b,
        usablePantry,
        targetCaloriesPerMeal: targetCaloriesPerMeal,
      );
      return scoreB.compareTo(scoreA);
    });
    return list;
  }

  /// Returns all recipes available in the catalog
  static List<RecipeRecommendationModel> getAllRecipes() => catalog;

  /// Pantry match remains dominant; each soon-to-expire ingredient adds a
  /// zero-waste boost. Expired food is excluded by the recipe model.
  static double _score(
    RecipeRecommendationModel recipe,
    List<PantryItemModel> pantryItems, {
    int? targetCaloriesPerMeal,
  }) {
    var urgency = 0;
    for (final required in recipe.requiredIngredients) {
      final wanted = required.toLowerCase();
      final match = pantryItems.where((item) {
        final available = item.name.toLowerCase();
        return item.expiryStatus == ExpiryStatus.useSoon &&
            (available.contains(wanted) || wanted.contains(available));
      });
      if (match.isNotEmpty) urgency += 12;
    }
    var calorieFit = 0.0;
    if (targetCaloriesPerMeal != null && targetCaloriesPerMeal > 0) {
      final difference = (recipe.calories - targetCaloriesPerMeal).abs();
      calorieFit =
          (1 - difference / targetCaloriesPerMeal).clamp(0.0, 1.0) * 20;
    }
    return recipe.matchPercentage(pantryItems) + urgency + calorieFit;
  }
}
