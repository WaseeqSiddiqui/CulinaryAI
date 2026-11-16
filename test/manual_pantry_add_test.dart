import 'package:culinary_ai/core/theme/app_theme.dart';
import 'package:culinary_ai/models/pantry_item_model.dart';
import 'package:culinary_ai/models/recipe_ingredient.dart';
import 'package:culinary_ai/providers/pantry_provider.dart';
import 'package:culinary_ai/screens/pantry/pantry_screen.dart';
import 'package:culinary_ai/services/food_image_service.dart';
import 'package:culinary_ai/services/pantry_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await (FontLoader('PlusJakartaSans')..addFont(
          rootBundle.load('assets/fonts/PlusJakartaSans-Variable.ttf'),
        ))
        .load();
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
  });
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<void> openEditor(
    WidgetTester tester, {
    PantryItemModel? item,
    Size size = const Size(390, 844),
    double textScale = 1,
  }) async {
    final pantry = PantryProvider()..bindHousehold('manual-pantry-test');
    addTearDown(pantry.dispose);
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: pantry,
        child: MaterialApp(
          theme: AppTheme.lightTheme,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(textScale)),
            child: child!,
          ),
          home: Builder(
            builder: (context) => Scaffold(
              body: FilledButton(
                onPressed: () =>
                    PantryScreen.showItemEditor(context, item: item),
                child: const Text('Open editor'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Open editor'));
    await tester.pumpAndSettle();
  }

  testWidgets(
    'every popular preset selects valid name, unit and storage fields',
    (tester) async {
      await openEditor(tester);
      final presetScroll = find.descendant(
        of: find.byKey(const Key('popular-pantry-ingredients')),
        matching: find.byType(Scrollable),
      );
      for (final preset in FoodImageService.popularPresets) {
        final chip = find.byKey(ValueKey('pantry-preset-${preset['name']}'));
        await tester.scrollUntilVisible(chip, 100, scrollable: presetScroll);
        await tester.tap(chip);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: preset['name']);
        final fields = tester.widgetList<TextFormField>(
          find.byType(TextFormField),
        );
        expect(fields.first.controller!.text, preset['name']);
        final dropdowns = tester
            .stateList<FormFieldState<String>>(
              find.byType(DropdownButtonFormField<String>),
            )
            .toList();
        expect(dropdowns.first.value, preset['unit']);
        expect(dropdowns.last.value, preset['location']);
      }
    },
  );

  testWidgets('popular presets fit a small phone with larger text', (
    tester,
  ) async {
    await openEditor(tester, size: const Size(320, 740), textScale: 1.3);
    final presetScroll = find.descendant(
      of: find.byKey(const Key('popular-pantry-ingredients')),
      matching: find.byType(Scrollable),
    );
    for (final preset in FoodImageService.popularPresets) {
      final chip = find.byKey(ValueKey('pantry-preset-${preset['name']}'));
      await tester.scrollUntilVisible(chip, 100, scrollable: presetScroll);
      await tester.tap(chip);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: preset['name']);
    }
  });

  testWidgets('existing container units can be opened for editing', (
    tester,
  ) async {
    await openEditor(
      tester,
      item: PantryItemModel(
        id: 'stored-bottle',
        householdId: 'manual-pantry-test',
        name: 'Olive Oil',
        quantity: 1,
        unit: 'bottle',
        location: 'Pantry Shelf',
        updatedAt: DateTime.now(),
      ),
    );
    expect(tester.takeException(), isNull);
    final unit = tester.state<FormFieldState<String>>(
      find.byType(DropdownButtonFormField<String>).first,
    );
    expect(unit.value, 'bottle');
  });

  test(
    'manual milk additions keep both entries and total 4 litres after reload',
    () async {
      const scope = 'milk-addition-test';
      final pantry = PantryProvider()..bindHousehold(scope);
      addTearDown(pantry.dispose);
      for (var i = 0; i < 20 && !pantry.hasLoaded; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 1));
      }
      for (final quantity in [1.0, 3.0]) {
        pantry.addItem(
          householdId: scope,
          name: 'Milk',
          quantity: quantity,
          unit: 'L',
          location: 'Fridge',
        );
      }
      expect(pantry.allItems.map((item) => item.quantity), [1.0, 3.0]);
      expect(pantry.allItems.map((item) => item.id).toSet(), hasLength(2));
      expect(
        pantry
            .previewConsumption(const [
              RecipeIngredient(name: 'Milk', quantity: 4, unit: 'L'),
            ])
            .single
            .availableInRecipeUnit,
        4,
      );
      await Future<void>.delayed(Duration.zero);
      final reloaded = await PantryService().loadLocal(scope);
      expect(reloaded, hasLength(2));
      expect(reloaded.fold<double>(0, (sum, item) => sum + item.quantity), 4);
    },
  );
}
