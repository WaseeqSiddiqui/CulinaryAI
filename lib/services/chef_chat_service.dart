import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;

import '../models/pantry_item_model.dart';
import '../models/recipe_recommendation_model.dart';
import 'recipe_recommendation_service.dart';
import 'server_config_service.dart';

class ChefChatService {
  ChefChatService._();

  static bool isMealPlanningQuestion(String question) {
    final query = question.trim().toLowerCase();
    return _containsAny(query, [
      'what can i cook',
      'recommend',
      'suggest',
      'meal idea',
      'dinner idea',
      'lunch idea',
      'breakfast idea',
      'i am hungry',
      "i'm hungry",
    ]);
  }

  static Future<({String reply, bool isLiveAi})> askChefApi(
    String question,
    List<PantryItemModel> pantryItems, {
    http.Client? client,
  }) async {
    final httpClient = client ?? http.Client();
    final baseUrl = ServerConfigService.currentBaseUrl;
    final uri = Uri.parse('$baseUrl/chef-chat');

    try {
      final body = jsonEncode({
        'message': question.trim(),
        'pantry_items': [
          for (final item in pantryItems)
            {'name': item.name, 'quantity': item.quantity, 'unit': item.unit},
        ],
      });

      final res = await httpClient
          .post(
            uri,
            headers: {'Content-Type': 'application/json'},
            body: body,
          )
          .timeout(const Duration(seconds: 8));

      if (res.statusCode >= 200 && res.statusCode < 300) {
        final decoded = jsonDecode(res.body);
        if (decoded is Map && decoded['reply'] is String) {
          final replyText = (decoded['reply'] as String).trim();
          if (replyText.isNotEmpty) {
            return (reply: replyText, isLiveAi: true);
          }
        }
      }
    } catch (_) {
      // Fallback to offline rule-based chef
    } finally {
      if (client == null) httpClient.close();
    }

    return (reply: answer(question, pantryItems), isLiveAi: false);
  }

