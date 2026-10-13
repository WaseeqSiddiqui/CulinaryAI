import '../models/receipt_scanned_item.dart';

class ReceiptParserService {
  ReceiptParserService._();

  static final _ignoredLine = RegExp(
    r'\b(total|subtotal|sub total|grand total|net total|tax|vat|gst|change|'
    r'cash|card|visa|mastercard|payment|amount due|balance|receipt|invoice|'
    r'cashier|terminal|transaction|date|time|thank you|welcome|phone|tel|'
    r'www\.|http|discount|saving|round off|tender|bill no|order no|items? sold|'
    r'buy\s*\d|multibuy|promotion|coupon|supermarket|fresh mart|'
    r'description\s+qty|qty\s+rate|unit price)\b',
    caseSensitive: false,
  );
  static final _unitPattern = RegExp(
    r'\b(\d+(?:[.,]\d+)?)\s*(kg|kgs|kilogram|kilograms|g|gm|gms|gram|grams|'
    r'ml|millilitre|millilitres|milliliter|milliliters|l|ltr|ltrs|litre|litres|'
    r'liter|liters|cc|pcs|pc|piece|pieces|dozen|pack|packs|packet|packets|pkt|pkts|'
    r'bottle|bottles|can|cans|tin|tins|box|boxes)\b',
    caseSensitive: false,
  );
  static final _eachUnit = RegExp(r'\b(?:each|ea)\b', caseSensitive: false);
  static final _leadingCount = RegExp(
    r'^\s*(\d+(?:[.,]\d+)?)\s*(?:[xX×@*])\s*',
  );
  static final _plainLeadingCount = RegExp(
    r'^\s*(\d{1,3})\s+(?=(?:\d{5,14}\s+)?[a-zA-Z])',
  );
  static final _quantityPriceTail = RegExp(
    r'\b(\d+(?:[.,]\d+)?)\s*(?:[xX×@*])\s*'
    r'(?:rs\.?\s*|pkr\s*)?\d+(?:[.,]\d{1,2})?'
    r'(?:\s+(?:rs\.?\s*|pkr\s*)?\d+(?:[.,]\d{1,2})?)?\s*$',
    caseSensitive: false,
  );
  static final _packageCount = RegExp(
    r'\b(\d+(?:[.,]\d+)?)\s*(?:[xX×@*])\s*'
    r'(?=\d+(?:[.,]\d+)?\s*(?:kg|kgs|g|gm|gms|ml|cc|l|ltr|ltrs|pcs|pc|'
    r'dozen|pack|packs|packet|packets|pkt|pkts|bottle|bottles|can|cans|'
    r'tin|tins|box|boxes)\b)',
    caseSensitive: false,
  );
  static final _countAndTotalTail = RegExp(
    r'(?<![\d.,])(\d{1,3})\s+'
    r'(?:(?:(?:rs\.?|pkr|usd|eur|gbp)\s*|[$£€₹]\s*)?'
    r'\d{1,7}(?:,\d{3})*(?:\.\d{1,2})?\s+)?'
    r'(?:(?:rs\.?|pkr|usd|eur|gbp)\s*|[$£€₹]\s*)?'
    r'(\d{1,7}(?:,\d{3})*(?:\.\d{1,2})?)\s*$',
    caseSensitive: false,
  );
  static final _priceAtEnd = RegExp(
    r'(?:\b(?:rs\.?|pkr|usd|eur|gbp)\s*|[$£€₹]\s*)?'
    r'(\d{1,7}(?:,\d{3})*(?:\.\d{1,2})?)\s*$',
    caseSensitive: false,
  );
  static final _onlyPrice = RegExp(
    r'^\s*(?:rs\.?|pkr|usd|eur|gbp|[$£€₹])?\s*'
    r'\d{1,7}(?:,\d{3})*(?:\.\d{1,2})?\s*$',
    caseSensitive: false,
  );
  static final _weightedDetail = RegExp(
    r'^\s*(\d+(?:[.,]\d+)?)\s*(kg|kgs|g|gm|gms|ml|cc|l|ltr|ltrs)'
    r'\s*@\s*(?:(?:rs\.?|pkr|usd|eur|gbp)\s*|[$£€₹]\s*)?'
    r'(\d+(?:[.,]\d{1,2})?)\s*/\s*'
    r'(kg|kgs|g|gm|gms|ml|cc|l|ltr|ltrs)\s*$',
    caseSensitive: false,
  );
  static final _unitPriceContinuation = RegExp(
    r"^\s*([a-zA-Z][a-zA-Z0-9&+\-'\s]{1,60}?)\s*@\s*"
    r'(?:(?:rs\.?|pkr|usd|eur|gbp)\s*|[$£€₹]\s*)?'
    r'(\d+(?:[.,]\d{1,2})?)'
    r'(?:\s*/\s*(?:kg|kgs|g|gm|gms|ml|cc|l|ltr|ltrs|pc|pcs|each))?\s*$',
    caseSensitive: false,
  );
  static final _inlineUnitPrice = RegExp(
    r'\s*@\s*(?:(?:rs\.?|pkr|usd|eur|gbp)\s*|[$£€₹]\s*)?'
    r'\d+(?:[.,]\d{1,2})?'
    r'(?:\s*/\s*(?:kg|kgs|g|gm|gms|ml|cc|l|ltr|ltrs|pc|pcs|each))?',
    caseSensitive: false,
  );
  static final _saleUnitDescriptor = RegExp(
    r'\bper\s+(?:kg|kilo|kilogram|lb|pound)\b',
    caseSensitive: false,
  );
  static final _barcode = RegExp(r'(?<!\d)\d{5,14}(?!\d)');
  static final _currency = RegExp(
    r'\b(?:rs\.?|pkr|usd|eur|gbp)\b|[$£€₹]',
    caseSensitive: false,
  );
  static final _nonNameCharacters = RegExp(r"[^a-zA-Z0-9&+\-'\s]");
  static final _multipleSpaces = RegExp(r'\s+');

