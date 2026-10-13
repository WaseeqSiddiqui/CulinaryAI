import 'dart:convert';

import 'package:culinary_ai/providers/auth_provider.dart';
import 'package:culinary_ai/providers/pantry_provider.dart';
import 'package:culinary_ai/screens/chat/chatbot_screen.dart';
import 'package:culinary_ai/services/meal_planning_api_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Chef Chat renders live backend meal recommendations', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final pantry = PantryProvider()
      ..addItem(
        householdId: 'test-home',
        name: 'Basmati Rice',
        quantity: 1,
        unit: 'kg',
        location: 'Pantry Shelf',
      );
    final api = MealPlanningApiService(
      baseUrl: 'http://test.local',
      client: MockClient(
        (_) async => http.Response(
          jsonEncode({
            'meals': [
              {
                'recipe_id': 'rec_test',
                'name': 'Verified Rice Bowl',
                'cuisine': 'Pakistani',
                'cook_time_minutes': 20,
                'servings': 4,
                'pantry_match_percent': 80,
                'retrieval_score': 0.9,
                'ingredients_required': [
                  {'name': 'Basmati Rice', 'quantity': 300, 'unit': 'g'},
                ],
                'available_ingredients': ['Basmati Rice'],
                'missing_ingredients': [],
                'steps': [
                  {
                    'step_number': 1,
                    'instruction': 'Cook the rice.',
                    'timer_seconds': 600,
                  },
                ],
                'source': 'Test catalog',
              },
            ],
            'pantry_item_count': 1,
            'retrieval_method': 'test-retrieval',
          }),
          200,
        ),
      ),
    );

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: pantry),
          ChangeNotifierProvider(create: (_) => AuthProvider()),
        ],
        child: MaterialApp(home: ChatbotScreen(mealPlanningApi: api)),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('What can I cook?'));
    await tester.pump();
    await tester.pumpAndSettle();

    expect(find.text('Verified Rice Bowl'), findsOneWidget);
    expect(find.text('80% match'), findsOneWidget);
    expect(find.text('Cook this recipe'), findsOneWidget);
    expect(find.textContaining('Live backend'), findsOneWidget);
  });
}
