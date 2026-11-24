import 'package:culinary_ai/core/theme/app_theme.dart';
import 'package:culinary_ai/providers/pantry_provider.dart';
import 'package:culinary_ai/screens/pantry/expiry_overview_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets(
    'calendar selects dated items and keeps expired and undated food accessible',
    (tester) async {
      tester.view.physicalSize = const Size(320, 740);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final today = DateUtils.dateOnly(DateTime.now());
      final nextMonth = DateTime(today.year, today.month + 1, 2);
      final pantry = PantryProvider();
      addTearDown(pantry.dispose);
      for (final entry in <(String, DateTime?)>[
        ('Milk today', today),
        ('Yogurt today', today),
        ('Old spinach', today.subtract(const Duration(days: 1))),
        ('Next month rice', nextMonth),
        ('Undated flour', null),
      ]) {
        pantry.addItem(
          householdId: 'calendar-test',
          name: entry.$1,
          quantity: 1,
          unit: 'pcs',
          location: 'Fridge',
          expiryDate: entry.$2,
        );
      }
      await tester.pumpWidget(
        ChangeNotifierProvider.value(
          value: pantry,
          child: MaterialApp(
            theme: AppTheme.lightTheme,
            home: const ExpiryOverviewScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Your expiry calendar'), findsOneWidget);
      final todayKey = Key(
        'expiry-day-${DateFormat('yyyy-MM-dd').format(today)}',
      );
      expect(
        find.descendant(of: find.byKey(todayKey), matching: find.text('2')),
        findsWidgets,
      );
      await tester.scrollUntilVisible(find.text('Milk today'), 160);
      expect(find.text('Yogurt today'), findsOneWidget);
      expect(find.text('Old spinach'), findsNothing);
      await tester.drag(find.byType(ListView), const Offset(0, 1000));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Next month'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(
          Key('expiry-day-${DateFormat('yyyy-MM-dd').format(nextMonth)}'),
        ),
      );
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.text('Next month rice'), 160);
      expect(find.text('Milk today'), findsNothing);
      await tester.drag(find.byType(ListView), const Offset(0, 1000));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Expired (1)'));
      await tester.pumpAndSettle();
      expect(find.text('Old spinach'), findsOneWidget);
      await tester.tap(find.text('No date'));
      await tester.pumpAndSettle();
      expect(find.text('Undated flour'), findsOneWidget);
      expect(find.text('Old spinach'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}