  static List<ReceiptScannedItem> parseLines(List<String> recognizedLines) {
    final prepared = recognizedLines
        .map(_normalizeLine)
        .where((line) => line.isNotEmpty)
        .toList();
    final parsed = <ReceiptScannedItem>[];

    for (var index = 0; index < prepared.length; index++) {
      var line = prepared[index];
      if (_shouldIgnore(line)) continue;

      if (parsed.isNotEmpty && _applyWeightedDetail(line, parsed.last)) {
        continue;
      }
      if (parsed.isNotEmpty &&
          _appendUnitPriceContinuation(line, parsed.last)) {
        continue;
      }

      if (_looksLikeNameOnly(line)) {
        final nextIndex = index + 1;
        if (nextIndex < prepared.length &&
            !_shouldIgnore(prepared[nextIndex]) &&
            !_isDetailOnlyLine(prepared[nextIndex]) &&
            _parseLine(prepared[nextIndex]) != null) {
          line = '$line ${prepared[nextIndex]}';
          index = nextIndex;
        }

        var detailIndex = index + 1;
        var detailsAdded = 0;
        while (detailIndex < prepared.length &&
            detailsAdded < 2 &&
            _isDetailOnlyLine(prepared[detailIndex])) {
          line = '$line ${prepared[detailIndex]}';
          index = detailIndex;
          detailIndex++;
          detailsAdded++;
        }
      }

      final item = _parseLine(line);
      if (item != null) parsed.add(item);
    }

    return _mergeDuplicates(parsed);
  }

  static bool _applyWeightedDetail(String line, ReceiptScannedItem previous) {
    final match = _weightedDetail.firstMatch(line);
    if (match == null) return false;

    final quantity = _number(match.group(1));
    if (quantity == null || quantity <= 0) return false;
    previous.quantity = quantity;
    previous.unit = _normalizeUnit(match.group(2)!);
    return true;
  }

