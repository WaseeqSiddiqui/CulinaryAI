import 'package:culinary_ai/models/pantry_item_model.dart';
import 'package:culinary_ai/services/pantry_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('persists a household pantry for offline use', () async {
    SharedPreferences.setMockInitialValues({});
    final service = PantryService();
    final item = PantryItemModel(
      id: 'item-1',
      householdId: 'household-1',
      name: 'Rice',
      quantity: 2,
      unit: 'kg',
      location: 'Pantry Shelf',
      updatedAt: DateTime(2026, 10, 11),
    );

    await service.saveLocal('household-1', [item]);
    final restored = await service.loadLocal('household-1');

    expect(restored, hasLength(1));
    expect(restored.single.name, 'Rice');
    expect(restored.single.householdId, 'household-1');
  });
}
