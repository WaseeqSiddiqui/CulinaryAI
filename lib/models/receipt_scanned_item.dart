class ReceiptScannedItem {
  String name;
  double quantity;
  String unit;
  String location;
  double? price;
  bool isSelected;
  String sourceText;
  bool needsReview;

  ReceiptScannedItem({
    required this.name,
    required this.quantity,
    required this.unit,
    required this.location,
    this.price,
    this.isSelected = true,
    this.sourceText = '',
    this.needsReview = false,
  });

  ReceiptScannedItem copyWith({
    String? name,
    double? quantity,
    String? unit,
    String? location,
    double? price,
    bool? isSelected,
    String? sourceText,
    bool? needsReview,
  }) {
    return ReceiptScannedItem(
      name: name ?? this.name,
      quantity: quantity ?? this.quantity,
      unit: unit ?? this.unit,
      location: location ?? this.location,
      price: price ?? this.price,
      isSelected: isSelected ?? this.isSelected,
      sourceText: sourceText ?? this.sourceText,
      needsReview: needsReview ?? this.needsReview,
    );
  }
}
