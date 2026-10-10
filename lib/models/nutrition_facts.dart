class NutritionFacts {
  final double calories;
  final double proteinGrams;
  final double carbohydrateGrams;
  final double fatGrams;
  final double fiberGrams;

  const NutritionFacts({
    this.calories = 0,
    this.proteinGrams = 0,
    this.carbohydrateGrams = 0,
    this.fatGrams = 0,
    this.fiberGrams = 0,
  });

  NutritionFacts operator +(NutritionFacts other) => NutritionFacts(
    calories: calories + other.calories,
    proteinGrams: proteinGrams + other.proteinGrams,
    carbohydrateGrams: carbohydrateGrams + other.carbohydrateGrams,
    fatGrams: fatGrams + other.fatGrams,
    fiberGrams: fiberGrams + other.fiberGrams,
  );

  NutritionFacts scale(double factor) => NutritionFacts(
    calories: calories * factor,
    proteinGrams: proteinGrams * factor,
    carbohydrateGrams: carbohydrateGrams * factor,
    fatGrams: fatGrams * factor,
    fiberGrams: fiberGrams * factor,
  );
}
