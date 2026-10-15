import 'dart:convert';

import 'package:culinary_ai/models/shopping_models.dart';
import 'package:culinary_ai/models/store_models.dart';
import 'package:culinary_ai/services/product_matching_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  const wanted = ShoppingListItem(
    id: 'milk',
    name: 'Milk',
    quantity: 2,
    unit: 'L',
  );
  const candidates = [
    ProductCandidate(
      name: 'Fresh Milk 1L',
      size: '1 L',
      price: 300,
      inStock: true,
      index: 0,
    ),
  ];

  test('validates a mocked matcher response', () async {
    final service = ProductMatchingService(
      baseUrl: 'http://example.test',
      client: MockClient(
        (_) async => http.Response(
          jsonEncode({
            'chosen_index': 0,
            'units_to_buy': 2,
            'confidence': 0.95,
            'reason': 'Exact coverage',
          }),
          200,
        ),
      ),
    );
    final result = await service.match(wanted, candidates);
    expect(result.chosenIndex, 0);
    expect(result.unitsToBuy, 2);
  });

  test('rejects an out-of-range mocked matcher index', () async {
    final service = ProductMatchingService(
      baseUrl: 'http://example.test',
      client: MockClient(
        (_) async => http.Response(
          jsonEncode({
            'chosen_index': 7,
            'units_to_buy': 1,
            'confidence': 0.9,
            'reason': 'Bad response',
          }),
          200,
        ),
      ),
    );
    expect(
      () => service.match(wanted, candidates),
      throwsA(isA<FormatException>()),
    );
  });
}
