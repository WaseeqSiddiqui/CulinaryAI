import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';

import '../models/meal_nutrition_estimate.dart';
import 'vision_api_service.dart';

class MealNutritionService {
  final http.Client _client;
  final Uri baseUri;

  MealNutritionService({http.Client? client, String? baseUrl})
    : _client = client ?? http.Client(),
      baseUri = Uri.parse(
        (baseUrl ?? VisionApiService.defaultBaseUrl).replaceFirst(
          RegExp(r'/$'),
          '',
        ),
      );

  Future<MealNutritionEstimate> analyze({
    required Uint8List imageBytes,
    required String userId,
  }) async {
    final bytes = await VisionApiService.downscaleImage(imageBytes);
    final request =
        http.MultipartRequest('POST', baseUri.resolve('/analyze-meal'))
          ..headers['X-User-Id'] = userId
          ..fields['user_id'] = userId
          ..files.add(
            http.MultipartFile.fromBytes(
              'file',
              bytes,
              filename: 'meal.jpg',
              contentType: MediaType('image', 'jpeg'),
            ),
          );
    try {
      final response = await http.Response.fromStream(
        await _client.send(request).timeout(const Duration(seconds: 45)),
      );
      if (response.statusCode < 200 || response.statusCode >= 300) {
        final decoded = jsonDecode(response.body);
        final message = decoded is Map ? decoded['detail']?.toString() : null;
        throw Exception(
          message ?? 'Meal scan failed (${response.statusCode}).',
        );
      }
      return MealNutritionEstimate.fromJson(
        Map<String, dynamic>.from(jsonDecode(response.body) as Map),
      );
    } on TimeoutException {
      throw Exception('Meal scan timed out. Try a clearer, closer photo.');
    }
  }

  void close() => _client.close();
}
