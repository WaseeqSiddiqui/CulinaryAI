import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../models/fridge_vision_models.dart';
import '../models/pantry_item_model.dart';
import '../models/receipt_vision_models.dart';
import '../services/pantry_service.dart';
import '../services/pantry_zone_resolver.dart';
import '../services/expiry_estimation_service.dart';

enum PantryExpiryFilter { all, useSoon, expired, estimated }

class PantryProvider extends ChangeNotifier {
  PantryProvider({PantryService? service})
    : _service = service ?? PantryService();

  static const _uuid = Uuid();
  static const List<String> zones = PantryZoneResolver.zones;
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
  PantryExpiryFilter _expiryFilter = PantryExpiryFilter.all;
  bool _isLoading = false;
  bool _hasLoaded = false;
  bool _receivedRemoteSnapshot = false;
  String? _errorMessage;

  String get searchQuery => _searchQuery;
  String? get selectedZone => _selectedZone;
  PantryExpiryFilter get expiryFilter => _expiryFilter;
  String? get householdId => _householdId;
  bool get isLoading => _isLoading;
  bool get hasLoaded => _hasLoaded;
  String? get errorMessage => _errorMessage;
  List<PantryItemModel> get allItems => List.unmodifiable(_items);

  List<PantryItemModel> get filteredItems {
    return _items.where((item) {
      final matchesZone =
          _selectedZone == null || item.location == _selectedZone;
      final matchesSearch =
          _searchQuery.isEmpty ||
          item.name.toLowerCase().contains(_searchQuery.toLowerCase());
      final matchesExpiry = switch (_expiryFilter) {
        PantryExpiryFilter.all => true,
        PantryExpiryFilter.useSoon => item.expiryStatus == ExpiryStatus.useSoon,
        PantryExpiryFilter.expired => item.expiryStatus == ExpiryStatus.expired,
        PantryExpiryFilter.estimated => item.hasEstimatedExpiry,
      };
      return matchesZone && matchesSearch && matchesExpiry;
    }).toList()..sort((a, b) {
      final aDays = a.daysUntilExpiry ?? 100000;
      final bDays = b.daysUntilExpiry ?? 100000;
      final expiryOrder = aDays.compareTo(bDays);
      return expiryOrder != 0 ? expiryOrder : a.name.compareTo(b.name);
    });
  }

  Map<String, List<PantryItemModel>> get itemsByZone {
    return _groupByZone(filteredItems);
  }

  Map<String, List<PantryItemModel>> get allItemsByZone {
    return _groupByZone(_items);
  }

  Map<String, List<PantryItemModel>> _groupByZone(
    Iterable<PantryItemModel> source,
  ) {
    final grouped = <String, List<PantryItemModel>>{};
    for (final zone in zones) {
      final zoneItems = source.where((item) => item.location == zone).toList();
      if (zoneItems.isNotEmpty) grouped[zone] = zoneItems;
    }
    return grouped;
  }

  int get totalCount => _items.length;
  int get lowStockCount => _items.where((item) => item.isLowStock).length;
  int get useSoonCount =>
      _items.where((item) => item.expiryStatus == ExpiryStatus.useSoon).length;
  int get expiredCount =>
      _items.where((item) => item.expiryStatus == ExpiryStatus.expired).length;

