import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:culinary_ai/main.dart';
import 'package:culinary_ai/models/receipt_vision_models.dart';
import 'package:culinary_ai/models/fridge_vision_models.dart';
import 'package:culinary_ai/models/shopping_models.dart';
import 'package:culinary_ai/providers/pantry_provider.dart';
import 'package:culinary_ai/providers/shopping_provider.dart';
import 'package:culinary_ai/providers/theme_provider.dart';
import 'package:culinary_ai/screens/auth/register_screen.dart';
import 'package:culinary_ai/screens/cooking/guided_cooking_screen.dart';
import 'package:culinary_ai/screens/household/household_screen.dart';
import 'package:culinary_ai/screens/profile/personal_details_screen.dart';
import 'package:culinary_ai/screens/recipes/recipe_hub_screen.dart';
import 'package:culinary_ai/screens/scanner/expiry_label_scanner_screen.dart';
import 'package:culinary_ai/screens/scanner/fridge_scanner_screen.dart';
import 'package:culinary_ai/screens/scanner/meal_scanner_screen.dart';
import 'package:culinary_ai/screens/scanner/receipt_scanner_screen.dart';
import 'package:culinary_ai/screens/shopping/order_history_screen.dart';
import 'package:culinary_ai/screens/shopping/store_automation_screen.dart';
import 'package:culinary_ai/services/recipe_recommendation_service.dart';
import 'package:culinary_ai/services/shopping_service.dart';
import 'package:culinary_ai/widgets/recipe_nutrition_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

// The native store page is deliberately inert. These tests exercise the app's
// surrounding controls and never connect to a merchant or place an order.
class _TestStorePlatform extends InAppWebViewPlatform {
  @override
  PlatformInAppWebViewWidget createPlatformInAppWebViewWidget(
    PlatformInAppWebViewWidgetCreationParams params,
  ) => _TestStoreWidget(params);
}