  static String answer(String question, List<PantryItemModel> pantryItems) {
    final cleanQuestion = question.trim();
    final query = cleanQuestion.toLowerCase();
    if (query.isEmpty) {
      return 'Ask me about your pantry, recipe ideas, missing ingredients, cooking time, or cooking steps.';
    }

    final greetings = [
      'hello',
      'hi',
      'hey',
      'salam',
      'assalam',
      'good morning',
      'good afternoon',
      'good evening',
    ];
    if (greetings.any(
      (g) => query == g || query.startsWith('$g ') || query.startsWith('$g!'),
    )) {
      return 'Hello Chef! I can check your pantry inventory, suggest recipes, calculate calories, or guide you through cooking. What are you looking to cook today?';
    }

    if (_containsAny(query, ['low stock', 'running out', 'need to buy'])) {
      final lowStock = pantryItems.where((item) => item.isLowStock).toList();
      if (lowStock.isEmpty) {
        return 'Nothing is marked low-stock right now. Your pantry looks ready.';
      }
      return 'These items are running low: ${_joinNames(lowStock.map((item) => item.name).toList())}.';
    }

    if (_containsAny(query, [
      'what do i have',
      'in my pantry',
      'list pantry',
    ])) {
      if (pantryItems.isEmpty) {
        return 'Your pantry is empty right now. Add a few ingredients or scan a receipt and I can recommend matching meals.';
      }
      final names = pantryItems.map((item) => item.name).toList()..sort();
      return 'You currently have ${_joinNames(names)}.';
    }

    if (_containsAny(query, ['substitute', 'replace'])) {
      return 'Common kitchen substitutes:\n• Heavy Cream: Whole milk + butter (or plain Greek yogurt)\n• Olive Oil: Canola, vegetable, or coconut oil\n• Eggs (baking): Applesauce or mashed banana\n• Lemon Juice: Vinegar or lime juice';
    }

    if (_containsAny(query, ['help', 'who are you', 'what can you do', 'features'])) {
      return 'I am Chef CulinaryAI, your smart kitchen assistant! Here is what I can do:\n• Scan grocery receipts and fridge shelves to manage stock\n• Recommend recipes based on what ingredients you actually have\n• Alert you when ingredients are running low\n• Guide you step-by-step through interactive cooking';
    }

    final recipe = _findRecipe(query);

    if (_containsAny(query, ['how do i', 'how to', 'steps', 'instructions'])) {
      if (recipe == null) {
        return 'Tell me the recipe name too, for example: “How do I cook tomato pasta?”';
      }
      final steps = <String>[
        for (var i = 0; i < recipe.instructions.length; i++)
          '${i + 1}. ${recipe.instructions[i]}',
      ];
      return 'Here is how to make ${recipe.title}:\n${steps.join('\n')}';
    }

    if (_containsAny(query, ['calorie', 'nutrition'])) {
      if (recipe == null) {
        return 'Mention a recipe name and I’ll tell you its estimated calories.';
      }
      return '${recipe.title} is approximately ${recipe.calories} kcal per serving in the current recipe.';
    }

    if (_containsAny(query, ['how long', 'cook time', 'time does'])) {
      if (recipe == null) {
        return 'Mention a recipe name and I’ll check its cooking time.';
      }
      return '${recipe.title} takes about ${recipe.cookTimeMinutes} minutes and is marked ${recipe.difficulty.toLowerCase()}.';
    }

    if (_containsAny(query, ['missing', 'need for', 'ingredients for'])) {
      if (recipe == null) {
        return 'Which recipe should I check? Try “What is missing for tomato pasta?”';
      }
      final missing = recipe.missingIngredients(pantryItems);
      if (missing.isEmpty) {
        return 'You have every tracked ingredient needed for ${recipe.title}.';
      }
      return 'For ${recipe.title}, you still need ${_joinNames(missing)}.';
    }

    if (_containsAny(query, ['do i have', 'is there any', 'have any'])) {
      final matchingItem = pantryItems.where((item) {
        final name = item.name.toLowerCase();
        return query.contains(name) || name.split(' ').any(query.contains);
      }).firstOrNull;
      if (matchingItem != null) {
        return 'Yes, you have ${matchingItem.quantity} ${matchingItem.unit} of ${matchingItem.name} in ${matchingItem.location}.';
      }
      return 'I could not find that ingredient in your pantry.';
    }

    if (recipe != null) {
      final match = recipe.matchPercentage(pantryItems);
      final missing = recipe.missingIngredients(pantryItems);
      final missingText = missing.isEmpty
          ? 'You already have all tracked ingredients.'
          : 'You would still need ${_joinNames(missing)}.';
      return '${recipe.title} is a $match% pantry match and takes ${recipe.cookTimeMinutes} minutes. $missingText';
    }

    if (_containsAny(query, [
      'cook',
      'recipe',
      'meal',
      'dinner',
      'breakfast',
      'hungry',
      'recommend',
      'suggest',
    ])) {
      if (pantryItems.isEmpty) {
        return 'Your kitchen pantry is currently empty! You can scan a grocery receipt or scan your fridge to stock it in seconds.\n\nIn the meantime, here are popular dishes you can explore:\n• Lemon Garlic Chicken Skillet with Rice (25 min)\n• Rustic San Marzano Tomato & Basil Pasta (20 min)\n• Farmhouse Cheddar & Herb Frittata (18 min)';
      }
      final suggestions = RecipeRecommendationService.getRecommendedList(
        pantryItems,
      ).take(3).toList();
      final lines = suggestions
          .map(
            (item) =>
                '• ${item.title} — ${item.matchPercentage(pantryItems)}% match, ${item.cookTimeMinutes} min',
          )
          .join('\n');
      return 'Based on your pantry, I recommend:\n$lines';
    }

    return 'I can answer questions about your pantry and the available recipes. Try “What can I cook?”, “What is low stock?”, or “How do I cook tomato pasta?”';
  }

  static RecipeRecommendationModel? _findRecipe(String query) {
    RecipeRecommendationModel? best;
    var bestScore = 0;
    const ignored = {
      'with',
      'from',
      'this',
      'that',
      'what',
      'cook',
      'recipe',
      'ingredients',
    };

    for (final recipe in RecipeRecommendationService.catalog) {
      final searchable = <String>[
        recipe.title,
        recipe.mealType,
        ...recipe.requiredIngredients,
      ].join(' ').toLowerCase();
      final tokens = searchable
          .split(RegExp(r'[^a-z0-9]+'))
          .where((token) => token.length >= 4 && !ignored.contains(token))
          .toSet();
      final score = tokens.where(query.contains).length;
      if (score > bestScore) {
        best = recipe;
        bestScore = score;
      }
    }
    return best;
  }

  static bool _containsAny(String value, List<String> terms) =>
      terms.any(value.contains);

  static String _joinNames(List<String> values) {
    if (values.isEmpty) return '';
    if (values.length == 1) return values.first;
    if (values.length == 2) return '${values.first} and ${values.last}';
    return '${values.take(values.length - 1).join(', ')}, and ${values.last}';
  }
}
