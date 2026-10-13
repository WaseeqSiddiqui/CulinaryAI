import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/backend_meal_recommendation.dart';
import '../models/pantry_item_model.dart';

class MealPlanningApiException implements Exception {
  final String message;

  const MealPlanningApiException(this.message);

  @override
  String toString() => message;
}

class MealPlanningApiService {
  static const configuredBaseUrl = String.fromEnvironment(
    'CULINARY_API_BASE_URL',
    defaultValue: 'http://10.0.2.2:8000',
  );

  MealPlanningApiService({
    http.Client? client,
    String baseUrl = configuredBaseUrl,
    this.timeout = const Duration(seconds: 8),
  }) : _client = client ?? http.Client(),
       baseUri = Uri.parse(baseUrl.replaceFirst(RegExp(r'/$'), ''));

  final http.Client _client;
  final Uri baseUri;
  final Duration timeout;

  Future<BackendMealPlan> generatePlan({
    String question = '',
    required List<PantryItemModel> pantryItems,
    int servings = 4,
    int mealCount = 3,
    List<String> dietaryPreferences = const [],
    int? maxCookTimeMinutes,
  }) async {
    final effectivePreferences = dietaryPreferences
        .map((preference) => preference.trim().toLowerCase())
        .where(
          (preference) =>
              preference.isNotEmpty &&
              !const {'balanced', 'none', 'omnivore'}.contains(preference),
        )
        .toList();
    final body = <String, dynamic>{
      'question': question.trim(),
      'pantry_items': [
        for (final item in pantryItems)
          {'name': item.name, 'quantity': item.quantity, 'unit': item.unit},
      ],
      'servings': servings,
      'meal_count': mealCount,
      'dietary_preferences': effectivePreferences,
      'max_cook_time_minutes': ?maxCookTimeMinutes,
    };

    try {
      final response = await _client
          .post(
            baseUri.resolve('/generate-plan'),
            headers: const {'Content-Type': 'application/json'},
            body: jsonEncode(body),
          )
          .timeout(timeout);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw MealPlanningApiException(
          'Meal service returned status ${response.statusCode}.',
        );
      }
      final decoded = jsonDecode(response.body);
      if (decoded is! Map) {
        throw const MealPlanningApiException(
          'Meal service returned an invalid response.',
        );
      }
      return BackendMealPlan.fromJson(Map<String, dynamic>.from(decoded));
    } on TimeoutException {
      throw const MealPlanningApiException(
        'Meal service timed out. Using offline recommendations.',
      );
    } on MealPlanningApiException {
      rethrow;
    } on Object {
      throw const MealPlanningApiException(
        'Meal service is unavailable. Using offline recommendations.',
      );
    }
  }

  void close() => _client.close();
}
