import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:culinary_ai/models/pantry_item_model.dart';
import 'package:culinary_ai/models/receipt_vision_models.dart';
import 'package:culinary_ai/providers/pantry_provider.dart';
import 'package:culinary_ai/services/household_alias_service.dart';
import 'package:culinary_ai/services/pantry_service.dart';
import 'package:culinary_ai/services/vision_api_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('VisionApiService Tests', () {
    test('parses ValidatedReceiptResponse JSON correctly', () {
      final json = {
        'scan_id': 'rcpt_12345',
        'store_name': 'Metro Cash & Carry',
        'date': '2026-10-15',
        'currency': 'PKR',
        'receipt_total': 1200.0,
        'discounts_total': 50.0,
        'calculated_items_total': 1150.0,
        'total_difference_percent': 0.0,
        'total_mismatch_warning': false,
        'image_hash': 'sha256_mock_hash',
        'items': [
          {
            'raw_text': '2 X MILK 1L 500',
            'name': 'Milk',
            'matched_ingredient': 'Milk',
            'pack_size': 1.0,
            'unit': 'L',
            'count': 2.0,
            'total_qty': 2.0,
            'line_price': 500.0,
            'is_food': true,
            'confidence': 0.98,
            'needs_review': false,
            'storage_zone': 'Fridge',
            'review_reasons': [],
          },
          {
            'raw_text': 'BANANA 100',
            'name': 'Banana',
            'matched_ingredient': 'Banana',
            'pack_size': null,
            'unit': 'pcs',
            'count': null,
            'total_qty': 1.0,
            'line_price': 100.0,
            'is_food': true,
            'confidence': 0.85,
            'needs_review': true,
            'storage_zone': 'Pantry Shelf',
            'review_reasons': ['Missing quantity'],
          },
        ],
      };

      final response = ValidatedReceiptResponse.fromJson(json);
      expect(response.scanId, 'rcpt_12345');
      expect(response.storeName, 'Metro Cash & Carry');
      expect(response.items.length, 2);
      expect(response.items[0].totalQty, 2.0);
      expect(response.items[0].unit, 'L');
      expect(response.items[0].storageZone, 'Fridge');
      expect(response.items[1].needsReview, isTrue);
    });

    test('isDuplicate detects and records previously scanned receipts', () async {
      const householdId = 'hh_test';
      const receiptHash = 'hash_metro_123';

      expect(await VisionApiService.isDuplicate(householdId, receiptHash), isFalse);
      await VisionApiService.markProcessed(householdId, receiptHash);
      expect(await VisionApiService.isDuplicate(householdId, receiptHash), isTrue);
    });

    test('parseReceipt returns parsed response on HTTP 200', () async {
      final mockClient = MockClient((request) async {
        expect(request.url.path, '/parse-receipt');
        expect(request.headers['X-User-Id'], 'user_1');
        return http.Response(
          jsonEncode({
            'scan_id': 'scan_test',
            'store_name': 'Test Mart',
            'receipt_total': 300.0,
            'items': [
              {
                'raw_text': 'EGGS 300',
                'name': 'Eggs',
                'matched_ingredient': 'Eggs',
                'total_qty': 12.0,
                'unit': 'pcs',
                'line_price': 300.0,
                'storage_zone': 'Fridge',
                'is_food': true,
              }
            ],
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      });

      final service = VisionApiService(client: mockClient);
      final result = await service.parseReceipt(
        imageBytes: Uint8List.fromList([1, 2, 3, 4, 5]),
        userId: 'user_1',
      );

      expect(result.storeName, 'Test Mart');
      expect(result.items.first.matchedIngredient, 'Eggs');
    });

    test('parseReceipt throws friendly error on 429 rate limit', () async {
      final mockClient = MockClient((_) async {
        return http.Response(
          jsonEncode({'detail': 'Daily scan limit reached (20 scans/day).'}),
          429,
        );
      });

      final service = VisionApiService(client: mockClient);
      expect(
        () => service.parseReceipt(
          imageBytes: Uint8List.fromList([1, 2, 3]),
          userId: 'user_rate',
        ),
        throwsA(
          isA<VisionApiException>().having(
            (e) => e.message,
            'message',
            contains('Daily scan limit reached'),
          ),
        ),
      );
    });
  });

  group('HouseholdAliasService Tests', () {
    test('saves and retrieves per-household aliases locally', () async {
      final service = HouseholdAliasService();
      const householdId = 'hh_alias_test';

      var aliases = await service.getAliases(householdId);
      expect(aliases.isEmpty, isTrue);

      await service.saveAlias(householdId, 'olpers milk 1l', 'Milk');
      await service.saveAlias(householdId, 'tom loose', 'Tomato');

      aliases = await service.getAliases(householdId);
      expect(aliases['olpers milk 1l'], 'Milk');
      expect(aliases['tom loose'], 'Tomato');
    });
  });

  group('PantryProvider Ingestion & Ledger Tests', () {
    test('ingestReceiptItems writes ledger purchase event and updates pantry', () async {
      final pantryService = PantryService();
      final provider = PantryProvider(service: pantryService);
      const householdId = 'hh_ledger_test';
      provider.bindHousehold(householdId);

      final items = [
        ValidatedReceiptItem(
          rawText: '2 X MILK 1L 500',
          name: 'Milk',
          matchedIngredient: 'Milk',
          totalQty: 2.0,
          unit: 'L',
          linePrice: 500.0,
          storageZone: 'Fridge',
          isSelected: true,
        ),
        ValidatedReceiptItem(
          rawText: 'DETERGENT 300',
          name: 'Detergent',
          matchedIngredient: 'Detergent',
          totalQty: 1.0,
          unit: 'pcs',
          linePrice: 300.0,
          storageZone: 'Pantry Shelf',
          isSelected: false, // User unselected non-food
        ),
      ];

      await provider.ingestReceiptItems(
        householdId: householdId,
        items: items,
        storeName: 'Metro',
        receiptDate: '2026-10-15',
        receiptTotal: 800.0,
        receiptHash: 'test_hash_1',
      );

      // Check pantry items
      final fridgeMilk = provider.allItems.firstWhere((it) => it.name == 'Milk');
      expect(fridgeMilk.quantity, 2.0);
      expect(fridgeMilk.unit, 'L');
      expect(fridgeMilk.location, 'Fridge');
      expect(fridgeMilk.addedVia, 'receipt_scan');

      // Unselected item should NOT be in pantry
      expect(provider.allItems.any((it) => it.name == 'Detergent'), isFalse);

      // Ingesting again with same name & zone should INCREMENT quantity
      await provider.ingestReceiptItems(
        householdId: householdId,
        items: [
          ValidatedReceiptItem(
            rawText: '1 X MILK 1L 250',
            name: 'Milk',
            matchedIngredient: 'Milk',
            totalQty: 1.0,
            unit: 'L',
            linePrice: 250.0,
            storageZone: 'Fridge',
            isSelected: true,
          ),
        ],
      );

      final updatedMilk = provider.allItems.firstWhere((it) => it.name == 'Milk');
      expect(updatedMilk.quantity, 3.0);
    });
  });
}
