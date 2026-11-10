import '../services/food_image_service.dart';
import '../services/pantry_zone_resolver.dart';

enum ExpirySource {
  unknown,
  labelScan,
  receiptEstimate,
  manual,
  openedEstimate,
}

enum ExpiryConfidence { low, medium, high }

enum ExpiryStatus { unknown, fresh, useSoon, expired }

class PantryItemModel {
  final String id;
  final String householdId;
  final String name;
  final double quantity;
  final String unit;
  final String category;
  final String? packageType;
  final double? packageCount;
  final double? quantityPerPackage;
  final String location;
  final double lowStockThreshold;
  final String addedVia; // 'manual' or 'receipt_scan'
  final DateTime updatedAt;
  final String? customImageUrl;
  final bool estimated;
  final DateTime? purchaseDate;
  final DateTime? expiryDate;
  final DateTime? openedDate;
  final ExpirySource expirySource;
  final ExpiryConfidence expiryConfidence;
  final bool expiryUserConfirmed;

  PantryItemModel({
    required this.id,
    required this.householdId,
    required this.name,
    required this.quantity,
    required this.unit,
    this.category = 'Other',
    this.packageType,
    this.packageCount,
    this.quantityPerPackage,
    required String location,
    this.lowStockThreshold = 1.0,
    this.addedVia = 'manual',
    required this.updatedAt,
    this.customImageUrl,
    this.estimated = false,
    this.purchaseDate,
    this.expiryDate,
    this.openedDate,
    this.expirySource = ExpirySource.unknown,
    this.expiryConfidence = ExpiryConfidence.low,
    this.expiryUserConfirmed = false,
  }) : location = PantryZoneResolver.normalize(location);

  bool get isLowStock => quantity <= lowStockThreshold;
  double get remainingQuantity => quantity;
  bool get isOpened => openedDate != null;
  bool get hasKnownPackageCapacity =>
      packageType != null &&
      packageType!.trim().isNotEmpty &&
      packageCount != null &&
      quantityPerPackage != null &&
      packageCount! > 0 &&
      quantityPerPackage! > 0;
  bool get needsPackageDetails =>
      !hasKnownPackageCapacity &&
      const {
        'pc',
        'pcs',
        'piece',
        'pieces',
        'pack',
        'packs',
      }.contains(unit.trim().toLowerCase()) &&
      RegExp(
        r'\b(sauce|oil|milk|cream|vinegar|ketchup|mayonnaise|drink|juice|water)\b',
        caseSensitive: false,
      ).hasMatch(name);

  int? daysUntilExpiryAt(DateTime now) {
    final date = expiryDate;
    if (date == null) return null;
    final today = DateTime(now.year, now.month, now.day);
    final expiry = DateTime(date.year, date.month, date.day);
    return expiry.difference(today).inDays;
  }

  int? get daysUntilExpiry => daysUntilExpiryAt(DateTime.now());

  ExpiryStatus expiryStatusAt(DateTime now) {
    final days = daysUntilExpiryAt(now);
    if (days == null) return ExpiryStatus.unknown;
    if (days < 0) return ExpiryStatus.expired;
    if (days <= 3) return ExpiryStatus.useSoon;
    return ExpiryStatus.fresh;
  }

