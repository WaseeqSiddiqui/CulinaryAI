class ReconciledFridgeItem {
  final String detectedName;
  final String? matchedPantryId;
  final String? matchedName;
  final int? detectedCount;
  final double? detectedFillLevel;
  final String? labelSizeText;
  final double confidence;
  final String status; // 'verified', 'mismatch', 'new_item'
  final String? question;
  final double? currentQuantity;
  double? suggestedQuantity;
  final String unit;
  final bool estimated;
  final String? verifiedAt;
  bool isAccepted;

  ReconciledFridgeItem({
    required this.detectedName,
    this.matchedPantryId,
    this.matchedName,
    this.detectedCount,
    this.detectedFillLevel,
    this.labelSizeText,
    this.confidence = 1.0,
    required this.status,
    this.question,
    this.currentQuantity,
    this.suggestedQuantity,
    this.unit = 'pcs',
    this.estimated = true,
    this.verifiedAt,
    this.isAccepted = true,
  });

  factory ReconciledFridgeItem.fromJson(Map<String, dynamic> json) {
    return ReconciledFridgeItem(
      detectedName: json['detected_name'] as String? ?? '',
      matchedPantryId: json['matched_pantry_id'] as String?,
      matchedName: json['matched_name'] as String?,
      detectedCount: json['detected_count'] as int?,
      detectedFillLevel: (json['detected_fill_level'] as num?)?.toDouble(),
      labelSizeText: json['label_size_text'] as String?,
      confidence: (json['confidence'] as num?)?.toDouble() ?? 1.0,
      status: json['status'] as String? ?? 'verified',
      question: json['question'] as String?,
      currentQuantity: (json['current_quantity'] as num?)?.toDouble(),
      suggestedQuantity: (json['suggested_quantity'] as num?)?.toDouble(),
      unit: json['unit'] as String? ?? 'pcs',
      estimated: json['estimated'] as bool? ?? true,
      verifiedAt: json['verified_at'] as String?,
      isAccepted: json['status'] != 'mismatch', // Mismatches require explicit confirmation
    );
  }
}

class FridgeScanResponse {
  final String scanId;
  final List<ReconciledFridgeItem> reconciledItems;
  final int verifiedCount;
  final int mismatchCount;
  final int newItemsCount;

  FridgeScanResponse({
    required this.scanId,
    required this.reconciledItems,
    this.verifiedCount = 0,
    this.mismatchCount = 0,
    this.newItemsCount = 0,
  });

  factory FridgeScanResponse.fromJson(Map<String, dynamic> json) {
    return FridgeScanResponse(
      scanId: json['scan_id'] as String? ?? '',
      reconciledItems: (json['reconciled_items'] as List<dynamic>? ?? [])
          .map((item) => ReconciledFridgeItem.fromJson(item as Map<String, dynamic>))
          .toList(),
      verifiedCount: json['verified_count'] as int? ?? 0,
      mismatchCount: json['mismatch_count'] as int? ?? 0,
      newItemsCount: json['new_items_count'] as int? ?? 0,
    );
  }
}
