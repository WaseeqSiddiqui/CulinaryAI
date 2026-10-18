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
    ProductCandidate(
      name: 'Value Milk 2L',
      size: '2 L',
      price: 520,
      inStock: false,
      index: 1,
    ),
  ];

  ProductMatchingService serviceReturning(Map<String, Object?> response) {
    return ProductMatchingService(
      baseUrl: 'http://example.test',
      client: MockClient((_) async => http.Response(jsonEncode(response), 200)),
    );
  }

  test('accepts a valid mocked matcher response', () async {
    final service = serviceReturning({
      'chosen_index': 0,
      'units_to_buy': 2,
      'confidence': 0.95,
      'reason': 'Exact coverage',
    });

    final result = await service.match(wanted, candidates);

    expect(result.chosenIndex, 0);
    expect(result.unitsToBuy, 2);
  });

  for (final invalidIndex in [-1, 2, 7]) {
    test('rejects invalid mocked matcher index $invalidIndex', () async {
      final service = serviceReturning({
        'chosen_index': invalidIndex,
        'units_to_buy': 1,
        'confidence': 0.9,
        'reason': 'Bad response',
      });

      await expectLater(
        service.match(wanted, candidates),
        throwsA(isA<FormatException>()),
      );
    });
  }

  for (final invalidUnits in [-1, 0, 11]) {
    test('rejects invalid mocked units_to_buy $invalidUnits', () async {
      final service = serviceReturning({
        'chosen_index': 0,
        'units_to_buy': invalidUnits,
        'confidence': 0.9,
        'reason': 'Bad response',
      });

      await expectLater(
        service.match(wanted, candidates),
        throwsA(isA<FormatException>()),
      );
    });
  }

  test(
    'rejects a mocked response that chooses an out-of-stock product',
    () async {
      final service = serviceReturning({
        'chosen_index': 1,
        'units_to_buy': 1,
        'confidence': 0.95,
        'reason': 'Unavailable choice',
      });

      await expectLater(
        service.match(wanted, candidates),
        throwsA(isA<FormatException>()),
      );
    },
  );

  test('accepts an explicit no-match response', () async {
    final service = serviceReturning({
      'chosen_index': null,
      'units_to_buy': null,
      'confidence': 0,
      'reason': 'Nothing fits',
    });

    final result = await service.match(wanted, candidates);

    expect(result.chosenIndex, isNull);
    expect(result.unitsToBuy, isNull);
  });

  test('accepts a valid general shopping-query normalization', () async {
    final service = serviceReturning({
      'search_query': 'milk',
      'canonical_name': 'milk',
      'confidence': 0.94,
      'changed': true,
      'reason': 'Corrected typo and removed brand',
    });

    final result = await service.normalize(
      const ShoppingListItem(
        id: 'typo',
        name: 'Olpers milkk',
        quantity: 1,
        unit: 'L',
      ),
    );

    expect(result.searchQuery, 'milk');
    expect(result.changed, isTrue);
  });

  test('rejects a blank normalized shopping query', () async {
    final service = serviceReturning({
      'search_query': ' ',
      'canonical_name': 'milk',
      'confidence': 0.9,
      'changed': true,
      'reason': 'Correction',
    });

    await expectLater(
      service.normalize(wanted),
      throwsA(isA<FormatException>()),
    );
  });
}
