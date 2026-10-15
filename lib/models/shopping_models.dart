class ShoppingListItem {
  const ShoppingListItem({
    required this.id,
    required this.name,
    required this.quantity,
    required this.unit,
    this.keepAfterOrder = false,
  });

  final String id;
  final String name;
  final double quantity;
  final String unit;
  final bool keepAfterOrder;

  Map<String, dynamic> toMap() => {
    'id': id,
    'name': name,
    'quantity': quantity,
    'unit': unit,
    'keepAfterOrder': keepAfterOrder,
  };

  factory ShoppingListItem.fromMap(Map<String, dynamic> map) =>
      ShoppingListItem(
        id: map['id'] as String,
        name: map['name'] as String,
        quantity: (map['quantity'] as num).toDouble(),
        unit: map['unit'] as String,
        keepAfterOrder: map['keepAfterOrder'] as bool? ?? false,
      );
}

class ShoppingOrder {
  const ShoppingOrder({
    required this.id,
    required this.householdId,
    required this.items,
    required this.status,
    required this.createdAt,
    this.storeName,
    this.total,
  });

  final String id;
  final String householdId;
  final List<ShoppingListItem> items;
  final String status;
  final DateTime createdAt;
  final String? storeName;
  final double? total;

  Map<String, dynamic> toMap() => {
    'id': id,
    'householdId': householdId,
    'items': items.map((item) => item.toMap()).toList(),
    'status': status,
    'createdAt': createdAt.toIso8601String(),
    'storeName': storeName,
    'total': total,
  };

  factory ShoppingOrder.fromMap(Map<String, dynamic> map) => ShoppingOrder(
    id: map['id'] as String,
    householdId: map['householdId'] as String,
    items: (map['items'] as List<dynamic>)
        .map((item) => ShoppingListItem.fromMap(Map<String, dynamic>.from(item as Map)))
        .toList(),
    status: map['status'] as String,
    createdAt: DateTime.parse(map['createdAt'] as String),
    storeName: map['storeName'] as String?,
    total: (map['total'] as num?)?.toDouble(),
  );
}
