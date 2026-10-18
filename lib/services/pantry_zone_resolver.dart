class PantryZoneResolver {
  static const List<String> zones = [
    'Fridge',
    'Freezer',
    'Pantry Shelf',
    'Spice Rack',
  ];

  static const Map<String, String> _zoneAliases = {
    'fridge': 'Fridge',
    'refrigerator': 'Fridge',
    'refrigerated': 'Fridge',
    'chiller': 'Fridge',
    'chilled': 'Fridge',
    'freezer': 'Freezer',
    'deep freeze': 'Freezer',
    'deep freezer': 'Freezer',
    'frozen': 'Freezer',
    'pantry': 'Pantry Shelf',
    'pantry shelf': 'Pantry Shelf',
    'shelf': 'Pantry Shelf',
    'cupboard': 'Pantry Shelf',
    'dry storage': 'Pantry Shelf',
    'spice': 'Spice Rack',
    'spices': 'Spice Rack',
    'spice rack': 'Spice Rack',
    'seasoning': 'Spice Rack',
    'seasonings': 'Spice Rack',
  };

  static const List<String> _frozenPriority = [
    'frozen',
    'ice cream',
    'icecream',
  ];

  static const List<String> _spiceTerms = [
    'masala',
    'seasoning',
    'seasonings',
    'spice',
    'spices',
    'turmeric',
    'haldi',
    'cumin',
    'zeera',
    'jeera',
    'black pepper',
    'peppercorn',
    'peppercorns',
    'red chili',
    'red chilli',
    'chili powder',
    'chilli powder',
    'cayenne',
    'paprika',
    'coriander powder',
    'coriander seed',
    'coriander seeds',
    'cinnamon',
    'cardamom',
    'elaichi',
    'clove',
    'cloves',
    'laung',
    'nutmeg',
    'bay leaf',
    'bay leaves',
    'oregano',
  ];

  static const List<String> _pantryPriority = [
    'canned',
    'tinned',
    'tin pack',
    'custard powder',
    'milk powder',
    'baking powder',
    'cocoa powder',
    'protein powder',
    'washing powder',
    'dalda',
    'banaspati',
    'vanaspati',
  ];

  static const List<String> _freezerTerms = [
    'fish',
    'salmon',
    'tilapia',
    'prawn',
    'prawns',
    'shrimp',
  ];

  static const List<String> _fridgeTerms = [
    'milk',
    'yogurt',
    'yoghurt',
    'dahi',
    'butter',
    'cheese',
    'cream',
    'paneer',
    'egg',
    'eggs',
    'chicken',
    'beef',
    'mutton',
    'meat',
    'tomato',
    'tomatoes',
    'ginger',
    'carrot',
    'carrots',
    'cucumber',
    'spinach',
    'lettuce',
    'romaine',
    'bell pepper',
    'capsicum',
    'green chili',
    'green chilies',
    'green chilli',
    'green chillies',
    'lemon',
    'lime',
    'apple',
    'apples',
    'orange',
    'oranges',
    'strawberry',
    'strawberries',
    'blueberry',
    'blueberries',
    'raspberry',
    'raspberries',
    'grapes',
    'coriander',
    'cilantro',
    'mint',
    'mayonnaise',
    'mayo',
    'ketchup',
    'chilli garlic sauce',
    'chili garlic sauce',
    'diet cola',
    'cola',
    'soda',
  ];

  static const List<String> _pantryTerms = [
    'onion',
    'onions',
    'potato',
    'potatoes',
    'garlic',
    'banana',
    'bananas',
    'rice',
    'flour',
    'atta',
    'maida',
    'oil',
    'ghee',
    'sugar',
    'pasta',
    'noodles',
    'ramen',
    'lentil',
    'lentils',
    'daal',
    'dal',
    'chickpea',
    'chickpeas',
    'beans',
    'bread',
    'baguette',
    'soy sauce',
    'vinegar',
    'tea',
    'coffee',
    'water',
    'granola',
    'cereal',
    'oats',
    'biscuit',
    'biscuits',
    'cookies',
  ];

  static String normalize(String? value) {
    final normalized = _normalizeWords(value ?? '');
    return _zoneAliases[normalized] ?? 'Pantry Shelf';
  }

  static String resolveForItem(String itemName, {String? suggestedZone}) {
    return inferStrong(itemName) ?? normalize(suggestedZone);
  }

  static String? inferStrong(String itemName) {
    final words = _normalizeWords(itemName);
    if (words.isEmpty) return null;

    if (_hasAny(words, _frozenPriority)) return 'Freezer';
    if (_hasAny(words, _spiceTerms)) return 'Spice Rack';
    if (_hasAny(words, _pantryPriority)) return 'Pantry Shelf';
    if (_hasAny(words, _freezerTerms)) return 'Freezer';
    if (_hasAny(words, _fridgeTerms)) return 'Fridge';
    if (_hasAny(words, _pantryTerms)) return 'Pantry Shelf';
    return null;
  }

  static bool _hasAny(String words, List<String> terms) {
    final padded = ' $words ';
    return terms.any((term) {
      final normalizedTerm = _normalizeWords(term);
      return padded.contains(' $normalizedTerm ');
    });
  }

  static String _normalizeWords(String value) {
    return value
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
        .trim()
        .replaceAll(RegExp(r'\s+'), ' ');
  }
}
