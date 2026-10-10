class RecipeIngredient {
  final String name;
  final double quantity;
  final String unit;

  const RecipeIngredient({
    required this.name,
    required this.quantity,
    required this.unit,
  });

  RecipeIngredient scale(double factor) =>
      RecipeIngredient(name: name, quantity: quantity * factor, unit: unit);
}
