import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import '../models/pantry_item_model.dart';

class PantryProvider extends ChangeNotifier {
  static const _uuid = Uuid();

  // Storage zones
  static const List<String> zones = [
    'Fridge',
    'Freezer',
    'Pantry Shelf',
    'Spice Rack',
  ];

  // Units
  static const List<String> units = [
    'pcs', 'g', 'kg', 'ml', 'L', 'cups', 'tbsp', 'tsp', 'dozen',
  ];

  final List<PantryItemModel> _items = [
    PantryItemModel(
      id: '1', householdId: 'hh_demo', name: 'Whole Milk',
      quantity: 2.0, unit: 'L', location: 'Fridge',
      lowStockThreshold: 0.5, updatedAt: DateTime.now(),
    ),
    PantryItemModel(
      id: '2', householdId: 'hh_demo', name: 'Eggs',
      quantity: 6, unit: 'pcs', location: 'Fridge',
      lowStockThreshold: 4, updatedAt: DateTime.now(),
    ),
    PantryItemModel(
      id: '3', householdId: 'hh_demo', name: 'Greek Yogurt',
      quantity: 1.0, unit: 'kg', location: 'Fridge',
      lowStockThreshold: 0.2, updatedAt: DateTime.now(),
    ),
    PantryItemModel(
      id: '4', householdId: 'hh_demo', name: 'Cheddar Cheese',
      quantity: 250, unit: 'g', location: 'Fridge',
      lowStockThreshold: 100, updatedAt: DateTime.now(),
    ),
    PantryItemModel(
      id: '5', householdId: 'hh_demo', name: 'Chicken Breast',
      quantity: 500, unit: 'g', location: 'Freezer',
      lowStockThreshold: 200, updatedAt: DateTime.now(),
    ),
    PantryItemModel(
      id: '6', householdId: 'hh_demo', name: 'Frozen Peas',
      quantity: 300, unit: 'g', location: 'Freezer',
      lowStockThreshold: 100, updatedAt: DateTime.now(),
    ),
    PantryItemModel(
      id: '7', householdId: 'hh_demo', name: 'Ice Cream',
      quantity: 0.5, unit: 'L', location: 'Freezer',
      lowStockThreshold: 0.3, updatedAt: DateTime.now(),
    ),
    PantryItemModel(
      id: '8', householdId: 'hh_demo', name: 'Basmati Rice',
      quantity: 2.5, unit: 'kg', location: 'Pantry Shelf',
      lowStockThreshold: 0.5, updatedAt: DateTime.now(),
    ),
    PantryItemModel(
      id: '9', householdId: 'hh_demo', name: 'Cooking Oil',
      quantity: 0.3, unit: 'L', location: 'Pantry Shelf',
      lowStockThreshold: 0.5, updatedAt: DateTime.now(),
    ),
    PantryItemModel(
      id: '10', householdId: 'hh_demo', name: 'Garlic Cloves',
      quantity: 8, unit: 'pcs', location: 'Pantry Shelf',
      lowStockThreshold: 4, updatedAt: DateTime.now(),
    ),
    PantryItemModel(
      id: '11', householdId: 'hh_demo', name: 'Lentils (Masoor Dal)',
      quantity: 1.0, unit: 'kg', location: 'Pantry Shelf',
      lowStockThreshold: 0.2, updatedAt: DateTime.now(),
    ),
    PantryItemModel(
      id: '12', householdId: 'hh_demo', name: 'Cumin Seeds',
      quantity: 50, unit: 'g', location: 'Spice Rack',
      lowStockThreshold: 15, updatedAt: DateTime.now(),
    ),
    PantryItemModel(
      id: '13', householdId: 'hh_demo', name: 'Turmeric Powder',
      quantity: 15, unit: 'g', location: 'Spice Rack',
      lowStockThreshold: 20, updatedAt: DateTime.now(),
    ),
    PantryItemModel(
      id: '14', householdId: 'hh_demo', name: 'Red Chili Powder',
      quantity: 60, unit: 'g', location: 'Spice Rack',
      lowStockThreshold: 20, updatedAt: DateTime.now(),
    ),
    PantryItemModel(
      id: '15', householdId: 'hh_demo', name: 'Garam Masala',
      quantity: 8, unit: 'g', location: 'Spice Rack',
      lowStockThreshold: 15, updatedAt: DateTime.now(),
    ),
  ];

  String _searchQuery = '';
  String? _selectedZone; // null = all zones

  // ── Getters ────────────────────────────────────────────────────────────────

  String get searchQuery => _searchQuery;
  String? get selectedZone => _selectedZone;

  List<PantryItemModel> get allItems => List.unmodifiable(_items);

  List<PantryItemModel> get filteredItems {
    return _items.where((item) {
      final matchesZone = _selectedZone == null || item.location == _selectedZone;
      final matchesSearch = _searchQuery.isEmpty ||
          item.name.toLowerCase().contains(_searchQuery.toLowerCase());
      return matchesZone && matchesSearch;
    }).toList()
      ..sort((a, b) => a.name.compareTo(b.name));
  }

  /// Items grouped by zone, respecting active filters.
  Map<String, List<PantryItemModel>> get itemsByZone {
    final filtered = filteredItems;
    final Map<String, List<PantryItemModel>> grouped = {};
    for (final zone in zones) {
      final zoneItems = filtered.where((i) => i.location == zone).toList()
        ..sort((a, b) => a.name.compareTo(b.name));
      if (zoneItems.isNotEmpty) {
        grouped[zone] = zoneItems;
      }
    }
    return grouped;
  }

  int get totalCount => _items.length;

  int get lowStockCount => _items.where((i) => i.isLowStock).length;

  // ── Search & Filter ────────────────────────────────────────────────────────

  void setSearch(String query) {
    _searchQuery = query;
    notifyListeners();
  }

  void setZoneFilter(String? zone) {
    _selectedZone = zone;
    notifyListeners();
  }

  // ── CRUD ───────────────────────────────────────────────────────────────────

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
    final item = PantryItemModel(
      id: _uuid.v4(),
      householdId: householdId,
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
    notifyListeners();
  }

  void updateItem(PantryItemModel updated) {
    final idx = _items.indexWhere((i) => i.id == updated.id);
    if (idx == -1) return;
    _items[idx] = updated.copyWith(updatedAt: DateTime.now());
    notifyListeners();
  }

  void deleteItem(String id) {
    _items.removeWhere((i) => i.id == id);
    notifyListeners();
  }

  void adjustQuantity(String id, double delta) {
    final idx = _items.indexWhere((i) => i.id == id);
    if (idx == -1) return;
    final current = _items[idx];
    final newQty = (current.quantity + delta).clamp(0.0, double.infinity).toDouble();
    _items[idx] = current.copyWith(quantity: newQty, updatedAt: DateTime.now());
    notifyListeners();
  }
}
