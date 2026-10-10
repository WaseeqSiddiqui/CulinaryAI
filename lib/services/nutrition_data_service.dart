import '../models/nutrition_facts.dart';

class NutritionReference {
  final List<String> aliases;
  final NutritionFacts per100Grams;
  final double gramsPerPiece;
  final double gramsPerMilliliter;

  const NutritionReference({
    required this.aliases,
    required this.per100Grams,
    this.gramsPerPiece = 100,
    this.gramsPerMilliliter = 1,
  });
}

class NutritionDataService {
  const NutritionDataService._();

  static const references = <NutritionReference>[
    NutritionReference(
      aliases: ['chicken', 'chicken breast'],
      per100Grams: NutritionFacts(
        calories: 165,
        proteinGrams: 31,
        fatGrams: 3.6,
      ),
    ),
    NutritionReference(
      aliases: ['rice', 'basmati rice'],
      per100Grams: NutritionFacts(
        calories: 130,
        proteinGrams: 2.7,
        carbohydrateGrams: 28,
        fatGrams: 0.3,
        fiberGrams: 0.4,
      ),
    ),
    NutritionReference(
      aliases: ['garlic', 'garlic cloves'],
      per100Grams: NutritionFacts(
        calories: 149,
        proteinGrams: 6.4,
        carbohydrateGrams: 33.1,
        fatGrams: 0.5,
        fiberGrams: 2.1,
      ),
      gramsPerPiece: 3,
    ),
    NutritionReference(
      aliases: ['olive oil', 'oil'],
      per100Grams: NutritionFacts(calories: 884, fatGrams: 100),
      gramsPerMilliliter: 0.91,
    ),
    NutritionReference(
      aliases: ['pasta'],
      per100Grams: NutritionFacts(
        calories: 371,
        proteinGrams: 13,
        carbohydrateGrams: 75,
        fatGrams: 1.5,
        fiberGrams: 3.2,
      ),
    ),
    NutritionReference(
      aliases: ['tomato', 'tomatoes'],
      per100Grams: NutritionFacts(
        calories: 18,
        proteinGrams: 0.9,
        carbohydrateGrams: 3.9,
        fatGrams: 0.2,
        fiberGrams: 1.2,
      ),
      gramsPerPiece: 120,
    ),
    NutritionReference(
      aliases: ['cheese', 'cheddar', 'parmesan'],
      per100Grams: NutritionFacts(
        calories: 402,
        proteinGrams: 25,
        carbohydrateGrams: 1.3,
        fatGrams: 33,
      ),
    ),
    NutritionReference(
      aliases: ['egg', 'eggs'],
      per100Grams: NutritionFacts(
        calories: 143,
        proteinGrams: 12.6,
        carbohydrateGrams: 0.7,
        fatGrams: 9.5,
      ),
      gramsPerPiece: 50,
    ),
    NutritionReference(
      aliases: ['milk'],
      per100Grams: NutritionFacts(
        calories: 61,
        proteinGrams: 3.2,
        carbohydrateGrams: 4.8,
        fatGrams: 3.3,
      ),
      gramsPerMilliliter: 1.03,
    ),
    NutritionReference(
      aliases: ['onion', 'onions'],
      per100Grams: NutritionFacts(
        calories: 40,
        proteinGrams: 1.1,
        carbohydrateGrams: 9.3,
        fatGrams: 0.1,
        fiberGrams: 1.7,
      ),
      gramsPerPiece: 110,
    ),
    NutritionReference(
      aliases: ['cumin'],
      per100Grams: NutritionFacts(
        calories: 375,
        proteinGrams: 17.8,
        carbohydrateGrams: 44.2,
        fatGrams: 22.3,
        fiberGrams: 10.5,
      ),
    ),
    NutritionReference(
      aliases: ['lentil', 'lentils', 'dal'],
      per100Grams: NutritionFacts(
        calories: 353,
        proteinGrams: 25.8,
        carbohydrateGrams: 60.1,
        fatGrams: 1.1,
        fiberGrams: 10.7,
      ),
    ),
    NutritionReference(
      aliases: ['fish', 'salmon'],
      per100Grams: NutritionFacts(
        calories: 208,
        proteinGrams: 20,
        fatGrams: 13,
      ),
    ),
    NutritionReference(
      aliases: ['peas'],
      per100Grams: NutritionFacts(
        calories: 81,
        proteinGrams: 5.4,
        carbohydrateGrams: 14.5,
        fatGrams: 0.4,
        fiberGrams: 5.1,
      ),
    ),
    NutritionReference(
      aliases: ['bread', 'sourdough'],
      per100Grams: NutritionFacts(
        calories: 265,
        proteinGrams: 9,
        carbohydrateGrams: 49,
        fatGrams: 3.2,
        fiberGrams: 2.7,
      ),
      gramsPerPiece: 38,
    ),
    NutritionReference(
      aliases: ['butter'],
      per100Grams: NutritionFacts(
        calories: 717,
        proteinGrams: 0.9,
        carbohydrateGrams: 0.1,
        fatGrams: 81.1,
      ),
    ),
  ];

  static NutritionReference? find(String ingredientName) {
    final name = ingredientName.trim().toLowerCase();
    for (final reference in references) {
      if (reference.aliases.any(
        (alias) => name.contains(alias) || alias.contains(name),
      )) {
        return reference;
      }
    }
    return null;
  }
}