  void bindHousehold(String? householdId) {
    if (_householdId == householdId) return;
    _householdId = householdId;
    _items.clear();
    _subscription?.cancel();
    _subscription = null;
    _hasLoaded = false;
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
    final loadedItems = await _service.loadLocal(householdId);
    final localItems = _canonicalizeStoredItems(loadedItems);
    if (_householdId != householdId) return;
    _items
      ..clear()
      ..addAll(localItems);
    await _saveZoneCorrections(householdId, loadedItems, localItems);
    if (_items.isEmpty && householdId == 'personal_demo_chef') {
      _items.addAll(_demoPantry(householdId));
      await _service.saveLocal(householdId, _items);
    }
    _isLoading = false;
    _hasLoaded = true;
    notifyListeners();

    _subscription = _service
        .watch(householdId)
        .listen(
          (remoteItems) async {
            if (_householdId != householdId) return;
            final canonicalItems = _canonicalizeStoredItems(remoteItems);
            if (!_receivedRemoteSnapshot &&
                canonicalItems.isEmpty &&
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
              ..addAll(canonicalItems);
            await _service.saveLocal(householdId, _items);
            await _saveZoneCorrections(
              householdId,
              remoteItems,
              canonicalItems,
              saveLocal: false,
            );
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
    _selectedZone = zone == null ? null : PantryZoneResolver.normalize(zone);
    notifyListeners();
  }

  void setExpiryFilter(PantryExpiryFilter value) {
    _expiryFilter = value;
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
    DateTime? purchaseDate,
    DateTime? expiryDate,
    DateTime? openedDate,
    ExpirySource expirySource = ExpirySource.unknown,
    ExpiryConfidence expiryConfidence = ExpiryConfidence.low,
    bool expiryUserConfirmed = false,
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
      purchaseDate: purchaseDate,
      expiryDate: expiryDate,
      openedDate: openedDate,
      expirySource: expirySource,
      expiryConfidence: expiryConfidence,
      expiryUserConfirmed: expiryUserConfirmed,
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
    final purchasedAt = receiptDate == null
        ? now
        : DateTime.tryParse(receiptDate) ?? now;

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
      final zone = PantryZoneResolver.resolveForItem(
        targetName,
        suggestedZone: scanned.storageZone,
      );
      final estimate = ExpiryEstimationService.estimate(
        itemName: targetName,
        storageZone: zone,
        purchasedAt: purchasedAt,
      );

      var existingIndex = _items.indexWhere(
        (it) => it.name.toLowerCase().trim() == normName && it.location == zone,
      );
      if (existingIndex == -1) {
        existingIndex = _items.indexWhere(
          (it) =>
              it.name.toLowerCase().trim() == normName &&
              it.addedVia == 'receipt_scan',
        );
      }

      if (existingIndex != -1) {
        final existing = _items[existingIndex];
        final updated = existing.copyWith(
          quantity: existing.quantity + scanned.totalQty,
          location: existing.addedVia == 'receipt_scan'
              ? zone
              : existing.location,
          updatedAt: now,
          purchaseDate: purchasedAt,
          expiryDate: _preferredExpiry(existing, estimate),
          expirySource: existing.expiryUserConfirmed || estimate == null
              ? existing.expirySource
              : ExpirySource.receiptEstimate,
          expiryConfidence: existing.expiryUserConfirmed || estimate == null
              ? existing.expiryConfidence
              : estimate.confidence,
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
          purchaseDate: purchasedAt,
          expiryDate: estimate?.date,
          expirySource: estimate == null
              ? ExpirySource.unknown
              : ExpirySource.receiptEstimate,
          expiryConfidence: estimate?.confidence ?? ExpiryConfidence.low,
        );
        _items.add(newItem);
        _persistAndSync(newItem);
      }
    }
    notifyListeners();
  }

  DateTime? _preferredExpiry(
    PantryItemModel existing,
    ExpiryEstimate? estimate,
  ) {
    if (existing.expiryUserConfirmed || estimate == null) {
      return existing.expiryDate;
    }
    final current = existing.expiryDate;
    if (current == null || estimate.date.isBefore(current)) {
      return estimate.date;
    }
    return current;
  }

  Future<void> reconcileFridgeItems({
    required String householdId,
    required List<ReconciledFridgeItem> reconciledItems,
  }) async {
    final scopeId = _householdId ?? householdId;
    final now = DateTime.now();

    for (final item in reconciledItems) {
      if (!item.isAccepted) continue;

      if (item.status == 'mismatch') {
        // Find existing pantry item by ID or name
        final index = _items.indexWhere(
          (it) =>
              it.id == item.matchedPantryId ||
              it.name.toLowerCase() == item.detectedName.toLowerCase(),
        );
        if (index != -1 && item.suggestedQuantity != null) {
          final existing = _items[index];
          final estimate = existing.expiryDate == null
              ? ExpiryEstimationService.estimate(
                  itemName: existing.name,
                  storageZone: existing.location,
                  purchasedAt: now,
                )
              : null;
          final updated = existing.copyWith(
            quantity: item.suggestedQuantity!,
            estimated: true,
            updatedAt: now,
            expiryDate: estimate?.date ?? existing.expiryDate,
            expirySource: estimate == null
                ? existing.expirySource
                : ExpirySource.receiptEstimate,
            expiryConfidence: estimate?.confidence ?? existing.expiryConfidence,
          );
          _items[index] = updated;
          _persistAndSync(updated);
        }
      } else if (item.status == 'new_item') {
        final targetName = item.matchedName ?? item.detectedName;
        final expiry = ExpiryEstimationService.estimate(
          itemName: targetName,
          storageZone: 'Fridge',
          purchasedAt: now,
        );
        final newItem = PantryItemModel(
          id: _uuid.v4(),
          householdId: scopeId,
          name: targetName,
          quantity: item.suggestedQuantity ?? 1.0,
          unit: item.unit,
          location: 'Fridge',
          lowStockThreshold: _defaultThreshold(item.unit),
          addedVia: 'fridge_scan',
          estimated: true,
          updatedAt: now,
          purchaseDate: now,
          expiryDate: expiry?.date,
          expirySource: expiry == null
              ? ExpirySource.unknown
              : ExpirySource.receiptEstimate,
          expiryConfidence: expiry?.confidence ?? ExpiryConfidence.low,
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

  List<PantryItemModel> _canonicalizeStoredItems(
    Iterable<PantryItemModel> items,
  ) {
    return items.map((item) {
      final canonicalZone = item.addedVia == 'receipt_scan'
          ? PantryZoneResolver.resolveForItem(
              item.name,
              suggestedZone: item.location,
            )
          : PantryZoneResolver.normalize(item.location);
      return canonicalZone == item.location
          ? item
          : item.copyWith(location: canonicalZone);
    }).toList();
  }

  Future<void> _saveZoneCorrections(
    String householdId,
    List<PantryItemModel> original,
    List<PantryItemModel> canonical, {
    bool saveLocal = true,
  }) async {
    final originalById = {for (final item in original) item.id: item};
    final corrected = canonical.where(
      (item) => originalById[item.id]?.location != item.location,
    );
    if (corrected.isEmpty) return;
    if (saveLocal) {
      await _service.saveLocal(householdId, canonical);
    }
    for (final item in corrected) {
      unawaited(_service.upsert(item));
    }
  }

  void updateItem(PantryItemModel updated) {
    final index = _items.indexWhere((item) => item.id == updated.id);
    if (index == -1) return;
    final previous = _items[index];
    final item = updated.copyWith(
      householdId: _householdId ?? updated.householdId,
      addedVia: previous.location == updated.location
          ? updated.addedVia
          : 'manual',
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
