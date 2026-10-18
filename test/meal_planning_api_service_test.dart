import 'dart:convert';

import 'package:culinary_ai/models/pantry_item_model.dart';
import 'package:culinary_ai/services/meal_planning_api_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  final pantry = [
    PantryItemModel(
      id: 'rice',
      householdId: 'home',
      name: 'Basmati Rice',
      quantity: 1,
      unit: 'kg',
      location: 'Pantry Shelf',
      updatedAt: DateTime(2026),
    ),
  ];

  test('sends pantry context and maps verified meal plans', () async {
    late Map<String, dynamic> requestBody;
    final client = MockClient((request) async {
      expect(request.url.toString(), 'http://localhost:8000/generate-plan');
      requestBody = jsonDecode(request.body) as Map<String, dynamic>;
      return http.Response(
        jsonEncode({
          'meals': [
            {
              'recipe_id': 'rec_rice',
              'name': 'Golden Rice Bowl',
              'cuisine': 'Pakistani',
              'cook_time_minutes': 25,
              'servings': 2,
              'pantry_match_percent': 75,
              'retrieval_score': 0.82,
              'ingredients_required': [
                {'name': 'Basmati Rice', 'quantity': 200, 'unit': 'g'},
              ],
              'available_ingredients': ['Basmati Rice'],
              'missing_ingredients': [],
              'steps': [
                {
                  'step_number': 1,
                  'instruction': 'Rinse the rice.',
                  'timer_seconds': 0,
                },
              ],
              'source': 'Verified test catalog',
            },
          ],
          'pantry_item_count': 1,
          'retrieval_method': 'test-vector-index',
        }),
        200,
        headers: {'content-type': 'application/json'},
      );
    });
    final service = MealPlanningApiService(
      client: client,
      baseUrl: 'http://localhost:8000',
    );

    final plan = await service.generatePlan(
      question: 'Suggest a quick dinner',
      pantryItems: pantry,
      servings: 2,
      dietaryPreferences: const ['Balanced', 'halal'],
      mealsPerDay: 4,
      targetCaloriesPerPersonPerDay: 1600,
      pantryFirst: true,
    );

    expect(requestBody['servings'], 2);
    expect(requestBody['question'], 'Suggest a quick dinner');
    expect(requestBody['dietary_preferences'], ['halal']);
    expect(requestBody['meals_per_day'], 4);
    expect(requestBody['target_calories_per_person_per_day'], 1600);
    expect(requestBody['pantry_first'], isTrue);
    expect(
      (requestBody['pantry_items'] as List).single['name'],
      'Basmati Rice',
    );
    expect(plan.retrievalMethod, 'test-vector-index');
    expect(plan.meals.single.recipe.title, 'Golden Rice Bowl');
    expect(plan.meals.single.pantryMatchPercent, 75);
    expect(plan.meals.single.recipe.instructions, ['Rinse the rice.']);
  });

  test('throws a readable exception for backend failures', () async {
    final service = MealPlanningApiService(
      client: MockClient((_) async => http.Response('unavailable', 503)),
      baseUrl: 'http://localhost:8000',
    );

    expect(
      () => service.generatePlan(pantryItems: pantry),
      throwsA(
        isA<MealPlanningApiException>().having(
          (error) => error.message,
          'message',
          contains('503'),
        ),
      ),
    );
  });
}
