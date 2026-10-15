enum AddStatus { added, notFound, outOfStock, lowConfidence, failed }

class ProductCandidate {
  const ProductCandidate({
    required this.name,
    required this.price,
    required this.inStock,
    required this.index,
    this.size,
  });

  final String name;
  final String? size;
  final double price;
  final bool inStock;
  final int index;

  Map<String, dynamic> toMap() => {
    'name': name,
    'size': size,
    'price': price,
    'in_stock': inStock,
  };
}

class ProductMatch {
  const ProductMatch({
    required this.chosenIndex,
    required this.unitsToBuy,
    required this.confidence,
    required this.reason,
  });

  final int? chosenIndex;
  final int? unitsToBuy;
  final double confidence;
  final String reason;
}

class AddResult {
  const AddResult(this.status, this.message);
  final AddStatus status;
  final String message;
  bool get added => status == AddStatus.added;
}

class CartLine {
  const CartLine({
    required this.name,
    required this.quantity,
    required this.price,
  });
  final String name;
  final int quantity;
  final double price;
}

enum CheckoutState { placed, needsManualCompletion, failed }

class CheckoutResult {
  const CheckoutResult(this.state, this.message);
  final CheckoutState state;
  final String message;
}

class AutomationItemResult {
  const AutomationItemResult({
    required this.wantedName,
    required this.wantedQuantity,
    required this.wantedUnit,
    required this.status,
    required this.reason,
    this.productName,
    this.unitsAdded,
    this.unitPrice,
  });

  final String wantedName;
  final double wantedQuantity;
  final String wantedUnit;
  final AddStatus status;
  final String reason;
  final String? productName;
  final int? unitsAdded;
  final double? unitPrice;
}

class CartComparison {
  const CartComparison({required this.matched, required this.missing});
  final List<CartLine> matched;
  final List<String> missing;
}
