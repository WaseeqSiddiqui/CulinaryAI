import 'package:culinary_ai/models/shopping_models.dart';
import 'package:culinary_ai/providers/shopping_provider.dart';
import 'package:culinary_ai/screens/shopping/shopping_list_screen.dart';
import 'package:culinary_ai/services/shopping_service.dart';
import 'package:culinary_ai/services/purchase_session_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets(
    'an interrupted checkout remains accessible with an empty shopping list',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      await PurchaseSessionStore().save(
        const PurchaseSession(
          id: 'checkout',
          householdId: 'home',
          items: [
            ShoppingListItem(id: 'milk', name: 'Milk', quantity: 2, unit: 'L'),
          ],
          total: 675,
          confirmed: true,
        ),
      );
      final shopping = ShoppingProvider()..bindHousehold('home', []);
      await tester.pumpWidget(
        ChangeNotifierProvider.value(
          value: shopping,
          child: const MaterialApp(home: ShoppingListScreen()),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Resume PandaMart checkout'), findsOneWidget);
      final button = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Resume PandaMart checkout'),
      );
      expect(button.onPressed, isNotNull);
    },
  );
  testWidgets(
    'shopping list opens durable order history with total and merchant reference',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final service = ShoppingService();
      await service.createOrder(
        ShoppingOrder(
          id: 'order-1',
          householdId: 'home',
          items: const [
            ShoppingListItem(id: 'milk', name: 'Milk', quantity: 2, unit: 'L'),
          ],
          status: 'ordered (pending delivery)',
          createdAt: DateTime(2026, 10, 30, 12),
          storeName: 'PandaMart',
          total: 675,
          storeOrderReference: 'panda-123',
        ),
      );
      final shopping = ShoppingProvider(service: service)
        ..bindHousehold('home', []);
      await tester.pumpWidget(
        ChangeNotifierProvider.value(
          value: shopping,
          child: const MaterialApp(home: ShoppingListScreen()),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Order history'));
      await tester.pumpAndSettle();
      expect(find.text('Order history'), findsOneWidget);
      expect(find.text('Rs 675.00'), findsOneWidget);
      await tester.tap(find.text('PandaMart'));
      await tester.pumpAndSettle();
      expect(find.text('panda-123'), findsOneWidget);
      expect(find.text('Milk'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
