import '../models/receipt_scanned_item.dart';

class ReceiptParserService {
  ReceiptParserService._();

  static final _ignoredLine = RegExp(
    r'\b(total|subtotal|sub total|tax|vat|gst|change|cash|card|visa|mastercard|'
    r'payment|amount due|balance|receipt|invoice|cashier|terminal|transaction|'
    r'date|time|thank you|welcome|phone|tel|www\.|http|discount|saving)\b',
    caseSensitive: false,
  );
  static final _unitPattern = RegExp(
    r'\b(\d+(?:[.,]\d+)?)\s*(kg|kgs|kilogram|kilograms|g|gm|gms|gram|grams|'
    r'ml|millilitre|millilitres|milliliter|milliliters|l|ltr|ltrs|litre|litres|'
    r'liter|liters|pcs|pc|piece|pieces|dozen|pack|packs|bottle|bottles)\b',
    caseSensitive: false,
  );
  static final _leadingCount = RegExp(r'^\s*(\d+(?:[.,]\d+)?)\s*[xX×]\s+');
  static final _priceAtEnd = RegExp(
    r'(?:\b(?:rs\.?|pkr|usd|eur|gbp)\s*|[$£€]\s*)?'
    r'(\d{1,6}(?:,\d{3})*(?:\.\d{1,2})?)\s*$',
    caseSensitive: false,
  );
  static final _onlyPrice = RegExp(
    r'^\s*(?:rs\.?|pkr|usd|eur|gbp|[$£€])?\s*'
    r'\d{1,6}(?:,\d{3})*(?:\.\d{1,2})?\s*$',
    caseSensitive: false,
  );
  static final _skuPrefix = RegExp(r'^\s*\d{5,}\s+');
  static final _nonNameCharacters = RegExp(r"[^a-zA-Z0-9&+\-'\s]");
  static final _multipleSpaces = RegExp(r'\s+');

  static List<ReceiptScannedItem> parseLines(List<String> recognizedLines) {
    final prepared = recognizedLines
        .map((line) => line.replaceAll(_multipleSpaces, ' ').trim())
        .where((line) => line.isNotEmpty)
        .toList();
    final parsed = <ReceiptScannedItem>[];

    for (var index = 0; index < prepared.length; index++) {
      var line = prepared[index];
      if (_shouldIgnore(line)) continue;

      if (_looksLikeNameOnly(line) &&
          index + 1 < prepared.length &&
          _onlyPrice.hasMatch(prepared[index + 1])) {
        line = '$line ${prepared[index + 1]}';
        index++;
      }

      final item = _parseLine(line);
      if (item != null) parsed.add(item);
    }

    return _mergeDuplicates(parsed);
  }

  static ReceiptScannedItem? _parseLine(String original) {
    var working = original.replaceAll(_skuPrefix, '').trim();
    var quantity = 1.0;
    var unit = 'pcs';
    double? price;
    var hasPurchaseSignal = false;

    final leading = _leadingCount.firstMatch(working);
    if (leading != null) {
      quantity = _number(leading.group(1)) ?? 1;
      working = working.replaceFirst(leading.group(0)!, '').trim();
      hasPurchaseSignal = true;
    }

    final unitMatch = _unitPattern.firstMatch(working);
    if (unitMatch != null) {
      quantity = _number(unitMatch.group(1)) ?? quantity;
      unit = _normalizeUnit(unitMatch.group(2)!);
      working = working.replaceFirst(unitMatch.group(0)!, ' ').trim();
      hasPurchaseSignal = true;
    }

    final priceMatch = _priceAtEnd.firstMatch(working);
    if (priceMatch != null) {
      final candidate = _number(priceMatch.group(1));
      final prefix = working.substring(0, priceMatch.start).trim();
      if (candidate != null && prefix.contains(RegExp(r'[a-zA-Z]'))) {
        price = candidate;
        working = prefix;
        hasPurchaseSignal = true;
      }
    }

    working = working
        .replaceAll(
          RegExp(r'\b(?:rs\.?|pkr|usd|eur|gbp)\b', caseSensitive: false),
          ' ',
        )
        .replaceAll(_nonNameCharacters, ' ')
        .replaceAll(_multipleSpaces, ' ')
        .trim();

    if (!hasPurchaseSignal || !_isPlausibleName(working)) return null;
    final name = _titleCase(working);
    return ReceiptScannedItem(
      name: name,
      quantity: quantity,
      unit: unit,
      location: _suggestLocation(name),
      price: price,
      isSelected: true,
    );
  }

