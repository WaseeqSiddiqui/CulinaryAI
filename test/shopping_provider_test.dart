import 'dart:async';

import 'package:culinary_ai/models/pantry_item_model.dart';
import 'package:culinary_ai/models/shopping_models.dart';
import 'package:culinary_ai/providers/shopping_provider.dart';
import 'package:culinary_ai/services/shopping_service.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeShoppingService extends ShoppingService {
  List<ShoppingListItem> storedItems = [];
  Set<String> suppressedIds = {};
  final List<ShoppingOrder> orders = [];
  Completer<void>? createGate;
  bool failCreate = false;

  @override
  Future<List<ShoppingListItem>> loadList(String householdId) async =>
      List.of(storedItems);

  @override
  Future<void> saveList(
    String householdId,
    List<ShoppingListItem> items,
  ) async {
    storedItems = List.of(items);
  }

  @override
  Future<Set<String>> loadSuppressedPantryIds(String householdId) async =>
      Set.of(suppressedIds);

  @override
  Future<void> saveSuppressedPantryIds(
    String householdId,
    Set<String> ids,
  ) async {
    suppressedIds = Set.of(ids);
  }

  @override
  Future<void> createOrder(ShoppingOrder order) async {
    if (createGate != null) await createGate!.future;
    if (failCreate) throw StateError('disk full');
    final index = orders.indexWhere((entry) => entry.id == order.id);
    if (index < 0) {
      orders.add(order);
    } else {
      orders[index] = order;
    }
  }
}

PantryItemModel _pantryItem({
  required String id,
  required double quantity,
  double threshold = 2,
}) => PantryItemModel(
  id: id,
  householdId: 'home',
  name: 'Milk',
  quantity: quantity,
  unit: 'L',
  location: 'Fridge',
  lowStockThreshold: threshold,
  updatedAt: DateTime.utc(2026, 10, 16),
);

Future<void> _settleProvider() async {
  await Future<void>.delayed(Duration.zero);
  await Future<void>.delayed(Duration.zero);
}

