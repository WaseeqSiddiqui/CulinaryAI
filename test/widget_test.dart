import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:culinary_ai/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('CulinaryAI app boots to login screen test', (
    WidgetTester tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(const CulinaryAiApp());
    await tester.pumpAndSettle();

    // Verify CulinaryAI brand header and Sign In are present
    expect(find.text('CulinaryAI'), findsOneWidget);
    expect(find.text('Sign In'), findsOneWidget);
  });

  testWidgets('demo kitchen opens without account credentials', (
    WidgetTester tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(const CulinaryAiApp());
    await tester.pumpAndSettle();

    final demoButton = find.byKey(const Key('continueAsDemoButton'));
    await tester.ensureVisible(demoButton);
    await tester.tap(demoButton);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.text('Chef Alex'), findsOneWidget);
    expect(find.text('My Pantry'), findsOneWidget);
    expect(find.text('Chef Chat'), findsOneWidget);
  });
}
