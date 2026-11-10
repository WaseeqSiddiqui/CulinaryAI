import 'dart:math' as math;

import '../models/shopping_models.dart';
import '../models/store_models.dart';
import 'grocery_query_normalizer.dart';

/// A conservative fast path for literal ingredient names and printed pack sizes.
/// Unclear forms, quantities and multipacks are left for review or the online matcher.
class ExactProductMatcher {
  static ProductMatch? match(
    ShoppingListItem wanted,
    List<ProductCandidate> candidates,
  ) {
    if (!wanted.quantity.isFinite || wanted.quantity <= 0) return null;
    final wantedTokens = _tokens(wanted.name);
    if (wantedTokens.isEmpty) return null;
    final requestedUnit = _unit(wanted.unit);
    if (requestedUnit == null) return null;
    final requested = wanted.quantity * requestedUnit.$2;
    final requestedSizes = _sizes(wanted.name);
    final choices = <({int index, int units, double excess, double cost})>[];
    for (final (index, candidate) in candidates.indexed) {
      if (!candidate.inStock ||
          !candidate.price.isFinite ||
          candidate.price <= 0) {
        continue;
      }
      final name = candidate.name;
      final tokens = _tokens(name);
      if (!wantedTokens.every(tokens.contains) ||
          !GroceryQueryNormalizer.isSafeNormalization(wanted.name, name) ||
          !GroceryQueryNormalizer.isSafeNormalization(name, wanted.name)) {
        continue;
      }
      final extraForms = tokens.difference(wantedTokens).intersection(_forms);
      if (extraForms.isNotEmpty) continue;
      final orderedTokens = RegExp(r'[a-z]+')
          .allMatches(name.toLowerCase())
          .map((m) => _canonicalToken(m.group(0)!))
          .toList();
      final lastIngredientToken = orderedTokens.lastIndexWhere(
        wantedTokens.contains,
      );
      if (orderedTokens
          .skip(lastIngredientToken + 1)
          .any((t) => !_packageTokens.contains(t))) {
        continue;
      }
      final label = '${candidate.size ?? ''} $name';
      if (RegExp(r'\d\s*[x×]\s*\d', caseSensitive: false).hasMatch(label)) {
        continue;
      }
      final sizes = _sizes(label);
      if (sizes.length > 1) continue;
      if (requestedSizes.isNotEmpty && !requestedSizes.every(sizes.contains)) {
        continue;
      }
      final size = sizes.firstOrNull;
      double capacity;
      if (requestedUnit.$1 == 'count' && (size == null || size.$1 != 'count')) {
        // A piece of loose produce is not a bag by weight. Only packaged pantry
        // goods use the customary shopping-list meaning of one retail unit.
        if (size == null ||
            !_retailPackageGroceries.any(wantedTokens.contains)) {
          continue;
        }
        capacity = 1;
      } else {
        if (size == null || size.$1 != requestedUnit.$1 || size.$2 <= 0) {
          continue;
        }
        capacity = size.$2;
      }
      final units = (requested / capacity - 1e-9).ceil();
      if (units < 1 || units > 10 || units * capacity > requested * 2) continue;
      choices.add((
        index: index,
        units: units,
        excess: math.max(0, units * capacity - requested),
        cost: units * candidate.price,
      ));
    }
    choices.sort((a, b) {
      final excess = a.excess.compareTo(b.excess);
      return excess != 0 ? excess : a.cost.compareTo(b.cost);
    });
    if (choices.isEmpty) return null;
    final best = choices.first;
    return ProductMatch(
      chosenIndex: best.index,
      unitsToBuy: best.units,
      confidence: .98,
      reason: 'Exact ingredient name and printed package quantity verified locally.',
    );
  }

  static Set<String> _tokens(String text) =>
      RegExp(r'[a-z]+')
          .allMatches(text.toLowerCase())
          .map((m) => m.group(0)!)
          .map(_canonicalToken)
          .toSet();

  static String _canonicalToken(String token) {
    if (token == 'soya') return 'soy';
    return token.endsWith('s') && token.length > 3
        ? token.substring(0, token.length - 1)
        : token;
  }

  static const _packageTokens = {
    'g',
    'gm',
    'kg',
    'l',
    'ml',
    'pc',
    'pcs',
    'piece',
    'count',
    'ct',
    'pack',
    'bottle',
    'jar',
    'can',
    'pouch',
    'bag',
    'box',
    'tin',
    'tray',
    'each',
  };
  static const _retailPackageGroceries = {
    'soy',
    'sauce',
    'mustard',
    'pasta',
    'oat',
    'rice',
    'flour',
    'lentil',
    'chickpea',
    'spice',
    'salt',
    'sugar',
    'oil',
    'tea',
    'coffee',
    'yogurt',
    'butter',
    'cheese',
    'cream',
    'milk',
    'vinegar',
  };

  static const _forms = {
    'chocolate',
    'strawberry',
    'vanilla',
    'banana',
    'ketchup',
    'paste',
    'puree',
    'extract',
    'drink',
    'beverage',
    'concentrate',
    'tea',
    'coffee',
    'cereal',
    'biscuit',
    'cookie',
    'candy',
    'seed',
    'leaf',
    'ground',
    'roasted',
    'salted',
    'unsalted',
    'sweetened',
    'coconut',
    'almond',
    'soy',
    'oat',
    'rice',
    'cashew',
    'black',
  };

  static Set<(String, double)> _sizes(String label) =>
      RegExp(
            r'(\d+(?:\.\d+)?)\s*(kg|kilograms?|grams?|gm|g|ml|millilit(?:er|re)s?|lit(?:er|re)s?|l|pcs?|pieces?|count|ct)\b',
            caseSensitive: false,
          )
          .allMatches(label)
          .map((m) {
            final unit = _unit(m.group(2)!);
            return unit == null
                ? null
                : (unit.$1, double.parse(m.group(1)!) * unit.$2);
          })
          .whereType<(String, double)>()
          .toSet();

  static (String, double)? _unit(String unit) =>
      switch (unit.trim().toLowerCase()) {
        'kg' || 'kilogram' || 'kilograms' => ('mass', 1000),
        'g' || 'gm' || 'gram' || 'grams' => ('mass', 1),
        'l' || 'liter' || 'liters' || 'litre' || 'litres' => ('volume', 1000),
        'ml' ||
        'milliliter' ||
        'milliliters' ||
        'millilitre' ||
        'millilitres' => ('volume', 1),
        'pc' ||
        'pcs' ||
        'piece' ||
        'pieces' ||
        'count' ||
        'ct' ||
        'pack' ||
        'packs' ||
        'bottle' ||
        'bottles' ||
        'can' ||
        'cans' => ('count', 1),
        'dozen' => ('count', 12),
        _ => null,
      };
}
