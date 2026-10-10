import 'package:culinary_ai/models/pantry_item_model.dart';
import 'package:culinary_ai/services/chef_chat_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final pantry = [
    PantryItemModel(
      id: 'milk',
      householdId: 'home',
      name: 'Milk',
      quantity: 1,
      unit: 'L',
      location: 'Fridge',
      lowStockThreshold: 0.5,
      updatedAt: DateTime(2026),
    ),
    PantryItemModel(
      id: 'pasta',
      householdId: 'home',
      name: 'Pasta',
      quantity: 400,
      unit: 'g',
      location: 'Pantry Shelf',
      lowStockThreshold: 100,
      updatedAt: DateTime(2026),
    ),
    PantryItemModel(
      id: 'tomato',
      householdId: 'home',
      name: 'Tomato',
      quantity: 2,
      unit: 'pcs',
      location: 'Fridge',
      lowStockThreshold: 2,
      updatedAt: DateTime(2026),
    ),
  ];

  test('answers pantry inventory questions', () {
    final answer = ChefChatService.answer('Do I have milk?', pantry);

    expect(answer, contains('1.0 L of Milk'));
  });

  test('recommends recipes using pantry match scores', () {
    final answer = ChefChatService.answer('What can I cook?', pantry);

    expect(answer, contains('Based on your pantry'));
    expect(answer, contains('% match'));
  });

  test('returns step-by-step instructions for a known recipe', () {
    final answer = ChefChatService.answer(
      'How do I cook tomato pasta?',
      pantry,
    );

    expect(answer, contains('Here is how to make'));
    expect(answer, contains('1.'));
    expect(answer, contains('Tomato'));
  });

  test('reports low-stock pantry items', () {
    final answer = ChefChatService.answer('What is low stock?', pantry);

    expect(answer, contains('Tomato'));
  });
}
