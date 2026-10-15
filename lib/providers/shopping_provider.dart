import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../models/pantry_item_model.dart';
import '../models/shopping_models.dart';
import '../services/shopping_service.dart';

class ShoppingProvider extends ChangeNotifier {
  ShoppingProvider({ShoppingService? service})
    : _service = service ?? ShoppingService();

  static const _uuid = Uuid();
  final ShoppingService _service;
  final List<ShoppingListItem> _items = [];
  String? _householdId;
  bool _loading = false;
  bool _maySeedFromPantry = false;

  List<ShoppingListItem> get items => List.unmodifiable(_items);
  bool get isLoading => _loading;
  String? get householdId => _householdId;

  void bindHousehold(String? householdId, List<PantryItemModel> pantryItems) {
    if (_householdId == householdId) {
      if (_maySeedFromPantry && !_loading && pantryItems.isNotEmpty) {
        unawaited(_seedFromPantry(pantryItems));
      }
      return;
    }
    _householdId = householdId;
    _items.clear();
    _maySeedFromPantry = false;
    if (householdId == null) return;
    Future.microtask(() => _load(householdId, pantryItems));
  }

  Future<void> _load(
    String householdId,
    List<PantryItemModel> pantryItems,
  ) async {
    _loading = true;
    notifyListeners();
    final hadSavedList = await _service.hasSavedList(householdId);
    final stored = await _service.loadList(householdId);
    if (_householdId != householdId) return;
    _items.addAll(stored);
    if (_items.isEmpty && !hadSavedList) {
      _maySeedFromPantry = true;
      if (pantryItems.isNotEmpty) await _seedFromPantry(pantryItems);
    }
    _loading = false;
    notifyListeners();
  }

  Future<void> _seedFromPantry(List<PantryItemModel> pantryItems) async {
    if (!_maySeedFromPantry) return;
    _items.addAll(
      pantryItems
          .where((item) => item.isLowStock)
          .map(
            (item) => ShoppingListItem(
              id: item.id,
              name: item.name,
              quantity: _restockQuantity(item),
              unit: item.unit,
            ),
          ),
    );
    _maySeedFromPantry = false;
    await _persist();
    notifyListeners();
  }

  static double _restockQuantity(PantryItemModel item) {
    final shortage = item.lowStockThreshold - item.quantity;
    return shortage > 0 ? shortage : item.lowStockThreshold;
  }

  Future<void> setQuantity(String id, double quantity) async {
    final index = _items.indexWhere((item) => item.id == id);
    if (index < 0 || quantity <= 0) return;
    final item = _items[index];
    _items[index] = ShoppingListItem(
      id: item.id,
      name: item.name,
      quantity: quantity,
      unit: item.unit,
      keepAfterOrder: item.keepAfterOrder,
    );
    await _persist();
    notifyListeners();
  }

  Future<void> remove(String id) async {
    _items.removeWhere((item) => item.id == id);
    await _persist();
    notifyListeners();
  }

  Future<ShoppingOrder?> placePendingOrder() async {
    final householdId = _householdId;
    if (householdId == null || _items.isEmpty) return null;
    final order = ShoppingOrder(
      id: _uuid.v4(),
      householdId: householdId,
      items: List.of(_items),
      status: 'pending',
      createdAt: DateTime.now(),
    );
    await _service.createOrder(order);
    _items.removeWhere((item) => !item.keepAfterOrder);
    await _persist();
    notifyListeners();
    return order;
  }

  Future<ShoppingOrder?> recordStoreOrder({
    required String storeName,
    required double total,
    required Set<String> purchasedItemIds,
  }) async {
    final householdId = _householdId;
    final purchased = _items
        .where((item) => purchasedItemIds.contains(item.id))
        .toList();
    if (householdId == null || purchased.isEmpty) return null;
    final order = ShoppingOrder(
      id: _uuid.v4(),
      householdId: householdId,
      items: purchased,
      status: 'ordered (pending delivery)',
      createdAt: DateTime.now(),
      storeName: storeName,
      total: total,
    );
    await _service.createOrder(order);
    _items.removeWhere(
      (item) => purchasedItemIds.contains(item.id) && !item.keepAfterOrder,
    );
    await _persist();
    notifyListeners();
    return order;
  }

  Future<void> _persist() async {
    final householdId = _householdId;
    if (householdId != null) await _service.saveList(householdId, _items);
  }
}
