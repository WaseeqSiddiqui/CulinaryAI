import '../models/pantry_item_model.dart';
import '../models/recipe_ingredient.dart';

enum InventoryUnitDimension { mass, volume, count, unknown }

class PantryAllocation {
  final PantryItemModel item;
  final double amountInPantryUnit;

  const PantryAllocation({
    required this.item,
    required this.amountInPantryUnit,
  });
}

class IngredientAvailability {
  final RecipeIngredient ingredient;
  final double availableInRecipeUnit;
  final List<PantryAllocation> allocations;
  final bool hasAmbiguousPackage;

  const IngredientAvailability({
    required this.ingredient,
    required this.availableInRecipeUnit,
    required this.allocations,
    required this.hasAmbiguousPackage,
  });

  bool get isSufficient =>
      availableInRecipeUnit + 0.000001 >= ingredient.quantity;
  double get shortage =>
      (ingredient.quantity - availableInRecipeUnit).clamp(0, double.infinity);
}

/// Converts only compatible units. Cross mass/volume conversions are allowed
/// solely for ingredients with an explicit density; unknown package capacities
/// are intentionally never guessed.
class InventoryQuantityService {
  const InventoryQuantityService._();

  static const Map<String, double> _gramsPerMilliliter = {
    'milk': 1.03,
    'olive oil': 0.91,
    'cooking oil': 0.92,
    'oil': 0.92,
    'mustard sauce': 1.02,
    'soy sauce': 1.16,
    'vinegar': 1.01,
    'heavy cream': 0.99,
  };

  static const Map<String, double> _gramsPerPiece = {
    'egg': 50,
    'eggs': 50,
    'garlic': 3,
    'garlic cloves': 3,
    'tomato': 120,
    'tomatoes': 120,
    'onion': 110,
    'onions': 110,
    'lemon': 58,
    'bread': 38,
  };

  static InventoryUnitDimension dimension(String unit) {
    final value = _unit(unit);
    if (const {'g', 'kg'}.contains(value)) {
      return InventoryUnitDimension.mass;
    }
    if (const {'ml', 'l', 'tsp', 'tbsp', 'cup'}.contains(value)) {
      return InventoryUnitDimension.volume;
    }
    if (const {'pcs', 'dozen'}.contains(value)) {
      return InventoryUnitDimension.count;
    }
    return InventoryUnitDimension.unknown;
  }

  static double? convert({
    required double quantity,
    required String fromUnit,
    required String toUnit,
    required String ingredientName,
  }) {
    final from = _unit(fromUnit);
    final to = _unit(toUnit);
    if (from == to) return quantity;
    final fromDimension = dimension(from);
    final toDimension = dimension(to);
    if (fromDimension == InventoryUnitDimension.unknown ||
        toDimension == InventoryUnitDimension.unknown) {
      return null;
    }

    if (fromDimension == toDimension) {
      final base = _toBase(quantity, from);
      return base == null ? null : _fromBase(base, to);
    }

    final density = _specificValue(_gramsPerMilliliter, ingredientName);
    if ({fromDimension, toDimension}.contains(InventoryUnitDimension.mass) &&
        {fromDimension, toDimension}.contains(InventoryUnitDimension.volume) &&
        density != null) {
      final base = _toBase(quantity, from);
      if (base == null) return null;
      final convertedBase = fromDimension == InventoryUnitDimension.mass
          ? base / density
          : base * density;
      return _fromBase(convertedBase, to);
    }

    final gramsPerPiece = _specificValue(_gramsPerPiece, ingredientName);
    if ({fromDimension, toDimension}.contains(InventoryUnitDimension.mass) &&
        {fromDimension, toDimension}.contains(InventoryUnitDimension.count) &&
        gramsPerPiece != null) {
      final base = _toBase(quantity, from);
      if (base == null) return null;
      final convertedBase = fromDimension == InventoryUnitDimension.mass
          ? base / gramsPerPiece
          : base * gramsPerPiece;
      return _fromBase(convertedBase, to);
    }
    return null;
  }

