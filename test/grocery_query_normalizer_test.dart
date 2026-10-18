import 'package:culinary_ai/services/grocery_query_normalizer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('uses a confident general typo or brand normalization first', () {
    expect(
      GroceryQueryNormalizer.searchQueries(
        'Himalia aaples',
        'apples',
        confidence: 0.96,
      ),
      ['apples', 'Himalia aaples'],
    );
    expect(
      GroceryQueryNormalizer.searchQueries(
        'Olpers milkk',
        'milk',
        confidence: 0.92,
      ),
      ['milk', 'Olpers milkk'],
    );
  });

  test('does not use low-confidence normalization', () {
    expect(
      GroceryQueryNormalizer.searchQueries(
        'some unclear item',
        'milk',
        confidence: 0.4,
      ),
      ['some unclear item'],
    );
  });

  test('rejects normalization that drops product form', () {
    expect(
      GroceryQueryNormalizer.isSafeNormalization('Apple juice 1L', 'apples'),
      isFalse,
    );
    expect(
      GroceryQueryNormalizer.isSafeNormalization('Milk powdr', 'milk'),
      isFalse,
    );
    expect(
      GroceryQueryNormalizer.isSafeNormalization(
        'Sugar free mango drink',
        'mango drink',
      ),
      isFalse,
    );
  });

  test('allows spelling cleanup while retaining product form', () {
    expect(
      GroceryQueryNormalizer.isSafeNormalization(
        'Nestle apple juce',
        'apple juice',
      ),
      isTrue,
    );
    expect(
      GroceryQueryNormalizer.isSafeNormalization(
        'Everyday milk powdr',
        'milk powder',
      ),
      isTrue,
    );
  });

  test('approves a candidate containing the normalized core grocery', () {
    expect(
      GroceryQueryNormalizer.isApprovedEquivalent(
        'apples',
        'Fresh Red Apple 1kg',
      ),
      isTrue,
    );
    expect(
      GroceryQueryNormalizer.isApprovedEquivalent(
        'milk',
        'Milk Pak UHT Milk 1L',
      ),
      isTrue,
    );
    expect(
      GroceryQueryNormalizer.isApprovedEquivalent('apple juice', 'Red Apples'),
      isFalse,
    );
  });
}
