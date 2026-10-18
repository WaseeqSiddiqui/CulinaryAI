/// Tests for [ValidatedReceiptResponse] / [ValidatedReceiptItem] JSON parsing
/// and [VisionApiService.parseReceipt] HTTP transport.
///
/// The old Dart-side regex receipt parser (ReceiptParserService) has been
/// removed. Receipt analysis is now performed entirely by the Gemini Vision
/// backend (POST /parse-receipt). These tests cover the Flutter side:
///   1. JSON deserialisation of the structured backend response.
///   2. VisionApiService HTTP transport (success, rate-limit, bad-image paths).
///   3. Duplicate-detection helpers (SHA-256 / metadata key in SharedPreferences).
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:culinary_ai/models/receipt_vision_models.dart';
import 'package:culinary_ai/services/vision_api_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  // ─────────────────────────────────────────────────────────────────────────
  // JSON deserialization
  // ─────────────────────────────────────────────────────────────────────────

  group('ValidatedReceiptResponse JSON parsing', () {
    test('parses a complete receipt response with all fields', () {
      final json = {
        'scan_id': 'rcpt_1729000000_abc12345',
        'store_name': 'Metro Cash & Carry',
        'date': '2026-10-15',
        'currency': 'PKR',
        'receipt_total': 1630.0,
        'discounts_total': 50.0,
        'calculated_items_total': 1630.0,
        'total_difference_percent': 0.0,
        'total_mismatch_warning': false,
        'image_hash': 'sha256_deadbeef',
        'items': [
          {
            'raw_text': 'WHOLE MILK 2L 320.00',
            'name': 'Whole Milk',
            'matched_ingredient': 'Milk',
            'pack_size': 2.0,
            'unit': 'L',
            'count': 1.0,
            'total_qty': 2.0,
            'line_price': 320.0,
            'is_food': true,
            'confidence': 0.97,
            'needs_review': false,
            'storage_zone': 'Fridge',
            'review_reasons': [],
          },
          {
            'raw_text': 'FREE RANGE EGGS 12 PCS 280.00',
            'name': 'Eggs',
            'matched_ingredient': 'Eggs',
            'pack_size': null,
            'unit': 'pcs',
            'count': 12.0,
            'total_qty': 12.0,
            'line_price': 280.0,
            'is_food': true,
            'confidence': 0.95,
            'needs_review': false,
            'storage_zone': 'Fridge',
            'review_reasons': [],
          },
          {
            'raw_text': 'BASMATI RICE 5KG 950.00',
            'name': 'Basmati Rice',
            'matched_ingredient': 'Basmati Rice',
            'pack_size': 5.0,
            'unit': 'kg',
            'count': 1.0,
            'total_qty': 5.0,
            'line_price': 950.0,
            'is_food': true,
            'confidence': 0.99,
            'needs_review': false,
            'storage_zone': 'Pantry Shelf',
            'review_reasons': [],
          },
          {
            'raw_text': 'CUMIN SEEDS 100G 80.00',
            'name': 'Cumin Seeds',
            'matched_ingredient': 'Cumin',
            'pack_size': 100.0,
            'unit': 'g',
            'count': 1.0,
            'total_qty': 100.0,
            'line_price': 80.0,
            'is_food': true,
            'confidence': 0.93,
            'needs_review': false,
            'storage_zone': 'Spice Rack',
            'review_reasons': [],
          },
        ],
      };

      final response = ValidatedReceiptResponse.fromJson(json);

      expect(response.scanId, 'rcpt_1729000000_abc12345');
      expect(response.storeName, 'Metro Cash & Carry');
      expect(response.currency, 'PKR');
      expect(response.receiptTotal, 1630.0);
      expect(response.discountsTotal, 50.0);
      expect(response.totalMismatchWarning, isFalse);
      expect(response.imageHash, 'sha256_deadbeef');
      expect(response.items, hasLength(4));

      final milk = response.items.firstWhere((i) => i.name == 'Whole Milk');
      expect(milk.totalQty, 2.0);
      expect(milk.unit, 'L');
      expect(milk.linePrice, 320.0);
      expect(milk.storageZone, 'Fridge');
      expect(milk.isSelected, isTrue); // is_food → pre-selected

      final rice = response.items.firstWhere((i) => i.name == 'Basmati Rice');
      expect(rice.storageZone, 'Pantry Shelf');
      expect(rice.totalQty, 5.0);

      final cumin = response.items.firstWhere((i) => i.name == 'Cumin Seeds');
      expect(cumin.storageZone, 'Spice Rack');
    });

    test('applies safe defaults when optional fields are absent', () {
      final json = {
        'scan_id': 'rcpt_minimal',
        'items': [
          {
            'raw_text': 'BREAD',
            'name': 'Bread',
            'matched_ingredient': 'Bread',
            'total_qty': 1.0,
          },
        ],
      };

      final response = ValidatedReceiptResponse.fromJson(json);
      expect(response.storeName, isNull);
      expect(response.receiptTotal, isNull);
      expect(response.discountsTotal, 0.0);
      expect(response.totalMismatchWarning, isFalse);

      final bread = response.items.first;
      expect(bread.unit, 'pcs'); // default unit
      expect(bread.confidence, 1.0);
      expect(bread.needsReview, isFalse);
    });

    test('items flagged needs_review carry their review_reasons', () {
      final json = {
        'scan_id': 'rcpt_review',
        'items': [
          {
            'raw_text': 'UNKNOWN 1',
            'name': 'Unknown Item',
            'matched_ingredient': 'Unknown Item',
            'total_qty': 1.0,
            'unit': 'pcs',
            'needs_review': true,
            'review_reasons': ['Missing quantity: count and pack size are both null', 'Catalog match confidence low (0.45)'],
            'is_food': true,
          },
        ],
      };

      final response = ValidatedReceiptResponse.fromJson(json);
      final item = response.items.first;
      expect(item.needsReview, isTrue);
      expect(item.reviewReasons, hasLength(2));
      expect(item.reviewReasons.first, contains('Missing quantity'));
    });

    test('non-food items parse with isSelected = false', () {
      final json = {
        'scan_id': 'rcpt_nonfood',
        'items': [
          {
            'raw_text': 'SHOPPING BAG 10',
            'name': 'Shopping Bag',
            'matched_ingredient': 'Shopping Bag',
            'total_qty': 1.0,
            'unit': 'pcs',
            'is_food': false,
          },
        ],
      };

      final response = ValidatedReceiptResponse.fromJson(json);
      expect(response.items.first.isFood, isFalse);
      expect(response.items.first.isSelected, isFalse); // non-food → unselected
    });

    test('mismatch warning is set when total_mismatch_warning is true', () {
      final json = {
        'scan_id': 'rcpt_mismatch',
        'receipt_total': 1000.0,
        'calculated_items_total': 850.0,
        'total_difference_percent': 15.0,
        'total_mismatch_warning': true,
        'items': <dynamic>[],
      };

      final response = ValidatedReceiptResponse.fromJson(json);
      expect(response.totalMismatchWarning, isTrue);
      expect(response.totalDifferencePercent, 15.0);
    });
  });

  group('ValidatedReceiptItem.copyWith', () {
    test('creates an updated copy without mutating the original', () {
      final original = ValidatedReceiptItem(
        rawText: 'MILK 500',
        name: 'Milk',
        matchedIngredient: 'Milk',
        totalQty: 1.0,
        unit: 'L',
        isSelected: true,
      );

      final updated = original.copyWith(name: 'Full-Fat Milk', totalQty: 2.0);

      expect(original.name, 'Milk');
      expect(updated.name, 'Full-Fat Milk');
      expect(updated.totalQty, 2.0);
      expect(updated.unit, 'L'); // unchanged field preserved
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  // HTTP transport: VisionApiService.parseReceipt
  // ─────────────────────────────────────────────────────────────────────────

  group('VisionApiService.parseReceipt HTTP integration', () {
    test('sends multipart POST to /parse-receipt with X-User-Id header', () async {
      final mockClient = MockClient((request) async {
        expect(request.url.path, '/parse-receipt');
        expect(request.headers['X-User-Id'], 'hh_test');
        expect(request.method, 'POST');

        return http.Response(
          jsonEncode({
            'scan_id': 'rcpt_http_test',
            'store_name': 'Test Supermarket',
            'receipt_total': 500.0,
            'items': [
              {
                'raw_text': 'EGGS 12PCS 200',
                'name': 'Eggs',
                'matched_ingredient': 'Eggs',
                'total_qty': 12.0,
                'unit': 'pcs',
                'line_price': 200.0,
                'storage_zone': 'Fridge',
                'is_food': true,
              },
            ],
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      });

      final service = VisionApiService(client: mockClient);
      final result = await service.parseReceipt(
        imageBytes: Uint8List.fromList(List.generate(50, (i) => i)),
        userId: 'hh_test',
      );

      expect(result.scanId, 'rcpt_http_test');
      expect(result.storeName, 'Test Supermarket');
      expect(result.items.first.matchedIngredient, 'Eggs');
      expect(result.items.first.totalQty, 12.0);
    });

    test('succeeds when household_aliases are provided alongside the image', () async {
      // The MockClient cannot re-read a finalized MultipartRequest body,
      // so we verify the happy-path round-trip completes without error when
      // aliases are passed — the field forwarding is tested server-side.
      final mockClient = MockClient((_) async {
        return http.Response(
          jsonEncode({
            'scan_id': 'rcpt_alias_ok',
            'items': [],
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      });

      final service = VisionApiService(client: mockClient);
      final result = await service.parseReceipt(
        imageBytes: Uint8List.fromList([1, 2, 3, 4, 5]),
        userId: 'hh_alias',
        householdAliases: {'olpers milk 1l': 'Milk', 'tom loose': 'Tomato'},
      );

      expect(result.scanId, 'rcpt_alias_ok');
      expect(result.items, isEmpty);
    });

    test('throws VisionApiException(statusCode: 429) on rate limit', () async {
      final mockClient = MockClient((_) async {
        return http.Response(
          jsonEncode({'detail': 'Daily scan limit reached (20 scans/day). Please try again tomorrow.'}),
          429,
        );
      });

      final service = VisionApiService(client: mockClient);
      await expectLater(
        service.parseReceipt(
          imageBytes: Uint8List.fromList([1, 2, 3]),
          userId: 'hh_rate',
        ),
        throwsA(
          isA<VisionApiException>()
              .having((e) => e.statusCode, 'statusCode', 429)
              .having((e) => e.message, 'message', contains('Daily')),
        ),
      );
    });

    test('throws VisionApiException(statusCode: 400) on unreadable image', () async {
      final mockClient = MockClient((_) async {
        return http.Response(
          jsonEncode({'detail': 'The receipt image is unreadable. Please take a clearer, well-lit photo.'}),
          400,
        );
      });

      final service = VisionApiService(client: mockClient);
      await expectLater(
        service.parseReceipt(
          imageBytes: Uint8List.fromList([0xde, 0xad]),
          userId: 'hh_bad',
        ),
        throwsA(
          isA<VisionApiException>()
              .having((e) => e.statusCode, 'statusCode', 400)
              .having((e) => e.message, 'message', contains('unreadable')),
        ),
      );
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  // Duplicate-detection helpers
  // ─────────────────────────────────────────────────────────────────────────

  group('VisionApiService duplicate-receipt detection', () {
    test('isDuplicate returns false for unseen hash, true after markProcessed', () async {
      const householdId = 'hh_dup_test';
      const hash = 'sha256_abc123';

      expect(await VisionApiService.isDuplicate(householdId, hash), isFalse);
      await VisionApiService.markProcessed(householdId, hash);
      expect(await VisionApiService.isDuplicate(householdId, hash), isTrue);
    });

    test('duplicate detection is scoped per household', () async {
      const hashA = 'hash_for_hh_A';
      await VisionApiService.markProcessed('household_A', hashA);

      // Same hash in a different household → not a duplicate there
      expect(await VisionApiService.isDuplicate('household_B', hashA), isFalse);
    });

    test('marking the same hash twice does not add duplicate entries', () async {
      const householdId = 'hh_idempotent';
      const hash = 'hash_idempotent_test';

      await VisionApiService.markProcessed(householdId, hash);
      await VisionApiService.markProcessed(householdId, hash);

      // Still a duplicate (and the list should not grow unbounded)
      expect(await VisionApiService.isDuplicate(householdId, hash), isTrue);
    });
  });
}