  static IngredientAvailability availability(
    RecipeIngredient ingredient,
    Iterable<PantryItemModel> pantryItems,
  ) {
    final matches =
        pantryItems
            .where(
              (item) =>
                  item.quantity > 0 &&
                  item.expiryStatus != ExpiryStatus.expired &&
                  namesMatch(ingredient.name, item.name),
            )
            .toList()
          ..sort((left, right) {
            if (left.isOpened != right.isOpened) return left.isOpened ? -1 : 1;
            final leftExpiry = left.expiryDate ?? DateTime(9999);
            final rightExpiry = right.expiryDate ?? DateTime(9999);
            return leftExpiry.compareTo(rightExpiry);
          });

    var available = 0.0;
    var remaining = ingredient.quantity;
    var ambiguous = false;
    final allocations = <PantryAllocation>[];
    for (final item in matches) {
      if (item.needsPackageDetails) {
        ambiguous = true;
      }
      final inRecipeUnit = convert(
        quantity: item.quantity,
        fromUnit: item.unit,
        toUnit: ingredient.unit,
        ingredientName: ingredient.name,
      );
      if (inRecipeUnit == null) continue;
      available += inRecipeUnit;
      if (remaining <= 0) continue;
      final useInRecipeUnit = remaining.clamp(0, inRecipeUnit).toDouble();
      final useInPantryUnit = convert(
        quantity: useInRecipeUnit,
        fromUnit: ingredient.unit,
        toUnit: item.unit,
        ingredientName: ingredient.name,
      );
      if (useInPantryUnit == null) continue;
      allocations.add(
        PantryAllocation(item: item, amountInPantryUnit: useInPantryUnit),
      );
      remaining -= useInRecipeUnit;
    }
    return IngredientAvailability(
      ingredient: ingredient,
      availableInRecipeUnit: available,
      allocations: allocations,
      hasAmbiguousPackage: ambiguous,
    );
  }

  static bool namesMatch(String left, String right) {
    final a = _name(left);
    final b = _name(right);
    if (a == b || a.contains(b) || b.contains(a)) return true;
    final aWords = a.split(' ').where((word) => word.length > 2).toSet();
    final bWords = b.split(' ').where((word) => word.length > 2).toSet();
    return aWords.intersection(bWords).isNotEmpty;
  }

  static double? _toBase(double quantity, String unit) => switch (_unit(unit)) {
    'g' || 'ml' || 'pcs' => quantity,
    'kg' || 'l' => quantity * 1000,
    'tsp' => quantity * 5,
    'tbsp' => quantity * 15,
    'cup' => quantity * 240,
    'dozen' => quantity * 12,
    _ => null,
  };

  static double? _fromBase(double quantity, String unit) =>
      switch (_unit(unit)) {
        'g' || 'ml' || 'pcs' => quantity,
        'kg' || 'l' => quantity / 1000,
        'tsp' => quantity / 5,
        'tbsp' => quantity / 15,
        'cup' => quantity / 240,
        'dozen' => quantity / 12,
        _ => null,
      };

  static double? _specificValue(Map<String, double> values, String name) {
    final normalized = _name(name);
    for (final entry in values.entries) {
      if (normalized == entry.key ||
          normalized.contains(entry.key) ||
          entry.key.contains(normalized)) {
        return entry.value;
      }
    }
    return null;
  }

  static String _unit(String value) => switch (value.trim().toLowerCase()) {
    'gram' || 'grams' => 'g',
    'kilogram' || 'kilograms' => 'kg',
    'milliliter' || 'milliliters' || 'millilitre' || 'millilitres' => 'ml',
    'liter' || 'liters' || 'litre' || 'litres' => 'l',
    'teaspoon' || 'teaspoons' => 'tsp',
    'tablespoon' || 'tablespoons' => 'tbsp',
    'cups' => 'cup',
    'pc' || 'piece' || 'pieces' || 'clove' || 'cloves' => 'pcs',
    _ => value.trim().toLowerCase(),
  };

  static String _name(String value) => value
      .trim()
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9 ]'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ');
}
