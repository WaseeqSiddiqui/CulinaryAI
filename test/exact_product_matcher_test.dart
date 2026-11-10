import 'package:culinary_ai/models/shopping_models.dart';
import 'package:culinary_ai/models/store_models.dart';
import 'package:culinary_ai/services/exact_product_matcher.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  ShoppingListItem wanted(String name, double quantity, String unit) =>
      ShoppingListItem(id: 'test', name: name, quantity: quantity, unit: unit);
  ProductCandidate product(
    String name, {
    double price = 300,
    bool inStock = true,
  }) => ProductCandidate(name: name, price: price, inStock: inStock, index: 0);

  test('covers litres from printed millilitre packs without online AI', () {
    final result = ExactProductMatcher.match(wanted('Milk', 2, 'L'), [
      product('Fresh Milk 1000ml'),
    ]);
    expect(result?.chosenIndex, 0);
    expect(result?.unitsToBuy, 2);
  });
  test('prefers exact quantity coverage before a cheaper oversized pack', () {
    final result = ExactProductMatcher.match(wanted('Rice', 1, 'kg'), [
      product('Rice 1500g', price: 250),
      product('Rice 1kg', price: 300),
    ]);
    expect(result?.chosenIndex, 1);
  });
  test('does not substitute milk powder or flavoured milk for milk', () {
    for (final name in [
      'Milk Powder 1kg',
      'Chocolate Milk 1L',
      'Lactose Free Milk 1L',
      'Baby Formula Milk 1L',
      'Coconut Milk 1L',
    ]) {
      expect(
        ExactProductMatcher.match(wanted('Milk', 1, 'L'), [product(name)]),
        isNull,
      );
    }
  });

  test(
    'does not confuse lemon with lemon grass or pieces with weighted produce',
    () {
      expect(
        ExactProductMatcher.match(wanted('Lemon', 2, 'pcs'), [
          product('Lemon Grass 50g'),
        ]),
        isNull,
      );
      expect(
        ExactProductMatcher.match(wanted('Tomato', 2, 'pcs'), [
          product('Tomato 500g'),
        ]),
        isNull,
      );
      expect(
        ExactProductMatcher.match(wanted('Chickpeas', 1, 'pcs'), [
          product('Black Chickpeas (Kala Chana) 500g'),
        ]),
        isNull,
      );
    },
  );
  test('never assumes density or an unprinted package size', () {
    expect(
      ExactProductMatcher.match(wanted('Milk', 1, 'L'), [product('Milk 1kg')]),
      isNull,
    );
    expect(
      ExactProductMatcher.match(wanted('Rice', 1, 'kg'), [product('Rice')]),
      isNull,
    );
  });
  test('preserves an explicitly requested pack size', () {
    expect(
      ExactProductMatcher.match(wanted('Milk 1L', 1, 'L'), [
        product('Milk 2L'),
      ]),
      isNull,
    );
  });
  test('leaves multipacks and unsafe excess for review', () {
    expect(
      ExactProductMatcher.match(wanted('Milk', 1, 'L'), [
        product('Milk 6 x 250ml'),
      ]),
      isNull,
    );
    expect(
      ExactProductMatcher.match(wanted('Rice', 100, 'g'), [
        product('Rice 1kg'),
      ]),
      isNull,
    );
  });
  test('allows a requested retail package for a labelled condiment', () {
    final result = ExactProductMatcher.match(wanted('Soy Sauce', 1, 'pcs'), [
      product('Brand Soy Sauce 300ml'),
    ]);
    expect(result?.unitsToBuy, 1);
  });
  test(
    'rejects unavailable products, invalid prices and unsupported units',
    () {
      expect(
        ExactProductMatcher.match(wanted('Milk', 1, 'L'), [
          product('Milk 1L', inStock: false),
        ]),
        isNull,
      );
      expect(
        ExactProductMatcher.match(wanted('Milk', 1, 'L'), [
          product('Milk 1L', price: double.nan),
        ]),
        isNull,
      );
      expect(
        ExactProductMatcher.match(wanted('Milk', 1, 'cup'), [
          product('Milk 1L'),
        ]),
        isNull,
      );
    },
  );
}
