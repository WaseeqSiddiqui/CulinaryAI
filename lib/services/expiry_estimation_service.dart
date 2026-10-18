import '../models/pantry_item_model.dart';

class ExpiryEstimate {
  final DateTime date;
  final ExpiryConfidence confidence;
  final String reason;

  const ExpiryEstimate({
    required this.date,
    required this.confidence,
    required this.reason,
  });
}

class ExpiryEstimationService {
  const ExpiryEstimationService._();

  static ExpiryEstimate? estimate({
    required String itemName,
    required String storageZone,
    required DateTime purchasedAt,
  }) {
    final name = itemName.toLowerCase();
    final zone = storageZone.toLowerCase();
    final frozen = zone.contains('freezer');
    int? days;
    var confidence = ExpiryConfidence.medium;

    if (frozen && _has(name, ['meat', 'chicken', 'beef', 'fish', 'mutton'])) {
      days = 90;
    } else if (_has(name, ['fish', 'seafood'])) {
      days = 1;
    } else if (_has(name, ['chicken', 'beef', 'mutton', 'meat'])) {
      days = 2;
    } else if (_has(name, ['milk', 'cream'])) {
      days = 7;
    } else if (_has(name, ['yogurt', 'yoghurt'])) {
      days = 10;
    } else if (_has(name, ['egg'])) {
      days = 21;
    } else if (_has(name, ['bread', 'bun', 'naan'])) {
      days = 5;
    } else if (_has(name, [
      'berry',
      'berries',
      'strawberry',
      'spinach',
      'lettuce',
      'herb',
    ])) {
      days = 3;
    } else if (_has(name, ['banana', 'tomato', 'cucumber', 'avocado'])) {
      days = 7;
    } else if (_has(name, ['apple', 'orange', 'lemon', 'citrus'])) {
      days = 14;
    } else if (_has(name, ['cheese'])) {
      days = 14;
    } else if (frozen) {
      days = 60;
      confidence = ExpiryConfidence.low;
    }

    if (days == null) return null;
    return ExpiryEstimate(
      date: _dateOnly(purchasedAt).add(Duration(days: days)),
      confidence: confidence,
      reason: 'Estimated from typical $itemName storage life in $storageZone.',
    );
  }

  static ExpiryEstimate estimateAfterOpening({
    required String itemName,
    required DateTime openedAt,
    DateTime? printedExpiry,
  }) {
    final name = itemName.toLowerCase();
    var days = 7;
    if (_has(name, ['milk', 'cream'])) days = 5;
    if (_has(name, ['juice'])) days = 7;
    if (_has(name, ['sauce', 'ketchup', 'mayonnaise'])) days = 30;
    if (_has(name, ['can', 'tin'])) days = 3;
    if (_has(name, ['cheese'])) days = 7;
    var date = _dateOnly(openedAt).add(Duration(days: days));
    if (printedExpiry != null && printedExpiry.isBefore(date)) {
      date = printedExpiry;
    }
    return ExpiryEstimate(
      date: date,
      confidence: ExpiryConfidence.medium,
      reason: 'Estimated safe-use window after opening.',
    );
  }

  static bool _has(String input, List<String> terms) =>
      terms.any((term) => input.contains(term));

  static DateTime _dateOnly(DateTime value) =>
      DateTime(value.year, value.month, value.day);
}