  static bool _appendUnitPriceContinuation(
    String line,
    ReceiptScannedItem previous,
  ) {
    final match = _unitPriceContinuation.firstMatch(line);
    final total = previous.price;
    final unitPrice = _number(match?.group(2));
    if (match == null || total == null || unitPrice == null || unitPrice <= 0) {
      return false;
    }

    final inferredCount = total / unitPrice;
    final nearWholeCount = (inferredCount - inferredCount.round()).abs() < 0.03;
    if (!nearWholeCount || inferredCount < 1 || inferredCount > 100) {
      return false;
    }

    previous.name = '${previous.name} ${_titleCase(match.group(1)!)}';
    previous.location = _suggestLocation(previous.name);
    return true;
  }

  static String _normalizeLine(String line) => line
      .replaceAll('Ã—', '×')
      .replaceAll('â‚¹', 'Rs ')
      .replaceAll(_multipleSpaces, ' ')
      .trim();

  static ReceiptScannedItem? _parseLine(String original) {
    var working = original;
    var purchaseCount = 1.0;
    var packageMultiplier = 1.0;
    var packageQuantity = 1.0;
    var unit = 'pcs';
    double? price;
    var hasPurchaseCount = false;
    var hasUnit = false;
    var hasPurchaseSignal = false;

    final leading = _leadingCount.firstMatch(working);
    if (leading != null) {
      purchaseCount = _number(leading.group(1)) ?? 1;
      working = working.replaceFirst(leading.group(0)!, '').trim();
      hasPurchaseCount = true;
      hasPurchaseSignal = true;
    } else if (_hasPriceOrUnitSignal(working)) {
      final plainCount = _plainLeadingCount.firstMatch(working);
      if (plainCount != null) {
        purchaseCount = _number(plainCount.group(1)) ?? 1;
        working = working.replaceFirst(plainCount.group(0)!, '').trim();
        hasPurchaseCount = true;
        hasPurchaseSignal = true;
      }
    }

    working = working
        .replaceAll(_barcode, ' ')
        .replaceAll(_multipleSpaces, ' ');

    final packageCount = _packageCount.firstMatch(working);
    if (packageCount != null) {
      packageMultiplier = _number(packageCount.group(1)) ?? 1;
      working = working.replaceFirst(packageCount.group(0)!, '').trim();
      hasPurchaseSignal = true;
    }

    final calculation = _quantityPriceTail.firstMatch(working);
    if (calculation != null) {
      purchaseCount = _number(calculation.group(1)) ?? purchaseCount;
      final calculationText = working.substring(calculation.start);
      price = _trailingPrice(calculationText);
      working = working.substring(0, calculation.start).trim();
      hasPurchaseCount = true;
      hasPurchaseSignal = true;
    }

    final unitMatch = _unitPattern.firstMatch(working);
    if (unitMatch != null) {
      packageQuantity = _number(unitMatch.group(1)) ?? 1;
      unit = _normalizeUnit(unitMatch.group(2)!);
      working = working.replaceFirst(unitMatch.group(0)!, ' ').trim();
      while (true) {
        final duplicateUnit = _unitPattern.firstMatch(working);
        if (duplicateUnit == null ||
            _number(duplicateUnit.group(1)) != packageQuantity ||
            _normalizeUnit(duplicateUnit.group(2)!) != unit) {
          break;
        }
        working = working.replaceFirst(duplicateUnit.group(0)!, ' ').trim();
      }
      hasUnit = true;
      hasPurchaseSignal = true;
    } else {
      final eachMatch = _eachUnit.firstMatch(working);
      if (eachMatch != null) {
        working = working.replaceFirst(eachMatch.group(0)!, ' ').trim();
        hasUnit = true;
        hasPurchaseSignal = true;
      }
    }

    if (!hasPurchaseCount) {
      final countAndTotal = _countAndTotalTail.firstMatch(working);
      if (countAndTotal != null) {
        final prefix = working.substring(0, countAndTotal.start).trim();
        if (prefix.contains(RegExp(r'[a-zA-Z]'))) {
          purchaseCount = _number(countAndTotal.group(1)) ?? 1;
          price = _number(countAndTotal.group(2));
          working = prefix;
          hasPurchaseCount = true;
          hasPurchaseSignal = true;
        }
      }
    }

    for (var removed = 0; removed < 2; removed++) {
      final priceMatch = _priceAtEnd.firstMatch(working);
      if (priceMatch == null) break;
      final prefix = working.substring(0, priceMatch.start).trim();
      if (!prefix.contains(RegExp(r'[a-zA-Z]'))) break;
      price ??= _number(priceMatch.group(1));
      working = prefix;
      hasPurchaseSignal = true;
    }

    working = working
        .replaceAll(_inlineUnitPrice, ' ')
        .replaceAll(_saleUnitDescriptor, ' ')
        .replaceAll(_currency, ' ')
        .replaceAll(
          RegExp(r'\b(?:qty|quantity|rate|amount)\b', caseSensitive: false),
          ' ',
        )
        .replaceAll(_nonNameCharacters, ' ')
        .replaceAll(_multipleSpaces, ' ')
        .trim();

    if (!hasPurchaseSignal || !_isPlausibleName(working)) return null;
    final name = _titleCase(working);
    final quantity = hasUnit
        ? packageQuantity * packageMultiplier * purchaseCount
        : purchaseCount;
    return ReceiptScannedItem(
      name: name,
      quantity: quantity,
      unit: unit,
      location: _suggestLocation(name),
      price: price,
      isSelected: true,
    );
  }

