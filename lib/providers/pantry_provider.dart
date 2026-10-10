import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../models/pantry_item_model.dart';
import '../services/pantry_service.dart';

class PantryProvider extends ChangeNotifier {
  PantryProvider({PantryService? service})
    : _service = service ?? PantryService();

  static const _uuid = Uuid();
  static const List<String> zones = [
    'Fridge',
    'Freezer',
    'Pantry Shelf',
    'Spice Rack',
  ];
  static const List<String> units = [
    'pcs',
    'g',
    'kg',
    'ml',
    'L',
    'cups',
    'tbsp',
    'tsp',
    'dozen',
  ];

  final PantryService _service;
  final List<PantryItemModel> _items = [];
  StreamSubscription<List<PantryItemModel>>? _subscription;
  String? _householdId;
  String _searchQuery = '';
  String? _selectedZone;
  bool _isLoading = false;
  bool _receivedRemoteSnapshot = false;
  String? _errorMessage;

  String get searchQuery => _searchQuery;
  String? get selectedZone => _selectedZone;
  String? get householdId => _householdId;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  List<PantryItemModel> get allItems => List.unmodifiable(_items);

  List<PantryItemModel> get filteredItems {
    return _items.where((item) {
      final matchesZone =
          _selectedZone == null || item.location == _selectedZone;
      final matchesSearch =
          _searchQuery.isEmpty ||
          item.name.toLowerCase().contains(_searchQuery.toLowerCase());
      return matchesZone && matchesSearch;
    }).toList()..sort((a, b) => a.name.compareTo(b.name));
  }

  Map<String, List<PantryItemModel>> get itemsByZone {
    final grouped = <String, List<PantryItemModel>>{};
    for (final zone in zones) {
      final zoneItems = filteredItems
          .where((item) => item.location == zone)
          .toList();
      if (zoneItems.isNotEmpty) grouped[zone] = zoneItems;
    }
    return grouped;
  }

  int get totalCount => _items.length;
  int get lowStockCount => _items.where((item) => item.isLowStock).length;

  void bindHousehold(String? householdId) {
    if (_householdId == householdId) return;
    _householdId = householdId;
    _items.clear();
    _subscription?.cancel();
    _subscription = null;
    _receivedRemoteSnapshot = false;
    if (householdId == null) {
      _isLoading = false;
      return;
    }
    Future.microtask(() => _startSync(householdId));
  }

  Future<void> _startSync(String householdId) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();
    final localItems = await _service.loadLocal(householdId);
    if (_householdId != householdId) return;
    _items
      ..clear()
      ..addAll(localItems);
    _isLoading = false;
    notifyListeners();

    _subscription = _service
        .watch(householdId)
        .listen(
          (remoteItems) async {
            if (_householdId != householdId) return;
            if (!_receivedRemoteSnapshot &&
                remoteItems.isEmpty &&
                _items.isNotEmpty) {
              _receivedRemoteSnapshot = true;
              for (final item in _items) {
                unawaited(_service.upsert(item));
              }
              return;
            }
            _receivedRemoteSnapshot = true;
            _items
              ..clear()
              ..addAll(remoteItems);
            await _service.saveLocal(householdId, _items);
            notifyListeners();
          },
          onError: (Object error) {
            _errorMessage = 'Using the offline pantry copy.';
            notifyListeners();
          },
        );
  }

  void setSearch(String query) {
    _searchQuery = query;
    notifyListeners();
  }

  void setZoneFilter(String? zone) {
    _selectedZone = zone;
    notifyListeners();
  }

  void addItem({
    required String householdId,
    required String name,
    required double quantity,
    required String unit,
    required String location,
    double lowStockThreshold = 1.0,
    String? customImageUrl,
    String addedVia = 'manual',
  }) {
    final scopeId = _householdId ?? householdId;
    final item = PantryItemModel(
      id: _uuid.v4(),
      householdId: scopeId,
      name: name.trim(),
      quantity: quantity,
      unit: unit,
      location: location,
      lowStockThreshold: lowStockThreshold,
      addedVia: addedVia,
      updatedAt: DateTime.now(),
      customImageUrl: customImageUrl,
    );
    _items.add(item);
    _persistAndSync(item);
    notifyListeners();
  }

  void updateItem(PantryItemModel updated) {
    final index = _items.indexWhere((item) => item.id == updated.id);
    if (index == -1) return;
    final item = updated.copyWith(
      householdId: _householdId ?? updated.householdId,
      updatedAt: DateTime.now(),
    );
    _items[index] = item;
    _persistAndSync(item);
    notifyListeners();
  }

  void deleteItem(String id) {
    final householdId = _householdId;
    if (householdId == null) return;
    _items.removeWhere((item) => item.id == id);
    unawaited(_service.saveLocal(householdId, _items));
    unawaited(_service.delete(householdId, id));
    notifyListeners();
  }

  void adjustQuantity(String id, double delta) {
    final index = _items.indexWhere((item) => item.id == id);
    if (index == -1) return;
    final current = _items[index];
    final quantity = (current.quantity + delta)
        .clamp(0.0, double.infinity)
        .toDouble();
    final updated = current.copyWith(
      quantity: quantity,
      updatedAt: DateTime.now(),
    );
    _items[index] = updated;
    _persistAndSync(updated);
    notifyListeners();
  }

  int deductIngredients(List<String> ingredientNames) {
    final changed = <PantryItemModel>[];
    final usedIds = <String>{};
    for (final ingredientName in ingredientNames) {
      final required = ingredientName.toLowerCase();
      final index = _items.indexWhere((item) {
        if (usedIds.contains(item.id) || item.quantity <= 0) return false;
        final available = item.name.toLowerCase();
        return available.contains(required) || required.contains(available);
      });
      if (index == -1) continue;
      final current = _items[index];
      final amount = _recipeUseAmount(current.unit);
      final updated = current.copyWith(
        quantity: (current.quantity - amount)
            .clamp(0.0, double.infinity)
            .toDouble(),
        updatedAt: DateTime.now(),
      );
      _items[index] = updated;
      usedIds.add(updated.id);
      changed.add(updated);
    }
    for (final item in changed) {
      _persistAndSync(item);
    }
    if (changed.isNotEmpty) notifyListeners();
    return changed.length;
  }

  double _recipeUseAmount(String unit) {
    return switch (unit.toLowerCase()) {
      'g' || 'ml' => 100,
      'kg' || 'l' || 'litres' => 0.2,
      'dozen' => 0.25,
      _ => 1,
    };
  }

  void _persistAndSync(PantryItemModel item) {
    final householdId = _householdId;
    if (householdId == null) return;
    unawaited(_service.saveLocal(householdId, _items));
    unawaited(_service.upsert(item));
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }
}
