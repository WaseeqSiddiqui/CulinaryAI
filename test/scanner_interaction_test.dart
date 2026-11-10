import 'dart:async';
import 'dart:convert';

import 'package:culinary_ai/core/theme/app_theme.dart';
import 'package:culinary_ai/models/fridge_vision_models.dart';
import 'package:culinary_ai/models/meal_nutrition_estimate.dart';
import 'package:culinary_ai/models/nutrition_facts.dart';
import 'package:culinary_ai/models/pantry_item_model.dart';
import 'package:culinary_ai/models/receipt_vision_models.dart';
import 'package:culinary_ai/providers/auth_provider.dart';
import 'package:culinary_ai/providers/recipe_experience_provider.dart';
import 'package:culinary_ai/screens/scanner/expiry_label_scanner_screen.dart';
import 'package:culinary_ai/screens/scanner/fridge_scanner_screen.dart';
import 'package:culinary_ai/screens/scanner/meal_scanner_screen.dart';
import 'package:culinary_ai/screens/scanner/receipt_scanner_screen.dart';
import 'package:culinary_ai/services/meal_nutrition_service.dart';
import 'package:culinary_ai/services/receipt_ocr_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

final _png = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aN1cAAAAASUVORK5CYII=',
);

class _Picker extends ImagePicker {
  _Picker({this.fail = false});
  final bool fail;

  @override
  Future<XFile?> pickImage({
    required ImageSource source,
    double? maxWidth,
    double? maxHeight,
    int? imageQuality,
    CameraDevice preferredCameraDevice = CameraDevice.rear,
    bool requestFullMetadata = true,
  }) async {
    if (fail) throw PlatformException(code: 'camera_access_denied');
    return XFile.fromData(_png, name: 'plate.png', mimeType: 'image/png');
  }
}

class _NutritionService extends MealNutritionService {
  @override
  Future<MealNutritionEstimate> analyze({
    required Uint8List imageBytes,
    required String userId,
  }) async => const MealNutritionEstimate(
    dishName: 'Lunch',
    portionDescription: 'One plate',
    nutrition: NutritionFacts(calories: 400),
    confidence: 0.8,
    assumptions: [],
  );
}

class _MealLog extends RecipeExperienceProvider {
  int saves = 0;
  final done = Completer<void>();
  @override
  Future<void> recordNutrition({
    required String title,
    required NutritionFacts nutrition,
  }) {
    saves++;
    return done.future;
  }
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<void> prepare(WidgetTester tester, Widget child) async {
    tester.view.physicalSize = const Size(800, 1100);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        home: Scaffold(body: child),
      ),
    );
    await tester.pumpAndSettle();
  }

  for (final receipt in [true, false]) {
    testWidgets(
      '${receipt ? 'receipt' : 'fridge'} saves once and recovers from a failed save',
      (tester) async {
        var attempts = 0;
        var pending = Completer<void>();
        Future<void> save() {
          attempts++;
          return pending.future;
        }

        final item = ValidatedReceiptItem(
          rawText: 'Milk',
          name: 'Milk',
          matchedIngredient: 'Milk',
          unit: 'L',
          totalQty: 1,
        );
        final sheet = receipt
            ? ReceiptReviewSheet(
                response: ValidatedReceiptResponse(
                  scanId: 'test',
                  items: [item],
                ),
                items: [item],
                isDuplicate: false,
                receiptImage: null,
                onAliasCorrection: (_, _) {},
                onConfirm: (_) => save(),
                onRescan: () {},
              )
            : FridgeReviewSheet(
                response: FridgeScanResponse(
                  scanId: 'test',
                  reconciledItems: [
                    ReconciledFridgeItem(
                      detectedName: 'Milk',
                      status: 'new_item',
                      suggestedQuantity: 1,
                    ),
                  ],
                ),
                onConfirm: (_) => save(),
                onRescan: () {},
              );
        await prepare(tester, sheet);
        final label = receipt ? 'Add 1 item' : 'Save changes';
        await tester.tap(find.text(label));
        await tester.tap(find.text(label));
        await tester.pump();
        expect(attempts, 1);
        expect(find.text('Saving…'), findsOneWidget);
        expect(
          tester.widget<PopScope>(find.byType(PopScope).last).canPop,
          isFalse,
        );
        pending.completeError(StateError('Local save failed'));
        await tester.pumpAndSettle();
        expect(
          find.text('Changes could not be saved. Please try again.'),
          findsOneWidget,
        );
        pending = Completer<void>();
        await tester.tap(find.text(label));
        await tester.pump();
        expect(attempts, 2);
        pending.complete();
        await tester.pumpAndSettle();
        expect(find.text('Saved'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('editing a scanned expiry stores the corrected date as manual', (
    tester,
  ) async {
    ConfirmedExpiry? result;
    await prepare(
      tester,
      Builder(
        builder: (context) => FilledButton(
          onPressed: () async {
            result = await Navigator.of(context).push<ConfirmedExpiry>(
              MaterialPageRoute(
                builder: (_) => ExpiryLabelScannerScreen(
                  imagePicker: _Picker(),
                  ocrService: ReceiptOcrService(
                    extractor: (_) async => const ReceiptOcrEngineOutput(
                      hocr: '',
                      text: 'EXP 31/12/2026',
                    ),
                  ),
                ),
              ),
            );
          },
          child: const Text('Open expiry'),
        ),
      ),
    );
    await tester.tap(find.text('Open expiry'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Choose a photo'));
    await tester.pumpAndSettle();
    final edit = find.byIcon(Icons.edit_calendar_outlined);
    await tester.ensureVisible(edit);
    await tester.tap(edit);
    await tester.pumpAndSettle();
    await tester.tap(find.text('30').last);
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    final confirm = find.text('Confirm expiry date');
    await tester.ensureVisible(confirm);
    await tester.tap(confirm);
    await tester.pumpAndSettle();
    expect(result?.source, ExpirySource.manual);
    expect(result?.date, DateTime(2026, 12, 30));
    expect(tester.takeException(), isNull);
  });

  testWidgets('camera denial leaves meal scanning recoverable', (tester) async {
    await prepare(tester, MealScannerScreen(imagePicker: _Picker(fail: true)));
    await tester.tap(find.text('Take a photo'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Check camera permissions'), findsOneWidget);
    expect(
      tester
          .widget<OutlinedButton>(
            find.widgetWithText(OutlinedButton, 'Choose a photo'),
          )
          .onPressed,
      isNotNull,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('meal log prevents duplicate entries while saving', (
    tester,
  ) async {
    final log = _MealLog();
    await prepare(
      tester,
      MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => AuthProvider()),
          ChangeNotifierProvider<RecipeExperienceProvider>.value(value: log),
        ],
        child: MealScannerScreen(
          imagePicker: _Picker(),
          nutritionService: _NutritionService(),
        ),
      ),
    );
    await tester.tap(find.text('Choose a photo'));
    await tester.pumpAndSettle();
    final add = find.text('Add to today');
    await tester.scrollUntilVisible(
      add,
      400,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(add);
    await tester.tap(add);
    await tester.pump();
    expect(log.saves, 1);
    expect(find.text('Saving meal…'), findsOneWidget);
    log.done.complete();
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