  static bool _hasPriceOrUnitSignal(String line) =>
      _unitPattern.hasMatch(line) ||
      _eachUnit.hasMatch(line) ||
      _priceAtEnd.hasMatch(line) ||
      _currency.hasMatch(line);

  static double? _trailingPrice(String value) {
    final match = _priceAtEnd.firstMatch(value);
    return _number(match?.group(1));
  }

  static bool _isDetailOnlyLine(String line) {
    if (_onlyPrice.hasMatch(line)) return true;
    if (_shouldIgnore(line)) return false;
    final residue = line
        .replaceAll(_currency, ' ')
        .replaceAll(
          RegExp(
            r'\b(?:kg|kgs|g|gm|gms|ml|cc|l|ltr|ltrs|pcs|pc|each|dozen|pack|packs|'
            r'packet|packets|pkt|pkts|bottle|bottles|can|cans|tin|tins|box|boxes)\b',
            caseSensitive: false,
          ),
          ' ',
        )
        .replaceAll(RegExp(r'[\d.,xX×@*\-\s]'), '');
    return residue.isEmpty &&
        (_unitPattern.hasMatch(line) ||
            _quantityPriceTail.hasMatch(line) ||
            _priceAtEnd.hasMatch(line));
  }

  static bool _shouldIgnore(String line) {
    if (_ignoredLine.hasMatch(line)) return true;
    if (!line.contains(RegExp(r'[a-zA-Z]'))) return true;
    return false;
  }

  static bool _looksLikeNameOnly(String line) =>
      !_shouldIgnore(line) &&
      !_unitPattern.hasMatch(line) &&
      !_eachUnit.hasMatch(line) &&
      !_leadingCount.hasMatch(line) &&
      !_priceAtEnd.hasMatch(line) &&
      _isPlausibleName(line);

  static bool _isPlausibleName(String value) {
    final letters = value.replaceAll(RegExp(r'[^a-zA-Z]'), '');
    if (letters.length < 3 || value.length > 100) return false;
    final words = value.split(' ').where((word) => word.isNotEmpty).toList();
    if (words.length > 12) return false;
    final digits = value.replaceAll(RegExp(r'[^0-9]'), '');
    return digits.length <= letters.length;
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
      case 'cc':
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
      case 'each':
      case 'ea':
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

  static const _uppercaseNames = {'ktc', 'trs'};

  static String _titleCase(String value) => value
      .toLowerCase()
      .split(' ')
      .where((word) => word.isNotEmpty)
      .map(
        (word) => _uppercaseNames.contains(word)
            ? word.toUpperCase()
            : '${word[0].toUpperCase()}${word.substring(1)}',
      )
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