  static bool _shouldIgnore(String line) {
    if (_ignoredLine.hasMatch(line)) return true;
    if (!line.contains(RegExp(r'[a-zA-Z]'))) return true;
    return false;
  }

  static bool _looksLikeNameOnly(String line) =>
      !_shouldIgnore(line) &&
      !_unitPattern.hasMatch(line) &&
      !_leadingCount.hasMatch(line) &&
      !_priceAtEnd.hasMatch(line) &&
      _isPlausibleName(line);

  static bool _isPlausibleName(String value) {
    final letters = value.replaceAll(RegExp(r'[^a-zA-Z]'), '');
    if (letters.length < 3 || value.length > 80) return false;
    final words = value.split(' ').where((word) => word.isNotEmpty).toList();
    return words.length <= 8;
  }

  static double? _number(String? value) {
    if (value == null) return null;
    return double.tryParse(value.replaceAll(',', ''));
  }

  static String _normalizeUnit(String raw) {
    switch (raw.toLowerCase()) {
      case 'kg':
      case 'kgs':
      case 'kilogram':
      case 'kilograms':
        return 'kg';
      case 'g':
      case 'gm':
      case 'gms':
      case 'gram':
      case 'grams':
        return 'g';
      case 'ml':
      case 'millilitre':
      case 'millilitres':
      case 'milliliter':
      case 'milliliters':
        return 'ml';
      case 'l':
      case 'ltr':
      case 'ltrs':
      case 'litre':
      case 'litres':
      case 'liter':
      case 'liters':
        return 'L';
      case 'dozen':
        return 'dozen';
      case 'pack':
      case 'packs':
      case 'bottle':
      case 'bottles':
        return 'pcs';
      default:
        return 'pcs';
    }
  }

  static String _suggestLocation(String name) {
    final value = name.toLowerCase();
    if (_containsAny(value, ['frozen', 'ice cream', 'icecream'])) {
      return 'freezer';
    }
    if (_containsAny(value, [
      'cumin',
      'coriander',
      'turmeric',
      'chilli',
      'chili',
      'pepper',
      'salt',
      'masala',
      'spice',
      'cinnamon',
      'paprika',
    ])) {
      return 'spice_rack';
    }
    if (_containsAny(value, [
      'milk',
      'egg',
      'yogurt',
      'yoghurt',
      'cheese',
      'cream',
      'butter',
      'chicken',
      'meat',
      'fish',
      'juice',
    ])) {
      return 'fridge';
    }
    return 'pantry_shelf';
  }

  static bool _containsAny(String value, List<String> terms) =>
      terms.any(value.contains);

  static String _titleCase(String value) => value
      .toLowerCase()
      .split(' ')
      .where((word) => word.isNotEmpty)
      .map((word) => '${word[0].toUpperCase()}${word.substring(1)}')
      .join(' ');

  static List<ReceiptScannedItem> _mergeDuplicates(
    List<ReceiptScannedItem> items,
  ) {
    final merged = <String, ReceiptScannedItem>{};
    for (final item in items) {
      final key = '${item.name.toLowerCase()}|${item.unit}';
      final existing = merged[key];
      if (existing == null) {
        merged[key] = item;
      } else {
        merged[key] = existing.copyWith(
          quantity: existing.quantity + item.quantity,
          price: existing.price == null && item.price == null
              ? null
              : (existing.price ?? 0) + (item.price ?? 0),
        );
      }
    }
    return merged.values.toList();
  }
}
