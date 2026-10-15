import '../services/food_image_service.dart';

class PantryItemModel {
  final String id;
  final String householdId;
  final String name;
  final double quantity;
  final String unit;
  final String location;
  final double lowStockThreshold;
  final String addedVia; // 'manual' or 'receipt_scan'
  final DateTime updatedAt;
  final String? customImageUrl;
  final bool estimated;

  PantryItemModel({
    required this.id,
    required this.householdId,
    required this.name,
    required this.quantity,
    required this.unit,
    required this.location,
    this.lowStockThreshold = 1.0,
    this.addedVia = 'manual',
    required this.updatedAt,
    this.customImageUrl,
    this.estimated = false,
  });

  bool get isLowStock => quantity <= lowStockThreshold;

  /// Returns a curated, appetizing high-resolution food photo for the ingredient
  String get displayImageUrl => FoodImageService.resolveImageUrl(
        name,
        storageZone: location,
        customImageUrl: customImageUrl,
      );

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'household_id': householdId,
      'name': name,
      'quantity': quantity,
      'unit': unit,
      'location': location,
      'low_stock_threshold': lowStockThreshold,
      'added_via': addedVia,
      'updated_at': updatedAt.toIso8601String(),
      'custom_image_url': customImageUrl,
      'estimated': estimated,
    };
  }

  factory PantryItemModel.fromMap(Map<String, dynamic> map, String id) {
    return PantryItemModel(
      id: id,
      householdId: map['household_id'] ?? '',
      name: map['name'] ?? '',
      quantity: (map['quantity'] as num?)?.toDouble() ?? 0.0,
      unit: map['unit'] ?? 'pcs',
      location: map['location'] ?? 'Pantry Shelf',
      lowStockThreshold: (map['low_stock_threshold'] as num?)?.toDouble() ?? 1.0,
      addedVia: map['added_via'] ?? 'manual',
      updatedAt: map['updated_at'] != null
          ? DateTime.tryParse(map['updated_at']) ?? DateTime.now()
          : DateTime.now(),
      customImageUrl: map['custom_image_url'],
      estimated: map['estimated'] as bool? ?? false,
    );
  }

  PantryItemModel copyWith({
    String? id,
    String? householdId,
    String? name,
    double? quantity,
    String? unit,
    String? location,
    double? lowStockThreshold,
    String? addedVia,
    DateTime? updatedAt,
    String? customImageUrl,
    bool? estimated,
  }) {
    return PantryItemModel(
      id: id ?? this.id,
      householdId: householdId ?? this.householdId,
      name: name ?? this.name,
      quantity: quantity ?? this.quantity,
      unit: unit ?? this.unit,
      location: location ?? this.location,
      lowStockThreshold: lowStockThreshold ?? this.lowStockThreshold,
      addedVia: addedVia ?? this.addedVia,
      updatedAt: updatedAt ?? this.updatedAt,
      customImageUrl: customImageUrl ?? this.customImageUrl,
      estimated: estimated ?? this.estimated,
    );
  }
}
