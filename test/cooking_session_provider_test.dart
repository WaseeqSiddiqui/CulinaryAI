import 'package:culinary_ai/models/cooking_session.dart';
import 'package:culinary_ai/models/recipe_recommendation_model.dart';
import 'package:culinary_ai/providers/cooking_session_provider.dart';
import 'package:culinary_ai/services/cooking_assistant_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeCookingAssistantService extends CookingAssistantService {
  _FakeCookingAssistantService() : super(baseUrl: 'https://example.test');

  @override
  Future<String> askStep({
    required String recipeTitle,
    required int stepNumber,
    required String instruction,
    required String message,
    required List<CookingChatMessage> history,
    required List<String> adjustments,
    required List<String> dietaryRestrictions,
  }) async => 'Keep cooking gently and check the visible cues.';

  @override
  Future<DetailedCookingStep> explainStep({
    required String recipeTitle,
    required int stepNumber,
    required String instruction,
  }) async => DetailedCookingStep.fallback(instruction);
}

const _recipe = RecipeRecommendationModel(
  id: 'session_test_recipe',
  title: 'Test Recipe',
  subtitle: 'A test',
  imageUrl: '',
  cookTimeMinutes: 10,
  calories: 100,
  difficulty: 'Easy',
  mealType: 'Dinner',
  servings: 2,
  ingredientDetails: [],
  instructions: ['Prepare ingredients.', 'Cook gently.', 'Serve safely.'],
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('normal questions never advance the cooking step', () async {
    final provider = CookingSessionProvider(
      recipe: _recipe,
      dietaryRestrictions: const [],
      service: _FakeCookingAssistantService(),
    );

    await provider.submitQuestion('Should I lower the heat?');

    expect(provider.stepIndex, 0);
    expect(provider.messages, hasLength(2));
    expect(provider.messages.last.isUser, isFalse);
    provider.dispose();
  });

  test('explicit next-step command advances exactly one step', () async {
    final provider = CookingSessionProvider(
      recipe: _recipe,
      dietaryRestrictions: const [],
      service: _FakeCookingAssistantService(),
    );

    await provider.submitQuestion('Next step');

    expect(provider.stepIndex, 1);
    expect(provider.completedSteps, contains(0));
    provider.dispose();
  });

  test('pause and resume preserve the current step', () {
    final provider = CookingSessionProvider(
      recipe: _recipe,
      dietaryRestrictions: const [],
      service: _FakeCookingAssistantService(),
    );

    provider.togglePause();
    expect(provider.isPaused, isTrue);
    expect(provider.stepIndex, 0);
    provider.togglePause();
    expect(provider.isPaused, isFalse);
    expect(provider.stepIndex, 0);
    provider.dispose();
  });
}
