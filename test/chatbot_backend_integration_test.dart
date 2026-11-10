import 'dart:convert';

import 'package:culinary_ai/core/theme/app_theme.dart';
import 'package:culinary_ai/providers/auth_provider.dart';
import 'package:culinary_ai/providers/pantry_provider.dart';
import 'package:culinary_ai/providers/recipe_experience_provider.dart';
import 'package:culinary_ai/screens/chat/chatbot_screen.dart';
import 'package:culinary_ai/services/meal_planning_api_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fixtures/recipe_discovery_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<PantryProvider> open(
    WidgetTester tester,
    MealPlanningApiService api, {
    bool small = false,
  }) async {
    if (small) {
      tester.view.physicalSize = const Size(320, 740);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
    }
    final pantry = PantryProvider()
      ..addItem(
        householdId: 'test-home',
        name: 'Basmati Rice',
        quantity: 1,
        unit: 'kg',
        location: 'Pantry Shelf',
      );
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: pantry),
          ChangeNotifierProvider(create: (_) => AuthProvider()),
          ChangeNotifierProvider(create: (_) => RecipeExperienceProvider()),
        ],
        child: MaterialApp(
          theme: AppTheme.lightTheme,
          home: ChatbotScreen(mealPlanningApi: api),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return pantry;
  }

  testWidgets(
    'Chef Chat searches live pantry recipes and renders source and quantities on a small phone',
    (tester) async {
      final requests = <Map<String, dynamic>>[];
      final api = MealPlanningApiService(
        baseUrl: 'https://test.local',
        client: MockClient((request) async {
          expect(request.url.path, '/discover-recipes');
          requests.add(jsonDecode(request.body) as Map<String, dynamic>);
          return http.Response(jsonEncode(liveRecipeFixture()), 200);
        }),
      );
      final pantry = await open(tester, api, small: true);
      await tester.tap(find.text('What can I cook?'));
      await tester.pumpAndSettle();
      expect(find.text('Live Rice Bowl'), findsOneWidget);
      expect(find.textContaining('Live recipe search'), findsOneWidget);
      final ingredients = find.text('Check 1 ingredient');
      await tester.scrollUntilVisible(
        ingredients,
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(ingredients);
      await tester.pumpAndSettle();
      expect(find.text('300g'), findsOneWidget);
      expect(find.text('In your pantry'), findsOneWidget);
      expect(find.textContaining('View recipe'), findsOneWidget);
      expect(tester.takeException(), isNull);
      pantry.addItem(
        householdId: 'test-home',
        name: 'Eggs',
        quantity: 6,
        unit: 'pcs',
        location: 'Fridge',
      );
      await tester.enterText(
        find.byType(TextField),
        'Give me a recipe for tomorrow',
      );
      await tester.testTextInput.receiveAction(TextInputAction.send);
      await tester.pumpAndSettle();
      expect(requests, hasLength(2));
      expect(
        (requests.last['pantry_items'] as List).any(
          (item) => item['name'] == 'Eggs',
        ),
        isTrue,
      );
    },
  );

  testWidgets('failed live recipe lookup does not silently return demo meals', (
    tester,
  ) async {
    final api = MealPlanningApiService(
      baseUrl: 'https://test.local',
      client: MockClient(
        (_) async => http.Response(
          jsonEncode({'detail': 'Recipe website unavailable. Please retry.'}),
          503,
        ),
      ),
    );
    await open(tester, api);
    await tester.tap(find.text('What can I cook?'));
    await tester.pumpAndSettle();
    expect(
      find.text('Recipe website unavailable. Please retry.'),
      findsOneWidget,
    );
    expect(
      find.textContaining('Live recipe search unavailable'),
      findsOneWidget,
    );
    expect(find.textContaining('Lemon Garlic Chicken'), findsNothing);
    expect(find.textContaining('View recipe'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
