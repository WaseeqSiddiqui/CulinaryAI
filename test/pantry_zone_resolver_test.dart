import 'package:culinary_ai/models/pantry_item_model.dart';
import 'package:culinary_ai/models/receipt_vision_models.dart';
import 'package:culinary_ai/providers/pantry_provider.dart';
import 'package:culinary_ai/services/pantry_zone_resolver.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('PantryZoneResolver', () {
    test('normalizes supported aliases and invalid zones', () {
      expect(PantryZoneResolver.normalize(' refrigerator '), 'Fridge');
      expect(PantryZoneResolver.normalize('DEEP FREEZE'), 'Freezer');
      expect(PantryZoneResolver.normalize('pantry'), 'Pantry Shelf');
      expect(PantryZoneResolver.normalize('spices'), 'Spice Rack');
      expect(PantryZoneResolver.normalize('unknown room'), 'Pantry Shelf');
    });

    test('uses decisive modifiers before base ingredient names', () {
      expect(
        PantryZoneResolver.resolveForItem('Frozen Chicken Nuggets'),
        'Freezer',
      );
      expect(
        PantryZoneResolver.resolveForItem('Chicken Biryani Masala'),
        'Spice Rack',
      );
      expect(PantryZoneResolver.resolveForItem('Fish Masala'), 'Spice Rack');
      expect(
        PantryZoneResolver.resolveForItem('Coriander Seeds'),
        'Spice Rack',
      );
      expect(
        PantryZoneResolver.resolveForItem('Canned Tomatoes'),
        'Pantry Shelf',
      );
      expect(
        PantryZoneResolver.resolveForItem('Dalda Banaspati'),
        'Pantry Shelf',
      );
    });

    test('classifies common receipt items into expected zones', () {
      expect(PantryZoneResolver.resolveForItem('Milk Whole Gallon'), 'Fridge');
      expect(
        PantryZoneResolver.resolveForItem('Organic Bananas'),
        'Pantry Shelf',
      );
      expect(PantryZoneResolver.resolveForItem('Blueberries Pint'), 'Fridge');
      expect(
        PantryZoneResolver.resolveForItem('Red Chili Powder'),
        'Spice Rack',
      );
    });

    test('keeps a canonical suggested zone when no strong rule exists', () {
      expect(
        PantryZoneResolver.resolveForItem(
          'Uncatalogued Product',
          suggestedZone: 'freezer',
        ),
        'Freezer',
      );
    });
  });

  test('pantry models always hold a canonical location', () {
    final item = PantryItemModel(
      id: '1',
      householdId: 'h',
      name: 'Milk',
      quantity: 1,
      unit: 'L',
      location: ' refrigerator ',
      updatedAt: DateTime(2026),
    );

    expect(item.location, 'Fridge');
  });

  test('needs-review receipt rows require explicit user selection', () {
    final item = ValidatedReceiptItem.fromJson({
      'raw_text': 'UNKNOWN PRODUCT',
      'name': 'Unknown Product',
      'matched_ingredient': 'Unknown Product',
      'unit': 'pcs',
      'total_qty': 1,
      'is_food': true,
      'needs_review': true,
      'storage_zone': 'Pantry Shelf',
    });

    expect(item.isFood, isTrue);
    expect(item.needsReview, isTrue);
    expect(item.isSelected, isFalse);
  });

  test('dashboard zone groups are independent of the pantry filter', () {
    final pantry = PantryProvider();
    pantry.addItem(
      householdId: 'h',
      name: 'Milk',
      quantity: 1,
      unit: 'L',
      location: 'Fridge',
    );
    pantry.addItem(
      householdId: 'h',
      name: 'Rice',
      quantity: 1,
      unit: 'kg',
      location: 'Pantry Shelf',
    );

    pantry.setZoneFilter('Fridge');

    expect(pantry.itemsByZone['Fridge'], hasLength(1));
    expect(pantry.itemsByZone['Pantry Shelf'], isNull);
    expect(pantry.allItemsByZone['Fridge'], hasLength(1));
    expect(pantry.allItemsByZone['Pantry Shelf'], hasLength(1));
  });
}
