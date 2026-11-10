import 'package:culinary_ai/services/store_money_parser.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('parses Foodpanda rupee prices without treating Rs dot as decimal', () {
    expect(parseStoreMoney('Rs. 348.84'), 348.84);
    expect(parseStoreMoney('Rs. 1,299.50'), 1299.50);
    expect(parseStoreMoney('PKR 25,000'), 25000);
  });

  test('returns null when a price is absent', () {
    expect(parseStoreMoney('Unavailable'), isNull);
    expect(parseStoreMoney(null), isNull);
  });

  test('rejects ambiguous, negative and malformed amounts', () {
    for (final text in [
      'Rs -500',
      'Rs 100 Rs 200',
      'Rs 1,23',
      'Rs 500.999',
      '20% off Rs 300',
    ]) {
      expect(parseStoreMoney(text), isNull, reason: text);
    }
    expect(parseStoreMoney('Rs.\u00a01,200.50'), 1200.50);
  });
}
