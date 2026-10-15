import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../models/pantry_item_model.dart';
import '../models/receipt_vision_models.dart';
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
    if (_items.isEmpty && householdId == 'personal_demo_chef') {
      _items.addAll(_demoPantry(householdId));
      await _service.saveLocal(householdId, _items);
    }
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

  List<PantryItemModel> _demoPantry(String householdId) {
    final now = DateTime.now();
    PantryItemModel item(
      String id,
      String name,
      double quantity,
      String unit,
      String location,
      double lowStockThreshold,
    ) => PantryItemModel(
      id: id,
      householdId: householdId,
      name: name,
      quantity: quantity,
      unit: unit,
      location: location,
      lowStockThreshold: lowStockThreshold,
      addedVia: 'demo',
      updatedAt: now,
    );

    return [
      item('demo_chicken', 'Chicken Breast', 0.8, 'kg', 'Fridge', 0.5),
      item('demo_eggs', 'Eggs', 4, 'pcs', 'Fridge', 6),
      item('demo_spinach', 'Spinach', 1, 'pcs', 'Fridge', 1),
      item('demo_peas', 'Frozen Peas', 0.6, 'kg', 'Freezer', 0.25),
      item('demo_rice', 'Basmati Rice', 2, 'kg', 'Pantry Shelf', 0.5),
      item('demo_pasta', 'Pasta', 0.4, 'kg', 'Pantry Shelf', 0.5),
      item('demo_tomatoes', 'Canned Tomatoes', 3, 'pcs', 'Pantry Shelf', 2),
      item('demo_cumin', 'Cumin', 80, 'g', 'Spice Rack', 30),
      item('demo_turmeric', 'Turmeric', 45, 'g', 'Spice Rack', 30),
    ];
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

  Future<void> ingestReceiptItems({
    required String householdId,
    required List<ValidatedReceiptItem> items,
    String? storeName,
    String? receiptDate,
    double? receiptTotal,
    String? receiptHash,
  }) async {
    final scopeId = _householdId ?? householdId;
    final now = DateTime.now();

    for (final scanned in items.where((i) => i.isSelected)) {
      // 1. Record purchase event in the ledger (source="receipt")
      final event = {
        'id': _uuid.v4(),
        'household_id': scopeId,
        'item_name': scanned.name,
        'matched_ingredient': scanned.matchedIngredient,
        'quantity': scanned.totalQty,
        'unit': scanned.unit,
        'price': scanned.linePrice,
        'type': 'purchase',
        'source': 'receipt',
        'timestamp': now.toIso8601String(),
        'store_name': storeName,
        'receipt_date': receiptDate,
        'receipt_total': receiptTotal,
        'receipt_hash': receiptHash,
      };
      unawaited(_service.recordLedgerEvent(scopeId, event));

      // 2. Update pantry items
      final targetName = scanned.matchedIngredient.isNotEmpty
          ? scanned.matchedIngredient
          : scanned.name;
      final normName = targetName.toLowerCase().trim();
      final zone = scanned.storageZone;

      final existingIndex = _items.indexWhere(
        (it) => it.name.toLowerCase().trim() == normName && it.location == zone,
      );

      if (existingIndex != -1) {
        final existing = _items[existingIndex];
        final updated = existing.copyWith(
          quantity: existing.quantity + scanned.totalQty,
          updatedAt: now,
        );
        _items[existingIndex] = updated;
        _persistAndSync(updated);
      } else {
        final newItem = PantryItemModel(
          id: _uuid.v4(),
          householdId: scopeId,
          name: targetName,
          quantity: scanned.totalQty,
          unit: scanned.unit,
          location: zone,
          lowStockThreshold: _defaultThreshold(scanned.unit),
          addedVia: 'receipt_scan',
          updatedAt: now,
        );
        _items.add(newItem);
        _persistAndSync(newItem);
      }
    }
    notifyListeners();
  }

  double _defaultThreshold(String unit) {
    final u = unit.toLowerCase();
    if (u == 'kg' || u == 'l') return 0.5;
    if (u == 'pcs') return 2;
    if (u == 'g' || u == 'ml') return 50;
    return 1;
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
