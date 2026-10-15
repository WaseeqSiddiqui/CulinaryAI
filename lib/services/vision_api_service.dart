import 'dart:async';
import 'dart:convert';
import 'dart:ui' as ui;

import 'package:crypto/crypto.dart' as crypto;
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/receipt_vision_models.dart';

class VisionApiException implements Exception {
  final String message;
  final int? statusCode;

  const VisionApiException(this.message, {this.statusCode});

  @override
  String toString() => message;
}

class VisionApiService {
  static const configuredBaseUrl = String.fromEnvironment(
    'CULINARY_API_BASE_URL',
    defaultValue: 'http://10.0.2.2:8000',
  );

  VisionApiService({
    http.Client? client,
    String baseUrl = configuredBaseUrl,
    this.timeout = const Duration(seconds: 35),
  })  : _client = client ?? http.Client(),
        baseUri = Uri.parse(baseUrl.replaceFirst(RegExp(r'/$'), ''));

  final http.Client _client;
  final Uri baseUri;
  final Duration timeout;

  /// Downscales image bytes so the longest side is at most [maxDimension] px (~1600px)
  static Future<Uint8List> downscaleImage(
    Uint8List inputBytes, {
    int maxDimension = 1600,
  }) async {
    try {
      final codec = await ui.instantiateImageCodec(inputBytes);
      final frame = await codec.getNextFrame();
      final width = frame.image.width;
      final height = frame.image.height;

      // If already within dimensions, return original
      if (width <= maxDimension && height <= maxDimension) {
        return inputBytes;
      }

      int targetWidth = width;
      int targetHeight = height;
      if (width >= height) {
        targetWidth = maxDimension;
        targetHeight = (height * (maxDimension / width)).round();
      } else {
        targetHeight = maxDimension;
        targetWidth = (width * (maxDimension / height)).round();
      }

      final scaledCodec = await ui.instantiateImageCodec(
        inputBytes,
        targetWidth: targetWidth,
        targetHeight: targetHeight,
      );
      final scaledFrame = await scaledCodec.getNextFrame();
      final byteData = await scaledFrame.image.toByteData(
        format: ui.ImageByteFormat.png,
      );
      if (byteData == null) return inputBytes;
      return byteData.buffer.asUint8List();
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Downscale failed, falling back to original bytes: $e');
      }
      return inputBytes;
    }
  }

  /// Computes SHA-256 hash of image bytes for duplicate receipt detection
  static String hashBytes(Uint8List bytes) {
    return crypto.sha256.convert(bytes).toString();
  }

  /// Checks if a receipt hash or key was already processed
  static Future<bool> isDuplicate(String householdId, String identifier) async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList('culinary_receipt_hashes_$householdId') ?? [];
    return list.contains(identifier);
  }

  /// Records that a receipt has been processed
  static Future<void> markProcessed(String householdId, String identifier) async {
    final prefs = await SharedPreferences.getInstance();
    final key = 'culinary_receipt_hashes_$householdId';
    final list = prefs.getStringList(key) ?? [];
    if (!list.contains(identifier)) {
      list.add(identifier);
      await prefs.setStringList(key, list);
    }
  }

  /// Uploads receipt image to POST /parse-receipt
  Future<ValidatedReceiptResponse> parseReceipt({
    required Uint8List imageBytes,
    required String userId,
    Map<String, String>? householdAliases,
  }) async {
    // 1. Downscale image to ~1600px long side
    final preparedBytes = await downscaleImage(imageBytes, maxDimension: 1600);

    final uri = baseUri.resolve('/parse-receipt');
    final request = http.MultipartRequest('POST', uri);

    request.headers['X-User-Id'] = userId;
    request.fields['user_id'] = userId;

    if (householdAliases != null && householdAliases.isNotEmpty) {
      request.fields['household_aliases'] = jsonEncode(householdAliases);
    }

    request.files.add(
      http.MultipartFile.fromBytes(
        'file',
        preparedBytes,
        filename: 'receipt.jpg',
        contentType: MediaType('image', 'jpeg'),
      ),
    );

    try {
      final streamedResponse = await _client.send(request).timeout(timeout);
      final response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body);
        if (decoded is! Map<String, dynamic>) {
          throw const VisionApiException('Invalid response from receipt vision service.');
        }
        return ValidatedReceiptResponse.fromJson(decoded);
      }

      // Handle specific error codes
      if (response.statusCode == 429) {
        final detail = _extractDetail(response.body);
        throw VisionApiException(
          detail ?? 'Daily receipt scanning limit reached (max 20 scans/day). Please try again tomorrow.',
          statusCode: 429,
        );
      }

      if (response.statusCode == 400) {
        final detail = _extractDetail(response.body);
        throw VisionApiException(
          detail ?? 'The receipt image is unreadable. Please take a clearer, well-lit photo.',
          statusCode: 400,
        );
      }

      if (response.statusCode == 504) {
        throw const VisionApiException(
          'Receipt scanning timed out. Please try again with a clearer crop.',
          statusCode: 504,
        );
      }

      final errorMsg = _extractDetail(response.body) ?? 'Server error (${response.statusCode})';
      throw VisionApiException(errorMsg, statusCode: response.statusCode);
    } on TimeoutException {
      throw const VisionApiException(
        'Receipt recognition timed out. Check your connection or try again.',
        statusCode: 504,
      );
    } on VisionApiException {
      rethrow;
    } catch (e) {
      throw VisionApiException('Could not connect to receipt vision service: $e');
    }
  }

  String? _extractDetail(String responseBody) {
    try {
      final data = jsonDecode(responseBody);
      if (data is Map && data['detail'] != null) {
        return data['detail'].toString();
      }
    } catch (_) {}
    return null;
  }

  void close() => _client.close();
}