void main() {
  test('saved empty list still receives low-stock pantry items', () async {
    final service = _FakeShoppingService();
    final provider = ShoppingProvider(service: service);

    provider.bindHousehold('home', [_pantryItem(id: 'milk', quantity: 0.5)]);
    await _settleProvider();

    expect(provider.items, hasLength(1));
    expect(provider.items.single.id, 'milk');
    expect(provider.items.single.quantity, 1.5);
    expect(service.storedItems, hasLength(1));
  });

  test(
    'latest pantry snapshot wins when pantry loads after shopping',
    () async {
      final service = _FakeShoppingService();
      final provider = ShoppingProvider(service: service);

      provider.bindHousehold('home', const [], pantryReady: false);
      provider.bindHousehold('home', [
        _pantryItem(id: 'milk', quantity: 0.5),
      ], pantryReady: true);
      await _settleProvider();

      expect(provider.items.map((item) => item.id), contains('milk'));
    },
  );

  test(
    'removed low-stock item stays dismissed until it is restocked',
    () async {
      final service = _FakeShoppingService();
      final provider = ShoppingProvider(service: service);
      final low = _pantryItem(id: 'milk', quantity: 0.5);

      provider.bindHousehold('home', [low]);
      await _settleProvider();
      await provider.remove('milk');
      provider.bindHousehold('home', [low]);
      await _settleProvider();

      expect(provider.items, isEmpty);
      expect(service.suppressedIds, contains('milk'));

      provider.bindHousehold('home', [_pantryItem(id: 'milk', quantity: 3)]);
      await _settleProvider();
      provider.bindHousehold('home', [low]);
      await _settleProvider();

      expect(provider.items.map((item) => item.id), contains('milk'));
      expect(service.suppressedIds, isNot(contains('milk')));
    },
  );

  test('partial store order retains skipped rows and suppresses only purchased low stock', () async {
    final service = _FakeShoppingService();
    final provider = ShoppingProvider(service: service);
    final pantry = [
      _pantryItem(id: 'milk', quantity: 0.5),
      _pantryItem(id: 'eggs', quantity: 0),
    ];
    provider.bindHousehold('home', pantry);
    await _settleProvider();
    final snapshot = provider.items;
    final order = await provider.recordStoreOrder(
      storeName: 'PandaMart',
      total: 675,
      purchasedItemIds: {'milk'},
      purchasedItems: snapshot,
      orderId: 'same-order',
      expectedHouseholdId: 'home',
    );
    expect(order?.items.single.id, 'milk');
    expect(order?.total, 675);
    expect(provider.items.single.id, 'eggs');
    expect(service.suppressedIds, {'milk'});
    provider.bindHousehold('home', pantry);
    await _settleProvider();
    expect(provider.items.single.id, 'eggs');
    expect(pantry.first.quantity, 0.5);
  });

  test('repeated confirmation with one ID is idempotent even for retained shopping items', () async {
    final service = _FakeShoppingService()
      ..storedItems = const [
        ShoppingListItem(
          id: 'milk',
          name: 'Milk',
          quantity: 2,
          unit: 'L',
          keepAfterOrder: true,
        ),
      ];
    final provider = ShoppingProvider(service: service)
      ..bindHousehold('home', []);
    await _settleProvider();
    final first = provider.recordStoreOrder(
      storeName: 'PandaMart',
      total: 675,
      purchasedItemIds: {'milk'},
      orderId: 'same-order',
    );
    final second = provider.recordStoreOrder(
      storeName: 'PandaMart',
      total: 675,
      purchasedItemIds: {'milk'},
      orderId: 'same-order',
    );
    expect(identical(first, second), isTrue);
    await Future.wait([first, second]);
    expect(service.orders, hasLength(1));
    expect(provider.items, hasLength(1));
  });

  test(
    'a failed order save keeps the list and permits retry with the same ID',
    () async {
      final service = _FakeShoppingService()..failCreate = true;
      final provider = ShoppingProvider(service: service)
        ..bindHousehold('home', [_pantryItem(id: 'milk', quantity: 0)]);
      await _settleProvider();
      Future<ShoppingOrder?> record() => provider.recordStoreOrder(
        storeName: 'PandaMart',
        total: 675,
        purchasedItemIds: {'milk'},
        orderId: 'retry-order',
      );
      await expectLater(record(), throwsStateError);
      expect(provider.items, hasLength(1));
      service.failCreate = false;
      expect((await record())?.id, 'retry-order');
      expect(provider.items, isEmpty);
      expect(service.orders, hasLength(1));
    },
  );

  test(
    'preserves edits made to a shopping row while checkout is open',
    () async {
      final service = _FakeShoppingService();
      final provider = ShoppingProvider(service: service)
        ..bindHousehold('home', [_pantryItem(id: 'milk', quantity: 0)]);
      await _settleProvider();
      final snapshot = provider.items;
      await provider.setQuantity('milk', 5);
      final order = await provider.recordStoreOrder(
        storeName: 'PandaMart',
        total: 675,
        purchasedItemIds: {'milk'},
        purchasedItems: snapshot,
      );
      expect(order?.items.single.quantity, 2);
      expect(provider.items.single.quantity, 5);
    },
  );

  test(
    'rejects a checkout belonging to another household or an invalid total',
    () async {
      final service = _FakeShoppingService();
      final provider = ShoppingProvider(service: service)
        ..bindHousehold('home', [_pantryItem(id: 'milk', quantity: 0)]);
      await _settleProvider();
      expect(
        await provider.recordStoreOrder(
          storeName: 'PandaMart',
          total: 675,
          purchasedItemIds: {'milk'},
          expectedHouseholdId: 'other',
        ),
        isNull,
      );
      for (final total in [0.0, -1.0, double.nan, double.infinity]) {
        expect(
          await provider.recordStoreOrder(
            storeName: 'PandaMart',
            total: total,
            purchasedItemIds: {'milk'},
          ),
          isNull,
        );
      }
      expect(service.orders, isEmpty);
      expect(provider.items, hasLength(1));
    },
  );

  test('household switch during order saving does not remove the new household list', () async {
    final gate = Completer<void>();
    final service = _FakeShoppingService()..createGate = gate;
    final provider = ShoppingProvider(service: service)
      ..bindHousehold('home', [_pantryItem(id: 'milk', quantity: 0)]);
    await _settleProvider();
    final write = provider.recordStoreOrder(
      storeName: 'PandaMart',
      total: 675,
      purchasedItemIds: {'milk'},
      expectedHouseholdId: 'home',
    );
    service.storedItems = const [
      ShoppingListItem(id: 'other', name: 'Bread', quantity: 1, unit: 'pcs'),
    ];
    provider.bindHousehold('other-home', []);
    await _settleProvider();
    gate.complete();
    await write;
    expect(provider.items.single.id, 'other');
    expect(service.orders.single.householdId, 'home');
  });
}
