import 'dart:io';
import 'dart:ui' as ui;

import 'package:culinary_ai/main.dart';
import 'package:culinary_ai/providers/theme_provider.dart';
import 'package:culinary_ai/providers/pantry_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await (FontLoader('PlusJakartaSans')..addFont(
          rootBundle.load('assets/fonts/PlusJakartaSans-Variable.ttf'),
        ))
        .load();
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
  });
  for (final config in <(String, Size, bool, double)>[
    ('phone', const Size(390, 844), false, 1),
    ('small_phone', const Size(320, 740), false, 1),
    ('desktop', const Size(1440, 1000), false, 1),
    ('dark_phone', const Size(390, 844), true, 1),
    ('tablet', const Size(768, 1024), false, 1),
    ('larger_text', const Size(390, 844), false, 1.3),
  ]) {
    testWidgets('core navigation fits ${config.$1}', (tester) async {
      SharedPreferences.setMockInitialValues({});
      tester.view.physicalSize = config.$2;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final boundaryKey = GlobalKey();
      await tester.pumpWidget(
        RepaintBoundary(
          key: boundaryKey,
          child: MediaQuery(
            data: MediaQueryData(
              size: config.$2,
              textScaler: TextScaler.linear(config.$4),
            ),
            child: const CulinaryAiApp(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.runAsync(() async {
        final context = tester.element(find.byType(Scaffold).first);
        await precacheImage(
          const AssetImage('assets/images/hero_dish.jpg'),
          context,
        );
        await precacheImage(
          const AssetImage('assets/images/pantry_basket.jpg'),
          context,
        );
      });
      if (config.$3) {
        tester
            .element(find.byType(Scaffold).first)
            .read<ThemeProvider>()
            .setThemeMode(ThemeMode.dark);
        await tester.pumpAndSettle();
      }
      Future<void> capture(String name) async {
        await tester.pump(const Duration(milliseconds: 300));
        const captureDirectory = String.fromEnvironment('UI_CAPTURE_DIR');
        if (captureDirectory.isEmpty) return;
        await tester.runAsync(() async {
          final boundary =
              boundaryKey.currentContext!.findRenderObject()!
                  as RenderRepaintBoundary;
          final img = await boundary.toImage(pixelRatio: 1);
          final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
          final file = File('$captureDirectory/${config.$1}_$name.png');
          await file.parent.create(recursive: true);
          await file.writeAsBytes(bytes!.buffer.asUint8List());
          img.dispose();
        });
      }

      expect(tester.takeException(), isNull);
      await capture('login');
      final demo = find.byKey(const Key('continueAsDemoButton'));
      await tester.ensureVisible(demo);
      await tester.tap(demo);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await capture('home');
      // The feature directory must lead to the real expiry editor, including
      // when pantry search/zone filters would otherwise hide an ingredient.
      await tester.tap(find.text('All features'));
      await tester.pumpAndSettle();
      await capture('features');
      await tester.enterText(find.byType(TextField), 'not-a-feature');
      await tester.pumpAndSettle();
      expect(find.textContaining('No matching feature.'), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'receipt');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Scan receipt'));
      await tester.pumpAndSettle();
      expect(find.text('Scan a receipt'), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'expiry');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Check expiry'));
      await tester.pumpAndSettle();
      await capture('expiry');
      final pantry = tester
          .element(find.text('Check expiry'))
          .read<PantryProvider>();
      final quantities = {
        for (final item in pantry.allItems) item.id: item.quantity,
      };
      final firstExpiryItem = find.byWidgetPredicate(
        (widget) =>
            widget is ListTile &&
            widget.key is ValueKey<String> &&
            (widget.key! as ValueKey<String>).value.startsWith('expiry-item-'),
      );
      await tester.tap(firstExpiryItem.first);
      await tester.pumpAndSettle();
      expect(
        find.text('Scan label').hitTestable(),
        findsOneWidget,
        reason:
            'Expiry actions must be visible without hunting through the form',
      );
      await capture('expiry_editor');
      Navigator.of(tester.element(find.text('Scan label'))).pop();
      await tester.pumpAndSettle();
      expect({
        for (final item in pantry.allItems) item.id: item.quantity,
      }, quantities);
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.pageBack();
      await tester.pumpAndSettle();
      for (final tab in [
        ('My Pantry', 'pantry'),
        ('Recipes', 'recipes'),
        ('Shopping', 'shopping'),
        ('Profile', 'profile'),
      ]) {
        await tester.tap(find.text(tab.$1).last);
        await tester.pumpAndSettle();
        expect(
          tester.takeException(),
          isNull,
          reason: '${config.$1}: ${tab.$2}',
        );
        await capture(tab.$2);
        if (tab.$2 == 'recipes') {
          await tester.tap(find.widgetWithText(ChoiceChip, 'Meal plan'));
          await tester.pumpAndSettle();
          expect(find.text('Plan your meals'), findsOneWidget);
          await tester.tap(find.widgetWithText(ChoiceChip, 'Saved recipes'));
          await tester.pumpAndSettle();
          expect(find.text('Your saved recipes'), findsOneWidget);
          await tester.tap(find.text('Home').last);
          await tester.pumpAndSettle();
          await tester.tap(find.text('Find recipes'));
          await tester.pumpAndSettle();
          expect(find.text('Find a recipe to cook'), findsOneWidget);
        }
      }
      expect(tester.takeException(), isNull);
    });
  }
}
