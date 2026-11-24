import 'dart:async';
import 'dart:convert';

import 'package:culinary_ai/core/theme/app_theme.dart';
import 'package:culinary_ai/models/dish_options.dart';
import 'package:culinary_ai/providers/pantry_provider.dart';
import 'package:culinary_ai/screens/recipes/dish_request_screen.dart';
import 'package:culinary_ai/services/dish_options_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

Map<String, dynamic> checkResponse({bool ready = false}) => {
  'dish': 'Rice bowl',
  'status': ready ? 'ready' : 'missing',
  'message': ready ? 'Your pantry covers this recipe.' : 'Rice is missing.',
  'quantities_note': 'Check the recipe portions.',
  'recipe': {
    'recipe_id': 'mealdb_1',
    'name': 'Rice bowl',
    'cuisine': 'Pakistani',
    'category': 'Rice',
    'source': 'TheMealDB',
    'image_url': '',
    'source_url': 'https://www.themealdb.com/meal.php?c=1',
    'pantry_match_percent': ready ? 100 : 0,
    'can_cook_now': ready,
    'ingredients': [
      {
        'name': 'Rice',
        'measure': '300g',
        'unit': 'g',
        'status': ready ? 'available' : 'missing',
      },
    ],
  },
};

Map<String, dynamic> menuResponse() => {
  'area': 'Lahore',
  'dish': 'Rice bowl',
  'message': 'Matching menus.',
  'availability_note': 'Check menu and delivery coverage.',
  'restaurants': [
    {
      'name': 'Menu House',
      'summary': 'Rice bowl menu in Lahore.',
      'source': 'Restaurant website',
      'link_type': 'order',
      'url': 'https://menuhouse.pk/order?branch=lahore',
    },
  ],
};

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('one malformed restaurant entry cannot break the other direct ordering links', () {
    final data = menuResponse();
    data['restaurants'] = <dynamic>[
      ...(data['restaurants'] as List),
      {'name': 'Bad', 'url': 42},
      {
        'name': 'Marketplace',
        'url': 'https://www.foodpanda.pk/restaurant/abc/menu-house',
      },
      null,
    ];
    final restaurants = RestaurantResults.fromJson(data).restaurants;
    expect(restaurants, hasLength(1));
    expect(
      restaurants.single.url.toString(),
      'https://menuhouse.pk/order?branch=lahore',
    );
  });

  test('restaurant details strip HTML and Markdown formatting', () {
    final restaurant = RestaurantOption.fromJson({
      'name': '**Menu House**',
      'url': 'https://menuhouse.pk/order',
      'summary':
          '<p>Rice &amp; curry</p>\\n[Order](https://menuhouse.pk/order)',
    });
    expect(restaurant.name, 'Menu House');
    expect(restaurant.summary, 'Rice & curry Order');
  });

  test(
    'explicit dish requests are separated from general pantry questions',
    () {
      expect(
        DishRequestIntent.extract('I want chicken biryani'),
        'chicken biryani',
      );
      expect(
        DishRequestIntent.extract('How do I cook tomato pasta?'),
        'tomato pasta',
      );
      expect(DishRequestIntent.extract('I want a recipe for pizza'), 'pizza');
      expect(DishRequestIntent.extract('chicken biryani'), 'chicken biryani');
      expect(DishRequestIntent.extract('mujhe biryani chahiye'), 'biryani');
      expect(DishRequestIntent.extract('What can I cook?'), isNull);
      expect(DishRequestIntent.extract('I want to check my pantry'), isNull);
      expect(DishRequestIntent.extract('I want a weekly plan'), isNull);
    },
  );

  test(
    'inconsistent readiness and unsupported restaurant links are rejected',
    () {
      final payload = checkResponse()..['status'] = 'ready';
      expect(DishOptions.fromJson(payload).status, 'check_quantities');
      for (final url in [
        'javascript:alert(1)',
        'https://www.foodpanda.pk.evil.test/restaurant/abc/menu-house',
        'https://www.foodpanda.pk/darkstore/abc/groceries',
      ]) {
        expect(
          () => RestaurantOption.fromJson({'name': 'bad', 'url': url}),
          throwsFormatException,
        );
      }
    },
  );

  Future<void> open(
    WidgetTester tester,
    MockClient client, {
    Size size = const Size(390, 844),
    double scale = 1,
    Future<bool> Function(Uri)? openMenu,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => PantryProvider(),
        child: MaterialApp(
          theme: AppTheme.lightTheme,
          builder: (_, child) => MediaQuery(
            data: MediaQueryData(
              size: size,
              textScaler: TextScaler.linear(scale),
            ),
            child: child!,
          ),
          home: DishRequestScreen(
            service: DishOptionsService(
              client: client,
              baseUrl: 'https://test.local',
            ),
            openMenu: openMenu,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).at(0), 'Rice bowl');
    await tester.enterText(find.byType(TextField).at(1), 'Lahore');
    tester.testTextInput.hide();
    await tester.pumpAndSettle();
  }

  Future<void> submit(WidgetTester tester) async {
    await tester.ensureVisible(find.text('Check my pantry'));
    await tester.tap(find.text('Check my pantry'));
    await tester.pumpAndSettle();
  }

  testWidgets('ready ingredients do not trigger restaurant search', (
    tester,
  ) async {
    final requests = <String>[];
    await open(
      tester,
      MockClient((request) async {
        requests.add(request.url.path);
        return http.Response(jsonEncode(checkResponse(ready: true)), 200);
      }),
    );
    await submit(tester);
    expect(requests, ['/dish-options']);
    expect(find.text('You can cook this recipe'), findsOneWidget);
    expect(find.text('Find restaurants'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  for (final config in [
    (const Size(390, 844), 1.0),
    (const Size(320, 740), 1.3),
  ]) {
    testWidgets(
      'missing food opens real menu links at ${config.$1.width} scale ${config.$2}',
      (tester) async {
        final requests = <http.Request>[];
        Uri? opened;
        await open(
          tester,
          MockClient((request) async {
            requests.add(request);
            return http.Response(
              jsonEncode(
                request.url.path == '/dish-options'
                    ? checkResponse()
                    : menuResponse(),
              ),
              200,
            );
          }),
          size: config.$1,
          scale: config.$2,
          openMenu: (uri) async {
            opened = uri;
            return true;
          },
        );
        await submit(tester);
        expect(requests.map((r) => r.url.path), [
          '/dish-options',
          '/nearby-restaurants',
        ]);
        final searchBody = jsonDecode(requests.last.body) as Map;
        expect(searchBody.keys.toSet(), {'dish', 'area'});
        expect(find.text('Need: Rice'), findsOneWidget);
        final order = find.text('Order on restaurant website');
        await tester.scrollUntilVisible(
          order,
          220,
          scrollable: find.byType(Scrollable).first,
        );
        await Scrollable.ensureVisible(tester.element(order), alignment: 0.5);
        await tester.pumpAndSettle();
        expect(order.hitTestable(), findsOneWidget);
        await tester.tap(order);
        await tester.pumpAndSettle();
        expect(opened?.host, 'menuhouse.pk');
        expect(opened?.queryParameters['branch'], 'lahore');
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('search outage preserves the ingredient check and offers retry', (
    tester,
  ) async {
    await open(
      tester,
      MockClient(
        (request) async => request.url.path == '/dish-options'
            ? http.Response(jsonEncode(checkResponse()), 200)
            : http.Response(
                jsonEncode({'detail': 'Restaurant search is unavailable.'}),
                503,
              ),
      ),
    );
    await submit(tester);
    expect(find.text('Need: Rice'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Restaurant search is unavailable.'),
      220,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Restaurant search is unavailable.'), findsOneWidget);
    expect(find.text('Find restaurants'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('editing the area cannot apply a previous area response', (
    tester,
  ) async {
    final deferred = Completer<http.Response>();
    await open(
      tester,
      MockClient(
        (request) async => request.url.path == '/dish-options'
            ? http.Response(jsonEncode(checkResponse()), 200)
            : deferred.future,
      ),
    );
    await tester.tap(find.text('Check my pantry'));
    await tester.pump();
    await tester.pump();
    await tester.enterText(find.byType(TextField).at(1), 'Karachi');
    deferred.complete(http.Response(jsonEncode(menuResponse()), 200));
    await tester.pumpAndSettle();
    expect(find.text('Menu House'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('changed pantry invalidates the previous cooking result', (
    tester,
  ) async {
    await open(
      tester,
      MockClient(
        (_) async => http.Response(jsonEncode(checkResponse(ready: true)), 200),
      ),
    );
    await submit(tester);
    tester
        .element(find.byType(DishRequestScreen))
        .read<PantryProvider>()
        .addItem(
          householdId: 'test',
          name: 'Rice',
          quantity: 1,
          unit: 'kg',
          location: 'Pantry Shelf',
        );
    await tester.pumpAndSettle();
    expect(
      find.text('Your pantry has changed. Check again to update the result.'),
      findsOneWidget,
    );
    expect(find.text('You can cook this recipe'), findsNothing);
  });
}
