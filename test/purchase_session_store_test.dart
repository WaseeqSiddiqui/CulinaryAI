import 'package:culinary_ai/models/shopping_models.dart';
import 'package:culinary_ai/services/purchase_session_store.dart';
import 'package:culinary_ai/services/shopping_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _milk = ShoppingListItem(
  id: 'milk',
  name: 'Milk',
  quantity: 2,
  unit: 'L',
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('submission checkpoint survives a new store instance and is household scoped', () async {
    await PurchaseSessionStore().save(
      const PurchaseSession(
        id: 'order-1',
        householdId: 'home',
        items: [_milk],
        total: 675,
        confirmed: false,
      ),
    );
    final recovered = await PurchaseSessionStore().load('home');
    expect(recovered?.id, 'order-1');
    expect(recovered?.items.single.quantity, 2);
    expect(recovered?.total, 675);
    expect(recovered?.confirmed, isFalse);
    expect(await PurchaseSessionStore().load('other-home'), isNull);
    await PurchaseSessionStore().clear('home');
    expect(await PurchaseSessionStore().load('home'), isNull);
  });

  test(
    'corrupt checkpoint fails closed instead of enabling another purchase',
    () async {
      SharedPreferences.setMockInitialValues({
        'culinary_pandamart_checkout_home': '{broken',
      });
      await expectLater(
        PurchaseSessionStore().load('home'),
        throwsFormatException,
      );
      expect(
        (await SharedPreferences.getInstance()).containsKey(
          'culinary_pandamart_checkout_home',
        ),
        isTrue,
      );
    },
  );

  test('saving the same order ID twice keeps one durable order with its merchant reference', () async {
    final service = ShoppingService();
    final order = ShoppingOrder(
      id: 'order-1',
      householdId: 'home',
      items: [_milk],
      status: 'ordered (pending delivery)',
      createdAt: DateTime.utc(2026, 10, 30),
      storeName: 'PandaMart',
      total: 675,
      storeOrderReference: 'panda-123',
    );
    await service.createOrder(order);
    await service.createOrder(order);
    final orders = await ShoppingService().loadOrders('home');
    expect(orders, hasLength(1));
    expect(orders.single.storeOrderReference, 'panda-123');
    expect(orders.single.total, 675);
  });
}
