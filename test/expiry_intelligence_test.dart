import 'package:culinary_ai/models/pantry_item_model.dart';
import 'package:culinary_ai/services/expiry_estimation_service.dart';
import 'package:culinary_ai/services/expiry_label_parser.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('expiry labels', () {
    test('reads a contextual date and requires user confirmation', () {
      final result = ExpiryLabelParser.parse('LOT A8 EXP: 17/11/2026');
      expect(result?.date, DateTime(2026, 11, 17));
      expect(result?.confidence, ExpiryConfidence.high);
      expect(result?.requiresConfirmation, isTrue);
    });

    test('rejects impossible dates', () {
      expect(ExpiryLabelParser.parse('EXP 32/19/2026'), isNull);
    });
  });

  test('receipt estimation uses perishable category shelf life', () {
    final estimate = ExpiryEstimationService.estimate(
      itemName: 'Fresh milk',
      storageZone: 'Fridge',
      purchasedAt: DateTime(2026, 10, 17),
    );
    expect(estimate?.date, DateTime(2026, 10, 24));
  });

  test('opened estimate never extends beyond printed expiry', () {
    final estimate = ExpiryEstimationService.estimateAfterOpening(
      itemName: 'Milk',
      openedAt: DateTime(2026, 10, 17),
      printedExpiry: DateTime(2026, 10, 19),
    );
    expect(estimate.date, DateTime(2026, 10, 19));
  });

  test('old stored records remain migration safe', () {
    final item = PantryItemModel.fromMap({
      'name': 'Rice',
      'quantity': 1,
      'location': 'Pantry Shelf',
    }, 'rice');
    expect(item.expiryDate, isNull);
    expect(item.expirySource, ExpirySource.unknown);
  });
}
