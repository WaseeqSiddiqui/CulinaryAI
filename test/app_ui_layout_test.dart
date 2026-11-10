import 'dart:io';
import 'dart:ui' as ui;

import 'package:culinary_ai/main.dart';
import 'package:culinary_ai/providers/theme_provider.dart';
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
      for (final tab in [
        ('My Pantry', 'pantry'),
        ('Chef Chat', 'chat'),
        ('Restock', 'shopping'),
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
      }
      expect(tester.takeException(), isNull);
    });
  }
}
