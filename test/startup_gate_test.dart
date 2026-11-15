import 'package:culinary_ai/core/theme/app_theme.dart';
import 'package:culinary_ai/screens/startup/splash_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('branding stays until startup and session restoration finish', (
    tester,
  ) async {
    Widget app(bool initializing) => MaterialApp(
      theme: AppTheme.lightTheme,
      home: StartupGate(
        isInitializing: initializing,
        child: const Scaffold(body: Text('Signed-in destination')),
      ),
    );
    await tester.pumpWidget(app(true));
    expect(find.text('CulinaryAI'), findsOneWidget);
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Signed-in destination'), findsNothing);
    await tester.pumpWidget(app(false));
    await tester.pumpAndSettle();
    expect(find.text('Signed-in destination'), findsOneWidget);
    expect(find.byType(SplashScreen), findsNothing);
  });

  testWidgets('fast session restoration still shows a brief branded launch', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: StartupGate(
          isInitializing: false,
          child: const Scaffold(body: Text('Login destination')),
        ),
      ),
    );
    expect(find.byType(SplashScreen), findsOneWidget);
    await tester.pumpAndSettle();
    expect(find.text('Login destination'), findsOneWidget);
  });
}
