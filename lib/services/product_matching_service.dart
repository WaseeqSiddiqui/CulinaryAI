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
        .timeout(const Duration(seconds: 20));
    if (response.statusCode != 200) {
      throw StateError('Product matcher returned ${response.statusCode}');
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
