import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/shopping_models.dart';
import '../models/store_models.dart';
import 'meal_planning_api_service.dart';

class ProductMatchingService {
  ProductMatchingService({http.Client? client, String? baseUrl})
    : _client = client ?? http.Client(),
      _baseUri = Uri.parse(baseUrl ?? MealPlanningApiService.defaultBaseUrl);

  final http.Client _client;
  final Uri _baseUri;

  Future<ShoppingQueryNormalization> normalize(ShoppingListItem wanted) async {
    final response = await _client
        .post(
          _baseUri.resolve('/normalize-shopping-query'),
          headers: const {'Content-Type': 'application/json'},
          body: jsonEncode({
            'name': wanted.name,
            'quantity': wanted.quantity,
            'unit': wanted.unit,
          }),
        )
        .timeout(const Duration(seconds: 12));
    if (response.statusCode != 200) {
      throw StateError('Query normalizer returned ${response.statusCode}');
    }
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    final query = body['search_query']?.toString().trim() ?? '';
    final canonical = body['canonical_name']?.toString().trim() ?? '';
    final confidence = (body['confidence'] as num?)?.toDouble();
    final changed = body['changed'];
    final reason = body['reason']?.toString().trim() ?? '';
    if (query.isEmpty ||
        query.length > 120 ||
        canonical.isEmpty ||
        canonical.length > 120 ||
        confidence == null ||
        confidence < 0 ||
        confidence > 1 ||
        changed is! bool ||
        reason.isEmpty) {
      throw const FormatException('Invalid shopping query normalization');
    }
    return ShoppingQueryNormalization(
      searchQuery: query,
      canonicalName: canonical,
      confidence: confidence,
      changed: changed,
      reason: reason,
    );
  }

  Future<ProductMatch> match(
    ShoppingListItem wanted,
    List<ProductCandidate> candidates,
  ) async {
    final response = await _client
        .post(
          _baseUri.resolve('/match-product'),
          headers: const {'Content-Type': 'application/json'},
          body: jsonEncode({
            'name': wanted.name,
            'quantity': wanted.quantity,
            'unit': wanted.unit,
            'candidates': candidates.map((item) => item.toMap()).toList(),
          }),
        )
        .timeout(const Duration(seconds: 24));
    if (response.statusCode != 200) {
      var detail = '';
      try {
        final errorBody = jsonDecode(response.body);
        if (errorBody is Map<String, dynamic>) {
          detail = errorBody['detail']?.toString().trim() ?? '';
        }
      } catch (_) {
        // Keep the status-only fallback for non-JSON proxy responses.
      }
      throw StateError(
        detail.isEmpty
            ? 'Product matcher returned ${response.statusCode}'
            : 'Product matcher returned ${response.statusCode}: $detail',
      );
    }
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    final index = body['chosen_index'] as int?;
    final units = body['units_to_buy'] as int?;
    if (index != null && (index < 0 || index >= candidates.length)) {
      throw const FormatException('Invalid chosen product index');
    }
    if (index != null && (units == null || units <= 0 || units > 10)) {
      throw const FormatException('Invalid units_to_buy');
    }
    if (index != null && !candidates[index].inStock) {
      throw const FormatException('Matcher chose an unavailable product');
    }
    return ProductMatch(
      chosenIndex: index,
      unitsToBuy: units,
      confidence: (body['confidence'] as num).toDouble(),
      reason: body['reason'] as String,
    );
  }
}
