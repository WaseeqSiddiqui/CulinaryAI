import 'package:culinary_ai/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets(
    'pantry search preserves focus and leaves room for keyboard results',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetViewInsets);
      await tester.pumpWidget(const CulinaryAiApp());
      await tester.pumpAndSettle();
      final demo = find.byKey(const Key('continueAsDemoButton'));
      await tester.ensureVisible(demo);
      await tester.tap(demo);
      await tester.pumpAndSettle();
      await tester.tap(find.text('My Pantry').last);
      await tester.pumpAndSettle();
      expect(find.byType(DropdownButtonFormField<String>), findsOneWidget);
      final search = find.byType(TextField);
      await tester.showKeyboard(search);
      tester.view.viewInsets = const FakeViewPadding(bottom: 300);
      await tester.pumpAndSettle();
      expect(find.byType(DropdownButtonFormField<String>), findsNothing);
      await tester.enterText(search, 'Eggs');
      await tester.pumpAndSettle();
      expect(find.text('Eggs'), findsWidgets);
      expect(tester.testTextInput.isVisible, isTrue);
      expect(tester.takeException(), isNull);
      tester.testTextInput.hide();
      tester.view.resetViewInsets();
      await tester.pumpAndSettle();
      expect(find.byType(DropdownButtonFormField<String>), findsOneWidget);
      expect(find.text('Eggs'), findsWidgets);
      expect(tester.takeException(), isNull);
    },
  );
}