  ExpiryStatus get expiryStatus => expiryStatusAt(DateTime.now());
  bool get hasEstimatedExpiry =>
      expiryDate != null &&
      !expiryUserConfirmed &&
      {
        ExpirySource.receiptEstimate,
        ExpirySource.openedEstimate,
      }.contains(expirySource);

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
      'category': category,
      'package_type': packageType,
      'package_count': packageCount,
      'quantity_per_package': quantityPerPackage,
      'remaining_quantity': quantity,
      'package_status': isOpened ? 'opened' : 'unopened',
      'location': location,
      'low_stock_threshold': lowStockThreshold,
      'added_via': addedVia,
      'updated_at': updatedAt.toIso8601String(),
      'custom_image_url': customImageUrl,
      'estimated': estimated,
      'purchase_date': purchaseDate?.toIso8601String(),
      'expiry_date': expiryDate?.toIso8601String(),
      'opened_date': openedDate?.toIso8601String(),
      'expiry_source': expirySource.name,
      'expiry_confidence': expiryConfidence.name,
      'expiry_user_confirmed': expiryUserConfirmed,
    };
  }

  factory PantryItemModel.fromMap(Map<String, dynamic> map, String id) {
    return PantryItemModel(
      id: id,
      householdId: map['household_id'] ?? '',
      name: map['name'] ?? '',
      quantity:
          (map['remaining_quantity'] as num?)?.toDouble() ??
          (map['quantity'] as num?)?.toDouble() ??
          0.0,
      unit: map['unit'] ?? 'pcs',
      category: map['category'] ?? 'Other',
      packageType: map['package_type']?.toString(),
      packageCount: (map['package_count'] as num?)?.toDouble(),
      quantityPerPackage: (map['quantity_per_package'] as num?)?.toDouble(),
      location: map['location'] ?? 'Pantry Shelf',
      lowStockThreshold:
          (map['low_stock_threshold'] as num?)?.toDouble() ?? 1.0,
      addedVia: map['added_via'] ?? 'manual',
      updatedAt: map['updated_at'] != null
          ? DateTime.tryParse(map['updated_at']) ?? DateTime.now()
          : DateTime.now(),
      customImageUrl: map['custom_image_url'],
      estimated: map['estimated'] as bool? ?? false,
      purchaseDate: _date(map['purchase_date']),
      expiryDate: _date(map['expiry_date']),
      openedDate: _date(map['opened_date']),
      expirySource: _enumByName(
        ExpirySource.values,
        map['expiry_source'],
        ExpirySource.unknown,
      ),
      expiryConfidence: _enumByName(
        ExpiryConfidence.values,
        map['expiry_confidence'],
        ExpiryConfidence.low,
      ),
      expiryUserConfirmed: map['expiry_user_confirmed'] as bool? ?? false,
    );
  }

  PantryItemModel copyWith({
    String? id,
    String? householdId,
    String? name,
    double? quantity,
    String? unit,
    String? category,
    Object? packageType = _unset,
    Object? packageCount = _unset,
    Object? quantityPerPackage = _unset,
    String? location,
    double? lowStockThreshold,
    String? addedVia,
    DateTime? updatedAt,
    String? customImageUrl,
    bool? estimated,
    Object? purchaseDate = _unset,
    Object? expiryDate = _unset,
    Object? openedDate = _unset,
    ExpirySource? expirySource,
    ExpiryConfidence? expiryConfidence,
    bool? expiryUserConfirmed,
  }) {
    return PantryItemModel(
      id: id ?? this.id,
      householdId: householdId ?? this.householdId,
      name: name ?? this.name,
      quantity: quantity ?? this.quantity,
      unit: unit ?? this.unit,
      category: category ?? this.category,
      packageType: identical(packageType, _unset)
          ? this.packageType
          : packageType as String?,
      packageCount: identical(packageCount, _unset)
          ? this.packageCount
          : packageCount as double?,
      quantityPerPackage: identical(quantityPerPackage, _unset)
          ? this.quantityPerPackage
          : quantityPerPackage as double?,
      location: location ?? this.location,
      lowStockThreshold: lowStockThreshold ?? this.lowStockThreshold,
      addedVia: addedVia ?? this.addedVia,
      updatedAt: updatedAt ?? this.updatedAt,
      customImageUrl: customImageUrl ?? this.customImageUrl,
      estimated: estimated ?? this.estimated,
      purchaseDate: identical(purchaseDate, _unset)
          ? this.purchaseDate
          : purchaseDate as DateTime?,
      expiryDate: identical(expiryDate, _unset)
          ? this.expiryDate
          : expiryDate as DateTime?,
      openedDate: identical(openedDate, _unset)
          ? this.openedDate
          : openedDate as DateTime?,
      expirySource: expirySource ?? this.expirySource,
      expiryConfidence: expiryConfidence ?? this.expiryConfidence,
      expiryUserConfirmed: expiryUserConfirmed ?? this.expiryUserConfirmed,
    );
  }

  static const Object _unset = Object();

  static DateTime? _date(Object? value) =>
      value is String ? DateTime.tryParse(value) : null;

  static T _enumByName<T extends Enum>(
    List<T> values,
    Object? value,
    T fallback,
  ) {
    for (final item in values) {
      if (item.name == value) return item;
    }
    return fallback;
  }
}
