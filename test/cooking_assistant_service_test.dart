import 'dart:convert';
import 'dart:typed_data';

import 'package:culinary_ai/models/cooking_session.dart';
import 'package:culinary_ai/services/cooking_assistant_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('parses every practical field in a detailed cooking step', () async {
    late Map<String, dynamic> requestBody;
    final client = MockClient((request) async {
      requestBody = Map<String, dynamic>.from(jsonDecode(request.body) as Map);
      return http.Response(
        jsonEncode({
          'recipe_title': 'Karahi',
          'step_number': 2,
          'action': 'Cook the tomatoes down.',
          'heat_level': 'Medium',
          'pace': 'Steadily',
          'estimated_duration': '5–8 minutes (estimate)',
          'technique': 'Stir every minute.',
          'visual_cues': ['Oil begins to separate'],
          'texture_and_aroma': 'Jammy and fragrant',
          'precautions': ['Avoid scorching'],
          'completion_criteria': 'Tomatoes are soft and oil separates',
          'pro_tip': 'Keep the pan uncovered',
        }),
        200,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );
    });
    final service = CookingAssistantService(
      client: client,
      baseUrl: 'https://example.test',
    );

    final step = await service.explainStep(
      recipeTitle: 'Karahi',
      stepNumber: 2,
      instruction: 'Cook tomatoes.',
    );

    expect(requestBody['step_number'], 2);
    expect(step.heatLevel, 'Medium');
    expect(step.technique, 'Stir every minute.');
    expect(step.completionCriteria, contains('oil separates'));
    expect(step.precautions, ['Avoid scorching']);
  });

  test('sends recent shared-session context with step questions', () async {
    late Map<String, dynamic> requestBody;
    final client = MockClient((request) async {
      requestBody = Map<String, dynamic>.from(jsonDecode(request.body) as Map);
      return http.Response(
        jsonEncode({'reply': 'Leave the pan uncovered.'}),
        200,
      );
    });
    final service = CookingAssistantService(
      client: client,
      baseUrl: 'https://example.test',
    );
    final history = List.generate(
      12,
      (index) => CookingChatMessage(
        id: '$index',
        text: 'Message $index',
        isUser: index.isEven,
        kind: CookingMessageKind.text,
        createdAt: DateTime(2026),
      ),
    );

    final reply = await service.askStep(
      recipeTitle: 'Karahi',
      stepNumber: 2,
      instruction: 'Cook tomatoes.',
      message: 'Should I cover it?',
      history: history,
      adjustments: const ['Used yogurt instead of cream'],
      dietaryRestrictions: const ['Nut-free'],
    );

    expect(reply, 'Leave the pan uncovered.');
    expect(requestBody['conversation_history'], hasLength(10));
    expect(
      requestBody['adjustments'],
      contains('Used yogurt instead of cream'),
    );
    expect(requestBody['dietary_restrictions'], ['Nut-free']);
  });

  test('uses local step guidance when an older backend returns 404', () async {
    final client = MockClient(
      (_) async => http.Response('{"detail":"Not Found"}', 404),
    );
    final service = CookingAssistantService(
      client: client,
      baseUrl: 'https://example.test',
    );

    final step = await service.explainStep(
      recipeTitle: 'Salmon',
      stepNumber: 2,
      instruction: 'Place the salmon skin-down and cook for 5 minutes.',
    );

    expect(step.action, contains('skin-down'));
    expect(step.estimatedDuration, isNotEmpty);
  });

  test('falls back to chef chat when step chat route is unavailable', () async {
    final requestedPaths = <String>[];
    final client = MockClient((request) async {
      requestedPaths.add(request.url.path);
      if (request.url.path == '/cooking-step-chat') {
        return http.Response('{"detail":"Not Found"}', 404);
      }
      final body = Map<String, dynamic>.from(jsonDecode(request.body) as Map);
      expect(body['message'], contains('Step 2'));
      expect(body['message'], contains('Should I cover it?'));
      return http.Response(jsonEncode({'reply': 'Keep it uncovered.'}), 200);
    });
    final service = CookingAssistantService(
      client: client,
      baseUrl: 'https://example.test',
    );

    final reply = await service.askStep(
      recipeTitle: 'Karahi',
      stepNumber: 2,
      instruction: 'Cook the tomatoes down.',
      message: 'Should I cover it?',
      history: const [],
      adjustments: const [],
      dietaryRestrictions: const [],
    );

    expect(reply, 'Keep it uncovered.');
    expect(requestedPaths, ['/cooking-step-chat', '/chef-chat']);
  });

  test('uploads cooking photos as bytes without a native file path', () async {
    late http.Request uploaded;
    final client = MockClient((request) async {
      uploaded = request;
      return http.Response(
        jsonEncode({
          'status': 'needs_more_time',
          'headline': 'Keep cooking',
          'feedback': 'The tomatoes still look firm.',
          'action_suggestion': 'Cook gently and stir.',
          'confidence': 0.8,
          'image_sufficient': true,
        }),
        200,
      );
    });
    final service = CookingAssistantService(
      client: client,
      baseUrl: 'https://example.test',
    );
    final result = await service.validateImage(
      imageBytes: Uint8List.fromList(utf8.encode('photo-bytes')),
      imageName: 'plate.png',
      recipeTitle: 'Karahi',
      stepNumber: 2,
      instruction: 'Cook tomatoes.',
      question: 'Is this ready?',
      userId: 'cook-1',
    );
    expect(result.imageSufficient, isTrue);
    expect(uploaded.url.path, '/validate-cooking-step');
    expect(uploaded.headers['X-User-Id'], 'cook-1');
    expect(uploaded.headers['Content-Type'], startsWith('multipart/form-data'));
    final body = utf8.decode(uploaded.bodyBytes, allowMalformed: true);
    expect(body, contains('filename="plate.png"'));
    expect(body.toLowerCase(), contains('content-type: image/png'));
    expect(body, contains('photo-bytes'));
    expect(body, contains('Cook tomatoes.'));
  });

  test('unavailable photo endpoint explains how to continue cooking', () async {
    final service = CookingAssistantService(
      client: MockClient((_) async => http.Response('{}', 404)),
      baseUrl: 'https://example.test',
    );
    await expectLater(
      service.validateImage(
        imageBytes: Uint8List.fromList([1, 2, 3]),
        recipeTitle: 'Karahi',
        stepNumber: 2,
        instruction: 'Cook tomatoes.',
        question: 'Is this ready?',
        userId: 'cook-1',
      ),
      throwsA(
        isA<CookingAssistantException>().having(
          (error) => error.message,
          'message',
          contains('ask Chef a question'),
        ),
      ),
    );
  });

  test('vision result preserves uncertainty and safety limits', () {
    final result = CookingVisionResult.fromJson({
      'status': 'unable_to_assess',
      'headline': 'Photo too blurry',
      'feedback': 'I cannot reliably see the food.',
      'action_suggestion': 'Retake the photo in better light.',
      'visual_observations': <String>[],
      'confidence': 0,
      'image_sufficient': false,
      'safety_note': 'A photo cannot verify internal temperature.',
    });

    expect(result.imageSufficient, isFalse);
    expect(result.confidence, 0);
    expect(result.safetyNote, contains('cannot verify'));
  });
}
