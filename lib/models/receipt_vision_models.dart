class ValidatedReceiptResponse {
  final String scanId;
  final String? storeName;
  final String? date;
  final String? currency;
  final double? receiptTotal;
  final double discountsTotal;
  final double calculatedItemsTotal;
  final double totalDifferencePercent;
  final bool totalMismatchWarning;
  final List<ValidatedReceiptItem> items;
  final String? imageHash;

  ValidatedReceiptResponse({
    required this.scanId,
    this.storeName,
    this.date,
    this.currency,
    this.receiptTotal,
    this.discountsTotal = 0.0,
    this.calculatedItemsTotal = 0.0,
    this.totalDifferencePercent = 0.0,
    this.totalMismatchWarning = false,
    required this.items,
    this.imageHash,
  });

  factory ValidatedReceiptResponse.fromJson(Map<String, dynamic> json) {
    return ValidatedReceiptResponse(
      scanId: json['scan_id'] as String? ?? '',
      storeName: json['store_name'] as String?,
      date: json['date'] as String?,
      currency: json['currency'] as String?,
      receiptTotal: (json['receipt_total'] as num?)?.toDouble(),
      discountsTotal: (json['discounts_total'] as num?)?.toDouble() ?? 0.0,
      calculatedItemsTotal:
          (json['calculated_items_total'] as num?)?.toDouble() ?? 0.0,
      totalDifferencePercent:
          (json['total_difference_percent'] as num?)?.toDouble() ?? 0.0,
      totalMismatchWarning: json['total_mismatch_warning'] as bool? ?? false,
      items: (json['items'] as List<dynamic>? ?? [])
          .map((item) => ValidatedReceiptItem.fromJson(item as Map<String, dynamic>))
          .toList(),
      imageHash: json['image_hash'] as String?,
    );
  }
}

class ValidatedReceiptItem {
  String rawText;
  String name;
  String matchedIngredient;
  double? packSize;
  String unit;
  double? count;
  double totalQty;
  double? linePrice;
  bool isFood;
  double confidence;
  bool needsReview;
  String storageZone;
  List<String> reviewReasons;
  bool isSelected;

  ValidatedReceiptItem({
    required this.rawText,
    required this.name,
    required this.matchedIngredient,
    this.packSize,
    required this.unit,
    this.count,
    required this.totalQty,
    this.linePrice,
    this.isFood = true,
    this.confidence = 1.0,
    this.needsReview = false,
    this.storageZone = 'Pantry Shelf',
    this.reviewReasons = const [],
    this.isSelected = true,
  });

  factory ValidatedReceiptItem.fromJson(Map<String, dynamic> json) {
    final isFood = json['is_food'] as bool? ?? true;
    final needsReview = json['needs_review'] as bool? ?? false;
    return ValidatedReceiptItem(
      rawText: json['raw_text'] as String? ?? '',
      name: json['name'] as String? ?? '',
      matchedIngredient: json['matched_ingredient'] as String? ?? json['name'] ?? '',
      packSize: (json['pack_size'] as num?)?.toDouble(),
      unit: json['unit'] as String? ?? 'pcs',
      count: (json['count'] as num?)?.toDouble(),
      totalQty: (json['total_qty'] as num?)?.toDouble() ?? 1.0,
      linePrice: (json['line_price'] as num?)?.toDouble(),
      isFood: isFood,
      confidence: (json['confidence'] as num?)?.toDouble() ?? 1.0,
      needsReview: needsReview,
      storageZone: json['storage_zone'] as String? ?? 'Pantry Shelf',
      reviewReasons: (json['review_reasons'] as List<dynamic>? ?? [])
          .map((r) => r.toString())
          .toList(),
      isSelected: isFood && !needsReview,
    );
  }

  ValidatedReceiptItem copyWith({
    String? rawText,
    String? name,
    String? matchedIngredient,
    double? packSize,
    String? unit,
    double? count,
    double? totalQty,
    double? linePrice,
    bool? isFood,
    double? confidence,
    bool? needsReview,
    String? storageZone,
    List<String>? reviewReasons,
    bool? isSelected,
  }) {
    return ValidatedReceiptItem(
      rawText: rawText ?? this.rawText,
      name: name ?? this.name,
      matchedIngredient: matchedIngredient ?? this.matchedIngredient,
      packSize: packSize ?? this.packSize,
      unit: unit ?? this.unit,
      count: count ?? this.count,
      totalQty: totalQty ?? this.totalQty,
      linePrice: linePrice ?? this.linePrice,
      isFood: isFood ?? this.isFood,
      confidence: confidence ?? this.confidence,
      needsReview: needsReview ?? this.needsReview,
      storageZone: storageZone ?? this.storageZone,
      reviewReasons: reviewReasons ?? this.reviewReasons,
      isSelected: isSelected ?? this.isSelected,
    );
  }
}
