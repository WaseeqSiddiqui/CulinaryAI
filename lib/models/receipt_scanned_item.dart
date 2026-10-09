class ReceiptScannedItem {
  String name;
  double quantity;
  String unit;
  String location;
  double? price;
  bool isSelected;

  ReceiptScannedItem({
    required this.name,
    required this.quantity,
    required this.unit,
    required this.location,
    this.price,
    this.isSelected = true,
  });

  ReceiptScannedItem copyWith({
    String? name,
    double? quantity,
    String? unit,
    String? location,
    double? price,
    bool? isSelected,
  }) {
    return ReceiptScannedItem(
      name: name ?? this.name,
      quantity: quantity ?? this.quantity,
      unit: unit ?? this.unit,
      location: location ?? this.location,
      price: price ?? this.price,
      isSelected: isSelected ?? this.isSelected,
    );
  }
}
