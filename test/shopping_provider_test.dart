import 'package:culinary_ai/models/pantry_item_model.dart';
import 'package:culinary_ai/models/shopping_models.dart';
import 'package:culinary_ai/providers/shopping_provider.dart';
import 'package:culinary_ai/services/shopping_service.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeShoppingService extends ShoppingService {
  List<ShoppingListItem> storedItems = [];
  Set<String> suppressedIds = {};
  final List<ShoppingOrder> orders = [];

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
  Future<void> createOrder(ShoppingOrder order) async => orders.add(order);
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
}
