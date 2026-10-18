/// Tests for [FridgeScanResponse] and [ReconciledFridgeItem] JSON parsing,
/// and [VisionApiService.scanFridge] HTTP integration.
///
/// The old Tesseract hOCR / layout-reconstruction tests have been removed
/// because all OCR is now delegated to the Gemini Vision backend endpoint
/// (POST /scan-fridge). This file covers the equivalent surface area on the
/// Flutter side: JSON deserialization and HTTP transport logic.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:culinary_ai/models/fridge_vision_models.dart';
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

  group('FridgeScanResponse JSON parsing', () {
    test('parses verified, mismatch and new_item rows correctly', () {
      final json = {
        'scan_id': 'fridge_9999',
        'reconciled_items': [
          {
            'detected_name': 'Milk',
            'matched_pantry_id': 'item_1',
            'matched_name': 'Milk',
            'detected_count': null,
            'detected_fill_level': 0.6,
            'label_size_text': '1 L',
            'confidence': 0.95,
            'status': 'verified',
            'question': null,
            'current_quantity': 2.0,
            'suggested_quantity': 2.0,
            'unit': 'L',
            'estimated': false,
            'verified_at': '2026-10-15T10:00:00Z',
          },
          {
            'detected_name': 'Yogurt',
            'matched_pantry_id': 'item_2',
            'matched_name': 'Greek Yogurt',
            'detected_count': 3,
            'detected_fill_level': null,
            'label_size_text': '500g',
            'confidence': 0.72,
            'status': 'mismatch',
            'question': 'Detected 3 pots, pantry shows 1. Update to 3?',
            'current_quantity': 1.0,
            'suggested_quantity': 3.0,
            'unit': 'pcs',
            'estimated': true,
            'verified_at': null,
          },
          {
            'detected_name': 'Cheddar Cheese',
            'matched_pantry_id': null,
            'matched_name': null,
            'detected_count': 1,
            'detected_fill_level': null,
            'label_size_text': null,
            'confidence': 0.88,
            'status': 'new_item',
            'question': null,
            'current_quantity': null,
            'suggested_quantity': 1.0,
            'unit': 'pcs',
            'estimated': true,
            'verified_at': null,
          },
        ],
        'verified_count': 1,
        'mismatch_count': 1,
        'new_items_count': 1,
      };

      final response = FridgeScanResponse.fromJson(json);

      expect(response.scanId, 'fridge_9999');
      expect(response.reconciledItems, hasLength(3));
      expect(response.verifiedCount, 1);
      expect(response.mismatchCount, 1);
      expect(response.newItemsCount, 1);

      final milk = response.reconciledItems[0];
      expect(milk.detectedName, 'Milk');
      expect(milk.status, 'verified');
      expect(milk.detectedFillLevel, 0.6);
      expect(milk.labelSizeText, '1 L');
      expect(milk.isAccepted, isTrue); // verified items auto-accepted

      final yogurt = response.reconciledItems[1];
      expect(yogurt.status, 'mismatch');
      expect(yogurt.detectedCount, 3);
      expect(yogurt.suggestedQuantity, 3.0);
      expect(yogurt.question, contains('3 pots'));
      expect(yogurt.isAccepted, isFalse); // mismatches need explicit confirm

      final cheese = response.reconciledItems[2];
      expect(cheese.status, 'new_item');
      expect(cheese.matchedPantryId, isNull);
    });

    test('handles empty reconciled_items list gracefully', () {
      final json = {
        'scan_id': 'fridge_empty',
        'reconciled_items': <dynamic>[],
        'verified_count': 0,
        'mismatch_count': 0,
        'new_items_count': 0,
      };

      final response = FridgeScanResponse.fromJson(json);
      expect(response.reconciledItems, isEmpty);
    });

    test('applies safe defaults for optional fields', () {
      final json = {
        'scan_id': 'fridge_minimal',
        'reconciled_items': [
          {'detected_name': 'Apple', 'status': 'new_item'},
        ],
      };

      final response = FridgeScanResponse.fromJson(json);
      final apple = response.reconciledItems.first;

      expect(apple.detectedName, 'Apple');
      expect(apple.confidence, 1.0);
      expect(apple.unit, 'pcs');
      expect(apple.estimated, isTrue);
      expect(apple.matchedPantryId, isNull);
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  // HTTP transport: VisionApiService.scanFridge
  // ─────────────────────────────────────────────────────────────────────────

  group('VisionApiService.scanFridge HTTP integration', () {
    test('sends multipart request to /scan-fridge and parses 200 response', () async {
      final mockClient = MockClient((request) async {
        expect(request.url.path, '/scan-fridge');
        expect(request.headers['X-User-Id'], 'hh_fridge_1');
        expect(request.method, 'POST');

        return http.Response(
          jsonEncode({
            'scan_id': 'fridge_mock',
            'reconciled_items': [
              {
                'detected_name': 'Eggs',
                'status': 'verified',
                'confidence': 0.97,
                'detected_count': 6,
                'unit': 'pcs',
                'estimated': false,
              },
            ],
            'verified_count': 1,
            'mismatch_count': 0,
            'new_items_count': 0,
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      });

      final service = VisionApiService(client: mockClient);
      final result = await service.scanFridge(
        imageBytes: Uint8List.fromList(List.generate(100, (i) => i % 256)),
        userId: 'hh_fridge_1',
        existingItems: [],
      );

      expect(result.scanId, 'fridge_mock');
      expect(result.reconciledItems, hasLength(1));
      expect(result.reconciledItems.first.detectedName, 'Eggs');
      expect(result.reconciledItems.first.detectedCount, 6);
      expect(result.verifiedCount, 1);
    });

    test('throws VisionApiException with friendly message on 429', () async {
      final mockClient = MockClient((_) async {
        return http.Response(
          jsonEncode({'detail': 'Daily fridge scanning limit reached (20 scans/day).'}),
          429,
        );
      });

      final service = VisionApiService(client: mockClient);
      expect(
        () => service.scanFridge(
          imageBytes: Uint8List.fromList([1, 2, 3]),
          userId: 'hh_rate',
          existingItems: [],
        ),
        throwsA(
          isA<VisionApiException>().having(
            (e) => e.statusCode,
            'statusCode',
            429,
          ),
        ),
      );
    });

    test('throws VisionApiException with 400 message on bad image', () async {
      final mockClient = MockClient((_) async {
        return http.Response(
          jsonEncode({'detail': 'The provided file is not a valid or readable image.'}),
          400,
        );
      });

      final service = VisionApiService(client: mockClient);
      expect(
        () => service.scanFridge(
          imageBytes: Uint8List.fromList([0xff, 0xfe]),
          userId: 'hh_bad',
          existingItems: [],
        ),
        throwsA(
          isA<VisionApiException>().having(
            (e) => e.message,
            'message',
            contains('readable image'),
          ),
        ),
      );
    });
  });
}
