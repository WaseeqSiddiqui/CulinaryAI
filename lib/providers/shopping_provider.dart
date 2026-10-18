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
  final Set<String> _suppressedPantryIds = {};
  List<PantryItemModel> _latestPantryItems = const [];
  String? _householdId;
  bool _loading = false;
  bool _ready = false;
  bool _pantryReady = false;
  bool _syncingPantry = false;
  bool _pantrySyncRequested = false;

  List<ShoppingListItem> get items => List.unmodifiable(_items);
  bool get isLoading => _loading;
  String? get householdId => _householdId;

  void bindHousehold(
    String? householdId,
    List<PantryItemModel> pantryItems, {
    bool pantryReady = true,
  }) {
    _latestPantryItems = List.of(pantryItems);
    _pantryReady = pantryReady;
    if (_householdId == householdId) {
      if (_ready && !_loading) {
        unawaited(_syncLowStockItems());
      }
      return;
    }
    _householdId = householdId;
    _items.clear();
    _suppressedPantryIds.clear();
    _ready = false;
    if (householdId == null) return;
    Future.microtask(() => _load(householdId));
  }

  Future<void> _load(String householdId) async {
    _loading = true;
    notifyListeners();
    final stored = await _service.loadList(householdId);
    final suppressed = await _service.loadSuppressedPantryIds(householdId);
    if (_householdId != householdId) return;
    _items.addAll(stored);
    _suppressedPantryIds.addAll(suppressed);
    _ready = true;
    await _syncLowStockItems(notify: false);
    _loading = false;
    notifyListeners();
  }

  Future<void> _syncLowStockItems({bool notify = true}) async {
    if (!_ready || !_pantryReady || _householdId == null) return;
    if (_syncingPantry) {
      _pantrySyncRequested = true;
      return;
    }

    _syncingPantry = true;
    var changedAtLeastOnce = false;
    try {
      do {
        _pantrySyncRequested = false;
        final pantryById = {
          for (final item in _latestPantryItems) item.id: item,
        };
        final lowStockById = {
          for (final item in _latestPantryItems.where(
            (item) => item.isLowStock,
          ))
            item.id: item,
        };

        var changed = false;
        final suppressionCount = _suppressedPantryIds.length;
        _suppressedPantryIds.removeWhere((id) => !lowStockById.containsKey(id));
        changed = changed || suppressionCount != _suppressedPantryIds.length;

        final beforeRemoval = _items.length;
        _items.removeWhere(
          (item) =>
              pantryById.containsKey(item.id) &&
              !lowStockById.containsKey(item.id),
        );
        changed = changed || beforeRemoval != _items.length;

        final existingIds = _items.map((item) => item.id).toSet();
        for (final pantryItem in lowStockById.values) {
          if (existingIds.contains(pantryItem.id) ||
              _suppressedPantryIds.contains(pantryItem.id)) {
            continue;
          }
          _items.add(
            ShoppingListItem(
              id: pantryItem.id,
              name: pantryItem.name,
              quantity: _restockQuantity(pantryItem),
              unit: pantryItem.unit,
            ),
          );
          existingIds.add(pantryItem.id);
          changed = true;
        }

        if (changed) {
          changedAtLeastOnce = true;
          await _persist();
          await _persistSuppressedPantryIds();
        }
      } while (_pantrySyncRequested && _householdId != null);
    } finally {
      _syncingPantry = false;
    }
    if (notify && changedAtLeastOnce) notifyListeners();
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

  Future<void> addManualItem({
    required String name,
    required double quantity,
    required String unit,
  }) async {
    final trimmedName = name.trim();
    final trimmedUnit = unit.trim();
    if (_householdId == null ||
        trimmedName.isEmpty ||
        trimmedUnit.isEmpty ||
        !quantity.isFinite ||
        quantity <= 0) {
      return;
    }
    _items.add(
      ShoppingListItem(
        id: _uuid.v4(),
        name: trimmedName,
        quantity: quantity,
        unit: trimmedUnit,
      ),
    );
    await _persist();
    notifyListeners();
  }

  Future<void> remove(String id) async {
    if (_latestPantryItems.any((item) => item.id == id && item.isLowStock)) {
      _suppressedPantryIds.add(id);
      await _persistSuppressedPantryIds();
    }
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
    _suppressPendingLowStockItems(
      _items.where((item) => !item.keepAfterOrder).map((item) => item.id),
    );
    _items.removeWhere((item) => !item.keepAfterOrder);
    await _persist();
    await _persistSuppressedPantryIds();
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
    _suppressPendingLowStockItems(purchasedItemIds);
    _items.removeWhere(
      (item) => purchasedItemIds.contains(item.id) && !item.keepAfterOrder,
    );
    await _persist();
    await _persistSuppressedPantryIds();
    notifyListeners();
    return order;
  }

  Future<void> _persist() async {
    final householdId = _householdId;
    if (householdId != null) await _service.saveList(householdId, _items);
  }

  void _suppressPendingLowStockItems(Iterable<String> ids) {
    final lowStockIds = _latestPantryItems
        .where((item) => item.isLowStock)
        .map((item) => item.id)
        .toSet();
    _suppressedPantryIds.addAll(ids.where(lowStockIds.contains));
  }

  Future<void> _persistSuppressedPantryIds() async {
    final householdId = _householdId;
    if (householdId != null) {
      await _service.saveSuppressedPantryIds(householdId, _suppressedPantryIds);
    }
  }
}
