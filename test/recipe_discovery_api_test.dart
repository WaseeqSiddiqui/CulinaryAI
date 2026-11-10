import 'dart:convert';

import 'package:culinary_ai/models/pantry_item_model.dart';
import 'package:culinary_ai/models/recipe_discovery.dart';
import 'package:culinary_ai/services/chef_chat_service.dart';
import 'package:culinary_ai/services/meal_planning_api_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'fixtures/recipe_discovery_fixture.dart';

void main() {
  test(
    'live discovery sends pantry quantities, expiry and local planning date',
    () async {
      late Map<String, dynamic> body;
      late Uri url;
      final service = MealPlanningApiService(
        baseUrl: 'https://example.test',
        client: MockClient((request) async {
          url = request.url;
          body = jsonDecode(request.body) as Map<String, dynamic>;
          return http.Response(jsonEncode(liveRecipeFixture()), 200);
        }),
      );
      final result = await service.discoverRecipes(
        question: 'What can I cook tomorrow?',
        pantryItems: [
          PantryItemModel(
            id: 'rice',
            householdId: 'home',
            name: 'Rice',
            quantity: 1,
            unit: 'kg',
            location: 'Pantry Shelf',
            updatedAt: DateTime(2026, 10, 30),
            expiryDate: DateTime(2026, 10, 31),
          ),
        ],
        referenceDate: DateTime(2026, 10, 30, 23, 50),
        dietaryPreferences: ['Vegetarian'],
        avoidIngredients: ['Peanuts'],
      );
      expect(url.path, '/discover-recipes');
      expect(body['reference_date'], '2026-10-30');
      expect(body['dietary_preferences'], ['vegetarian']);
      expect(body['avoid_ingredients'], ['Peanuts']);
      expect((body['pantry_items'] as List).single, {
        'name': 'Rice',
        'quantity': 1.0,
        'unit': 'kg',
        'expiry_date': '2026-10-31',
      });
      expect(result.recipes.single.sourceUrl.host, 'www.themealdb.com');
      expect(result.recipes.single.canCookNow, isTrue);
    },
  );

  for (final status in [404, 429, 503]) {
    test(
      'HTTP $status exposes failure without an offline recipe fallback',
      () async {
        final service = MealPlanningApiService(
          baseUrl: 'https://example.test',
          client: MockClient(
            (_) async => http.Response(
              jsonEncode({'detail': 'Recipe website unavailable'}),
              status,
            ),
          ),
        );
        await expectLater(
          service.discoverRecipes(
            question: 'What can I cook?',
            pantryItems: [],
          ),
          throwsA(isA<MealPlanningApiException>()),
        );
      },
    );
  }

  test('inconsistent quantities cannot claim a recipe is ready', () {
    final raw =
        (liveRecipeFixture()['meals'] as List).single as Map<String, dynamic>;
    (raw['ingredients'] as List).first['status'] = 'insufficient';
    expect(DiscoveredRecipe.fromJson(raw).canCookNow, isFalse);
  });

  test('unsafe source links are rejected', () {
    final raw =
        (liveRecipeFixture()['meals'] as List).single as Map<String, dynamic>;
    raw['source_url'] = 'javascript:alert(1)';
    expect(() => DiscoveredRecipe.fromJson(raw), throwsFormatException);
  });

  test('natural recipe questions use live retrieval', () {
    for (final question in [
      'How do I cook tomato pasta?',
      'Give me a recipe for tonight',
      'Any dinner ideas for Friday?',
      'What can I cook tomorrow?',
    ]) {
      expect(
        ChefChatService.isMealPlanningQuestion(question),
        isTrue,
        reason: question,
      );
    }
    expect(
      ChefChatService.isMealPlanningQuestion('What do I have in my pantry?'),
      isFalse,
    );
    expect(
      ChefChatService.isMealPlanningQuestion('What is low stock?'),
      isFalse,
    );
  });
}
