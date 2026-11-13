import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/dish_options.dart';
import '../models/pantry_item_model.dart';
import 'server_config_service.dart';

class DishOptionsException implements Exception {
  const DishOptionsException(this.message);
  final String message;
  @override
  String toString() => message;
}

class DishOptionsService {
  DishOptionsService({http.Client? client, String? baseUrl})
    : _client = client ?? http.Client(),
      _base = Uri.parse(baseUrl ?? ServerConfigService.currentBaseUrl);
  final http.Client _client;
  final Uri _base;

  Future<Map<String, dynamic>> _post(
    String path,
    Map<String, dynamic> body,
  ) async {
    try {
      final response = await _client
          .post(
            _base.resolve(path),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(body),
          )
          .timeout(Duration(seconds: path == '/dish-options' ? 45 : 28));
      if (response.statusCode == 404) {
        throw const DishOptionsException(
          'This feature is not available on the server yet. Please try again later.',
        );
      }
      if (response.statusCode < 200 || response.statusCode >= 300) {
        var message = 'The search could not finish. Please try again.';
        try {
          final decoded = jsonDecode(response.body);
          if (decoded is Map && decoded['detail'] is String) {
            message = decoded['detail'] as String;
          }
        } catch (_) {}
        throw DishOptionsException(message);
      }
      return Map<String, dynamic>.from(jsonDecode(response.body) as Map);
    } on DishOptionsException {
      rethrow;
    } on TimeoutException {
      throw const DishOptionsException(
        'The search took too long. Please retry; your pantry is unchanged.',
      );
    } catch (_) {
      throw const DishOptionsException(
        'Search is unavailable. Check your connection and try again.',
      );
    }
  }

  Future<DishOptions> checkDish(
    String dish,
    List<PantryItemModel> pantry,
  ) async {
    final data = await _post('/dish-options', {
      'dish': dish.trim(),
      'reference_date': DateTime.now().toIso8601String().split('T').first,
      'pantry_items': [
        for (final item in pantry)
          {
            'name': item.name,
            'quantity': item.quantity,
            'unit': item.unit,
            if (item.expiryDate != null)
              'expiry_date': item.expiryDate!
                  .toIso8601String()
                  .split('T')
                  .first,
          },
      ],
    });
    return DishOptions.fromJson(data);
  }

  Future<RestaurantResults> restaurants(String dish, String area) async =>
      RestaurantResults.fromJson(
        await _post('/nearby-restaurants', {
          'dish': dish.trim(),
          'area': area.trim(),
        }),
      );

  void close() => _client.close();
}

/// Only explicit named requests leave the general Chef Chat conversation.
class DishRequestIntent {
  static String? extract(String question) {
    final match = RegExp(
      r"^(?:i want(?: to (?:eat|cook|make))?|i(?:'d| would) like(?: to (?:eat|cook|make))?|can i (?:cook|make)|how (?:do i|to) (?:cook|make))\s+(.+?)[?.!]*$",
      caseSensitive: false,
    ).firstMatch(question.trim());
    final romanUrdu = RegExp(
      r'^(?:mujhe|mujhay)\s+(.+?)\s+(?:chahiye|khani hai|khana hai)[.!?]*$',
      caseSensitive: false,
    ).firstMatch(question.trim());
    final bareDish = RegExp(
      r'^(?:(?:chicken|beef|lamb|mutton|vegetable|egg|tomato|cheese|spicy|plain)\s+){0,3}(?:biryani|pizza|pasta|burger|karahi|nihari|korma|pulao|daal|dal|haleem|shawarma|lasagna|lasagne|omelette)$',
      caseSensitive: false,
    ).hasMatch(question.trim());
    if (match == null && romanUrdu == null && !bareDish) return null;
    var dish = (match?.group(1) ?? romanUrdu?.group(1) ?? question.trim())
        .replaceFirst(
          RegExp(r'^(?:a |the )?(?:recipe for |some )?', caseSensitive: false),
          '',
        );
    dish = dish
        .replaceFirst(
          RegExp(r'\s+(?:recipe|please)$', caseSensitive: false),
          '',
        )
        .trim();
    if (dish.length < 2 ||
        dish.length > 100 ||
        RegExp(
          r'\b(pantry|inventory|stock|help|account|week|plan|something|anything|meals?|dinner|lunch|breakfast)\b',
          caseSensitive: false,
        ).hasMatch(dish)) {
      return null;
    }
    return dish;
  }
}
