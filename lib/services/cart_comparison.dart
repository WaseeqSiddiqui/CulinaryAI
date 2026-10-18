import '../models/store_models.dart';

CartComparison compareCart(
  List<AutomationItemResult> intended,
  List<CartLine> actual, {
  List<CartLine> baseline = const [],
}) {
  final usedActual = <int>{};
  final baselineActual = <int>{};
  final matched = <CartLine>[];
  final missing = <String>[];
  final quantityMismatches = <CartQuantityMismatch>[];

  for (final baselineLine in baseline) {
    final index = _bestLineIndex(
      baselineLine,
      actual,
      excluded: baselineActual,
    );
    if (index >= 0) baselineActual.add(index);
  }

  for (final item in intended.where((item) => item.status == AddStatus.added)) {
    final wantedLine = CartLine(
      name: item.productName ?? item.wantedName,
      quantity: item.unitsAdded ?? 1,
      price: item.unitPrice ?? 0,
    );
    final actualIndex = _bestLineIndex(
      wantedLine,
      actual,
      excluded: usedActual,
    );
    if (actualIndex < 0) {
      missing.add(item.wantedName);
      continue;
    }

    usedActual.add(actualIndex);
    final line = actual[actualIndex];
    final baselineIndex = _bestLineIndex(wantedLine, baseline);
    final baselineQuantity = baselineIndex < 0
        ? 0
        : baseline[baselineIndex].quantity;
    final expectedQuantity = baselineQuantity + (item.unitsAdded ?? 1);
    if (line.quantity != expectedQuantity) {
      quantityMismatches.add(
        CartQuantityMismatch(
          name: item.wantedName,
          expected: expectedQuantity,
          actual: line.quantity,
        ),
      );
    } else {
      matched.add(line);
    }
  }

  final unexpected = <CartLine>[
    for (var index = 0; index < actual.length; index++)
      if (!usedActual.contains(index) && !baselineActual.contains(index))
        actual[index],
  ];

  return CartComparison(
    matched: matched,
    missing: missing,
    quantityMismatches: quantityMismatches,
    unexpected: unexpected,
  );
}

int _bestLineIndex(
  CartLine wanted,
  List<CartLine> candidates, {
  Set<int> excluded = const {},
}) {
  if (wanted.storeId case final storeId?) {
    final byId = candidates.indexed
        .where((entry) => !excluded.contains(entry.$1))
        .where((entry) => entry.$2.storeId == storeId)
        .map((entry) => entry.$1)
        .firstOrNull;
    if (byId != null) return byId;
  }

  var bestIndex = -1;
  var bestScore = 0.0;
  for (var index = 0; index < candidates.length; index++) {
    if (excluded.contains(index)) continue;
    final score = _nameScore(wanted.name, candidates[index].name);
    if (score > bestScore) {
      bestScore = score;
      bestIndex = index;
    }
  }
  return bestScore >= 0.72 ? bestIndex : -1;
}

double _nameScore(String left, String right) {
  final leftTokens = _tokens(left);
  final rightTokens = _tokens(right);
  if (leftTokens.isEmpty || rightTokens.isEmpty) return 0;
  if (leftTokens.join(' ') == rightTokens.join(' ')) return 1;
  final common = leftTokens.intersection(rightTokens).length;
  if (common == 0) return 0;
  if (leftTokens.length == 1 || rightTokens.length == 1) return 0;
  return (2 * common) / (leftTokens.length + rightTokens.length);
}

Set<String> _tokens(String value) =>
    RegExp(r'[a-z0-9]+')
        .allMatches(value.toLowerCase())
        .map((match) => match.group(0)!)
        .where((token) => token.isNotEmpty)
        .toSet();
