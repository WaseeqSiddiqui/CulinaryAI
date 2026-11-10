import '../models/store_models.dart';

CartComparison compareCart(
  List<AutomationItemResult> intended,
  List<CartLine> actual, {
  List<CartLine> baseline = const [],
}) {
  final matched = <CartLine>[];
  final missing = <String>[];
  final quantityMismatches = <CartQuantityMismatch>[];
  final expected = <CartLine>[];
  final labels = <String>[];
  void accumulate(CartLine line, String label) {
    final index = _bestLineIndex(line, expected);
    if (index < 0) {
      expected.add(line);
      labels.add(label);
    } else {
      final previous = expected[index];
      expected[index] = CartLine(
        name: previous.name,
        quantity: previous.quantity + line.quantity,
        price: line.price,
        storeId: previous.storeId ?? line.storeId,
      );
    }
  }

  for (final line in baseline) {
    accumulate(line, line.name);
  }
  for (final item in intended.where((item) => item.status == AddStatus.added)) {
    accumulate(
      CartLine(
        name: item.productName ?? item.wantedName,
        quantity: item.unitsAdded ?? 1,
        price: item.unitPrice ?? 0,
        storeId: item.productId,
      ),
      item.wantedName,
    );
  }
  final usedActual = <int>{};
  for (var index = 0; index < expected.length; index++) {
    final wantedLine = expected[index];
    final actualIndex = _bestLineIndex(
      wantedLine,
      actual,
      excluded: usedActual,
    );
    if (actualIndex < 0) {
      missing.add(labels[index]);
      continue;
    }

    usedActual.add(actualIndex);
    final line = actual[actualIndex];
    final expectedQuantity = wantedLine.quantity;
    if (line.quantity != expectedQuantity) {
      quantityMismatches.add(
        CartQuantityMismatch(
          name: labels[index],
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
      if (!usedActual.contains(index)) actual[index],
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

  for (var index = 0; index < candidates.length; index++) {
    if (excluded.contains(index)) continue;
    if (_normalizedName(wanted.name) == _normalizedName(candidates[index].name)) {
      return index;
    }
  }
  return -1;
}

String _normalizedName(String value) =>
    value.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
