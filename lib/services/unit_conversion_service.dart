class UnitConversionService {
  const UnitConversionService._();

  static double toGrams(
    double quantity,
    String unit, {
    double gramsPerPiece = 100,
    double gramsPerMilliliter = 1,
  }) {
    final normalized = unit.trim().toLowerCase();
    return switch (normalized) {
      'g' || 'gram' || 'grams' => quantity,
      'kg' || 'kilogram' || 'kilograms' => quantity * 1000,
      'ml' || 'milliliter' || 'milliliters' => quantity * gramsPerMilliliter,
      'l' ||
      'litre' ||
      'litres' ||
      'liter' ||
      'liters' => quantity * 1000 * gramsPerMilliliter,
      'cup' || 'cups' => quantity * 240 * gramsPerMilliliter,
      'tbsp' ||
      'tablespoon' ||
      'tablespoons' => quantity * 15 * gramsPerMilliliter,
      'tsp' || 'teaspoon' || 'teaspoons' => quantity * 5 * gramsPerMilliliter,
      'dozen' => quantity * 12 * gramsPerPiece,
      'pc' ||
      'pcs' ||
      'piece' ||
      'pieces' ||
      'clove' ||
      'cloves' => quantity * gramsPerPiece,
      _ => quantity * gramsPerPiece,
    };
  }

  static double convertMass(double quantity, String from, String to) {
    final grams = toGrams(quantity, from);
    final target = to.trim().toLowerCase();
    return switch (target) {
      'kg' || 'kilogram' || 'kilograms' => grams / 1000,
      'g' || 'gram' || 'grams' => grams,
      _ => throw ArgumentError('Unsupported mass unit: $to'),
    };
  }
}
