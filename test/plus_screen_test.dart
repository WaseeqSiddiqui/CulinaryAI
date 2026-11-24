import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:culinary_ai/core/theme/app_theme.dart';
import 'package:culinary_ai/screens/subscription/plus_screen.dart';
import 'package:culinary_ai/services/authenticated_api_client.dart';
import 'package:culinary_ai/services/subscription_api_service.dart';
import 'package:culinary_ai/widgets/subscription_notifications.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'support/load_ui_fonts.dart';

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await loadUiFonts();
  });
  for (final width in [320.0, 390.0, 1280.0]) {
    testWidgets('Free and Plus plans show accurate usage at width $width', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final service = SubscriptionApiService(
        baseUrl: 'https://backend.test',
        client: MockClient(
          (_) async => http.Response(
            jsonEncode({
              'plan': 'free',
              'limits': {'chat': 20, 'photo': 3},
              'used': {'chat': 7, 'photo': 2},
              'resets_at': '2026-12-01T00:00:00Z',
            }),
            200,
          ),
        ),
      );
      addTearDown(service.close);
      final boundary = GlobalKey();
      await tester.pumpWidget(
        RepaintBoundary(
          key: boundary,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: AppTheme.lightTheme,
            builder: (_, child) => MediaQuery(
              data: MediaQueryData(
                size: Size(width, 844),
                textScaler: const TextScaler.linear(1.3),
              ),
              child: child!,
            ),
            home: PlusScreen(service: service),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Chef requests: 7 / 20'), findsOneWidget);
      expect(find.text('Photo scans: 2 / 3'), findsOneWidget);
      expect(find.text('Resets 1 Dec 2026'), findsOneWidget);
      const capture = String.fromEnvironment('UI_CAPTURE_DIR');
      if (capture.isNotEmpty) {
        await tester.runAsync(() async {
          final image =
              await (boundary.currentContext!.findRenderObject()!
                      as RenderRepaintBoundary)
                  .toImage(pixelRatio: 1);
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          final file = File('$capture/plus_${width.toInt()}.png');
          await file.parent.create(recursive: true);
          await file.writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
      }
      await tester.scrollUntilVisible(
        find.text('Subscribe with Google Play'),
        220,
      );
      expect(find.text('Price available on Google Play'), findsOneWidget);
      expect(find.text('500 Chef requests / month'), findsOneWidget);
      expect(find.text('50 photo scans / month'), findsOneWidget);
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Subscribe with Google Play'),
            )
            .onPressed,
        isNull,
      );
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('only user allowance errors show the plan dialog', (
    tester,
  ) async {
    final navigator = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigator,
        builder: (_, child) =>
            SubscriptionNotifications(navigatorKey: navigator, child: child!),
        home: const Scaffold(body: Text('Kitchen')),
      ),
    );
    SubscriptionEvents.limits.add(
      QuotaLimitNotice(
        kind: 'photo',
        plan: 'free',
        message: 'Your monthly photo allowance is used up.',
        resetsAt: DateTime.utc(2026, 12),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Monthly allowance reached'), findsOneWidget);
    expect(find.textContaining('subscription availability'), findsOneWidget);
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();
    expect(find.text('Kitchen'), findsOneWidget);
  });
}
