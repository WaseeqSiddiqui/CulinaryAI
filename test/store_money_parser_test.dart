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
}