class _TestStoreWidget extends PlatformInAppWebViewWidget {
  _TestStoreWidget(super.params) : super.implementation();
  @override
  Widget build(BuildContext context) => ColoredBox(
    color: Theme.of(context).colorScheme.surfaceContainerHighest,
    child: const Center(child: Text('Store page · test preview')),
  );
  @override
  T controllerFromPlatform<T>(PlatformInAppWebViewController controller) =>
      throw UnsupportedError('No merchant controller in a layout test');
  @override
  void dispose() {}
}

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
    InAppWebViewPlatform.instance = _TestStorePlatform();
    await rootBundle.loadString('assets/store_selectors.json');
  });

  for (final config in <(String, Size, bool, double)>[
    ('small_phone', const Size(320, 740), false, 1),
    ('phone', const Size(390, 844), false, 1),
    ('desktop', const Size(1440, 1000), false, 1),
    ('dark_phone', const Size(390, 844), true, 1),
    ('larger_text', const Size(390, 844), false, 1.3),
  ]) {
    testWidgets('secondary routes fit ${config.$1}', (tester) async {
      SharedPreferences.setMockInitialValues({});
      tester.view.physicalSize = config.$2;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('flutter_tts'),
        (call) async => 1,
      );
      final boundary = GlobalKey();
      await tester.pumpWidget(
        RepaintBoundary(
          key: boundary,
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
      final demo = find.byKey(const Key('continueAsDemoButton'));
      await tester.ensureVisible(demo);
      await tester.tap(demo);
      await tester.pumpAndSettle();
      final rootContext = tester.element(find.byType(Navigator).first);
      if (config.$3) {
        rootContext.read<ThemeProvider>().setThemeMode(ThemeMode.dark);
        await tester.pumpAndSettle();
      }
      final recipe = RecipeRecommendationService.getHeroRecommendation(
        rootContext.read<PantryProvider>().allItems,
      );
      final navigator = Navigator.of(rootContext);

      Future<void> capture(String name) async {
        expect(tester.takeException(), isNull, reason: '${config.$1}: $name');
        const directory = String.fromEnvironment('UI_CAPTURE_DIR');
        if (directory.isEmpty) return;
        await tester.pump(const Duration(milliseconds: 250));
        await tester.runAsync(() async {
          final object =
              boundary.currentContext!.findRenderObject()!
                  as RenderRepaintBoundary;
          final image = await object.toImage(pixelRatio: 1);
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          final file = File('$directory/${config.$1}_$name.png');
          await file.parent.create(recursive: true);
          await file.writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
      }

      Future<void> visit(
        String name,
        Widget screen, {
        Future<void> Function()? inspect,
      }) async {
        unawaited(
          navigator.push<void>(MaterialPageRoute(builder: (_) => screen)),
        );
        await tester.pump();
        await tester.runAsync(() async {
          await Future<void>.delayed(const Duration(milliseconds: 30));
        });
        await tester.pumpAndSettle();
        await capture(name);
        if (inspect != null) await inspect();
        navigator.pop();
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: 'Leaving $name');
      }

      await visit('register', const RegisterScreen());
      await visit(
        'recipes',
        const RecipeHubScreen(),
        inspect: () async {
          // Check the actual recipe sheet and portion controls as well as the list.
          final title = find.text(recipe.title);
          if (title.evaluate().isNotEmpty) {
            await tester.ensureVisible(title.first);
            await tester.pumpAndSettle();
            await tester.tap(title.first);
            await tester.pumpAndSettle();
            await capture('recipe_details');
            navigator.pop();
            await tester.pumpAndSettle();
          }
        },
      );
      for (final entry in [
        ('create_recipe', RecipeSection.create),
        ('weekly_plan', RecipeSection.weekly),
        ('nutrition_goals', RecipeSection.macros),
        ('saved_recipes', RecipeSection.saved),
      ]) {
        await visit(entry.$1, RecipeHubScreen(section: entry.$2));
      }
      await visit('cooking_preferences', const CookingPreferencesScreen());
      await visit('personal_details', const PersonalDetailsScreen());
      await visit('receipt_scan', const ReceiptScannerScreen());
      await visit('fridge_scan', const FridgeScannerScreen());
      await visit('meal_scan', const MealScannerScreen());
      await visit('expiry_scan', const ExpiryLabelScannerScreen());
      final receiptItems = [
        ValidatedReceiptItem(
          rawText: 'MILK 1L',
          name: 'Milk',
          matchedIngredient: 'Milk',
          unit: 'L',
          totalQty: 2,
          linePrice: 650,
          storageZone: 'Fridge',
        ),
        ValidatedReceiptItem(
          rawText: 'EGGS 6',
          name: 'Eggs',
          matchedIngredient: 'Eggs',
          unit: 'pcs',
          totalQty: 6,
          linePrice: 240,
          storageZone: 'Fridge',
          needsReview: true,
          isSelected: false,
          reviewReasons: ['Check the printed quantity'],
        ),
      ];
      unawaited(
        showModalBottomSheet<void>(
          context: rootContext,
          isScrollControlled: true,
          useSafeArea: true,
          showDragHandle: false,
          constraints: const BoxConstraints(maxWidth: 760),
          builder: (_) => ReceiptReviewSheet(
            response: ValidatedReceiptResponse(
              scanId: 'layout',
              storeName: 'Your local grocer',
              date: '30 Oct 2026',
              currency: 'PKR',
              receiptTotal: 890,
              items: receiptItems,
            ),
            items: receiptItems,
            isDuplicate: true,
            receiptImage: null,
            onAliasCorrection: (_, _) {},
            onConfirm: (_) {},
            onRescan: () => navigator.pop(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await capture('receipt_review');
      navigator.pop();
      await tester.pumpAndSettle();
      unawaited(
        showModalBottomSheet<void>(
          context: rootContext,
          isScrollControlled: true,
          useSafeArea: true,
          showDragHandle: false,
          constraints: const BoxConstraints(maxWidth: 760),
          builder: (_) => FridgeReviewSheet(
            response: FridgeScanResponse(
              scanId: 'layout',
              reconciledItems: [
                ReconciledFridgeItem(
                  detectedName: 'Milk',
                  matchedName: 'Milk',
                  status: 'verified',
                  currentQuantity: 2,
                  suggestedQuantity: 2,
                  unit: 'L',
                ),
                ReconciledFridgeItem(
                  detectedName: 'Eggs',
                  matchedName: 'Eggs',
                  status: 'mismatch',
                  currentQuantity: 12,
                  suggestedQuantity: 6,
                  unit: 'pcs',
                  isAccepted: false,
                  question: 'There appear to be 6 eggs. Update the count?',
                ),
                ReconciledFridgeItem(
                  detectedName: 'Yogurt',
                  status: 'new_item',
                  suggestedQuantity: 1,
                  unit: 'pcs',
                ),
              ],
            ),
            onConfirm: (_) {},
            onRescan: () => navigator.pop(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await capture('fridge_review');
      navigator.pop();
      await tester.pumpAndSettle();
      await visit(
        'recipe_nutrition',
        Scaffold(
          appBar: AppBar(title: const Text('Recipe portions')),
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: RecipeNutritionPanel(recipe: recipe, isDark: config.$3),
          ),
        ),
      );
      await visit('order_history', const OrderHistoryScreen());
      final householdId = rootContext.read<ShoppingProvider>().householdId!;
      await ShoppingService().createOrder(
        ShoppingOrder(
          id: 'layout-order',
          householdId: householdId,
          items: const [
            ShoppingListItem(id: 'milk', name: 'Milk', quantity: 2, unit: 'L'),
          ],
          status: 'ordered (pending delivery)',
          createdAt: DateTime(2026, 10, 30),
          storeName: 'PandaMart',
          total: 675,
          storeOrderReference: 'test-order-123',
        ),
      );
      await visit(
        'order_details',
        const OrderHistoryScreen(),
        inspect: () async {
          await tester.tap(find.text('PandaMart').last);
          await tester.pumpAndSettle();
          await capture('order_items');
        },
      );
      await visit(
        'store_setup',
        StoreAutomationScreen(
          items: rootContext.read<ShoppingProvider>().items,
        ),
      );
      await visit(
        'browser_shopping',
        const StoreAutomationScreen(
          externalStore: true,
          items: [
            ShoppingListItem(id: 'milk', name: 'Milk', quantity: 2, unit: 'L'),
          ],
        ),
        inspect: () async {
          final record = find.text('Record completed order');
          await tester.scrollUntilVisible(
            record,
            300,
            scrollable: find.byType(Scrollable).first,
          );
          await tester.tap(record);
          await tester.pumpAndSettle();
          await tester.tap(find.text('Order confirmed'));
          await tester.pumpAndSettle();
          expect(
            find.text('Select at least one purchased item'),
            findsOneWidget,
          );
          await tester.tap(find.text('Not yet'));
          await tester.pumpAndSettle();
        },
      );
      await visit(
        'guided_cooking',
        GuidedCookingScreen(recipe: recipe),
        inspect: () async {
          await tester.tap(find.text('Ask Chef').first);
          await tester.pumpAndSettle();
          await capture('cooking_assistant');
        },
      );
      await visit(
        'household',
        const HouseholdScreen(),
        inspect: () async {
          await tester.enterText(
            find.byType(TextField).first,
            'Our shared kitchen',
          );
          await tester.ensureVisible(find.text('Create household'));
          await tester.tap(find.text('Create household'));
          await tester.pumpAndSettle();
          await capture('household_members');
        },
      );
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });
  }
}
