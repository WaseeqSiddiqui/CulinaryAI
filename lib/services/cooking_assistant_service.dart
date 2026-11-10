import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';

import '../models/cooking_session.dart';
import 'server_config_service.dart';

class CookingAssistantException implements Exception {
  final String message;
  final int? statusCode;
  const CookingAssistantException(this.message, {this.statusCode});
  @override
  String toString() => message;
}

class CookingAssistantService {
  CookingAssistantService({
    http.Client? client,
    String? baseUrl,
    this.timeout = const Duration(seconds: 20),
  }) : _client = client ?? http.Client(),
       _ownsClient = client == null,
       baseUri = Uri.parse(
         (baseUrl ?? ServerConfigService.currentBaseUrl).replaceFirst(
           RegExp(r'/$'),
           '',
         ),
       );

  final http.Client _client;
  final bool _ownsClient;
  final Uri baseUri;
  final Duration timeout;

  Future<DetailedCookingStep> explainStep({
    required String recipeTitle,
    required int stepNumber,
    required String instruction,
  }) async {
    try {
      final response = await _postJson('/step-explanation', {
        'recipe_title': recipeTitle,
        'step_number': stepNumber,
        'step_instruction': instruction,
      });
      return DetailedCookingStep.fromJson(
        response,
        fallbackAction: instruction,
      );
    } on CookingAssistantException catch (error) {
      if (error.statusCode == 404) {
        return DetailedCookingStep.fallback(instruction);
      }
      rethrow;
    }
  }

  Future<String> askStep({
    required String recipeTitle,
    required int stepNumber,
    required String instruction,
    required String message,
    required List<CookingChatMessage> history,
    required List<String> adjustments,
    required List<String> dietaryRestrictions,
  }) async {
    Map<String, dynamic> response;
    try {
      response = await _postJson('/cooking-step-chat', {
        'recipe_title': recipeTitle,
        'step_number': stepNumber,
        'step_instruction': instruction,
        'message': message,
        'conversation_history': [
          for (final item in history.takeLast(10))
            {'role': item.isUser ? 'user' : 'assistant', 'content': item.text},
        ],
        'adjustments': adjustments,
        'dietary_restrictions': dietaryRestrictions,
      });
    } on CookingAssistantException catch (error) {
      if (error.statusCode != 404) rethrow;
      response = await _postJson('/chef-chat', {
        'message':
            'I am cooking $recipeTitle and I am on Step $stepNumber: '
            '$instruction\nMy question: $message\nAnswer briefly with practical '
            'advice for this exact step. Do not advance unless I ask.\n'
            'Dietary restrictions: ${dietaryRestrictions.join(', ')}\n'
            'Recipe adjustments: ${adjustments.join('; ')}\n'
            'Recent conversation:\n${history.takeLast(10).map((item) => '${item.isUser ? 'User' : 'Chef'}: ${item.text}').join('\n')}',
        'pantry_items': const [],
      });
    }
    final reply = response['reply']?.toString().trim() ?? '';
    if (reply.isEmpty) {
      throw const CookingAssistantException(
        'The chef returned an empty reply.',
      );
    }
    return reply;
  }

  Future<CookingVisionResult> validateImage({
    required Uint8List imageBytes,
    String imageName = 'cooking.jpg',
    required String recipeTitle,
    required int stepNumber,
    required String instruction,
    required String question,
    required String userId,
  }) async {
    try {
      final request =
          http.MultipartRequest(
              'POST',
              baseUri.resolve('/validate-cooking-step'),
            )
            ..headers['X-User-Id'] = userId
            ..fields.addAll({
              'recipe_title': recipeTitle,
              'step_number': '$stepNumber',
              'step_instruction': instruction,
              'user_question': question,
            })
            ..files.add(
              http.MultipartFile.fromBytes(
                'file',
                imageBytes,
                filename: imageName,
                contentType: MediaType('image', _subtypeFor(imageName)),
              ),
            );
      final streamed = await _client.send(request).timeout(timeout);
      final response = await http.Response.fromStream(streamed)
          .timeout(timeout);
      if (response.statusCode == 404) {
        throw const CookingAssistantException(
          'Photo checks are not available on this server yet. You can keep cooking with step guidance or ask Chef a question.',
          statusCode: 404,
        );
      }
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw CookingAssistantException(
          'Visual check failed with status ${response.statusCode}.',
        );
      }
      return CookingVisionResult.fromJson(
        Map<String, dynamic>.from(jsonDecode(response.body) as Map),
      );
    } on TimeoutException {
      throw const CookingAssistantException(
        'The visual check timed out. Check your connection and retry.',
      );
    } on CookingAssistantException {
      rethrow;
    } on Object {
      throw const CookingAssistantException(
        'The image could not be analyzed. Keep using the visible step cues or retry.',
      );
    }
  }

  Future<Map<String, dynamic>> _postJson(
    String path,
    Map<String, dynamic> body,
  ) async {
    try {
      final response = await _client
          .post(
            baseUri.resolve(path),
            headers: const {'Content-Type': 'application/json'},
            body: jsonEncode(body),
          )
          .timeout(timeout);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw CookingAssistantException(
          'Cooking assistant returned status ${response.statusCode}.',
          statusCode: response.statusCode,
        );
      }
      return Map<String, dynamic>.from(jsonDecode(response.body) as Map);
    } on TimeoutException {
      throw const CookingAssistantException(
        'The cooking assistant timed out. You can retry without losing your step.',
      );
    } on CookingAssistantException {
      rethrow;
    } on Object {
      throw const CookingAssistantException(
        'The cooking assistant is unavailable. Your session is still saved.',
      );
    }
  }

  void close() {
    if (_ownsClient) _client.close();
  }
}

extension<T> on List<T> {
  Iterable<T> takeLast(int count) =>
      length <= count ? this : skip(length - count);
}

String _subtypeFor(String path) {
  final lower = path.toLowerCase();
  if (lower.endsWith('.png')) return 'png';
  if (lower.endsWith('.webp')) return 'webp';
  return 'jpeg';
}
