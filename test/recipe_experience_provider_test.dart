import 'package:culinary_ai/models/nutrition_facts.dart';
import 'package:culinary_ai/providers/recipe_experience_provider.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<void> ready(RecipeExperienceProvider provider) async {
    while (!provider.ready) {
      await Future<void>.delayed(Duration.zero);
    }
  }

  test(
    'concurrent meal saves retain both meals and nutrition after restart',
    () async {
      final provider = RecipeExperienceProvider();
      await ready(provider);
      await Future.wait([
        provider.recordNutrition(
          title: 'Lunch',
          nutrition: const NutritionFacts(calories: 400, proteinGrams: 20),
        ),
        provider.recordNutrition(
          title: 'Dinner',
          nutrition: const NutritionFacts(calories: 600, proteinGrams: 30),
        ),
      ]);
      expect(provider.history, hasLength(2));
      expect(provider.nutritionFor(DateTime.now()).calories, 1000);
      final restored = RecipeExperienceProvider();
      await ready(restored);
      expect(restored.history.map((meal) => meal.title), ['Dinner', 'Lunch']);
      expect(restored.nutritionFor(DateTime.now()).proteinGrams, 50);
      provider.dispose();
      restored.dispose();
    },
  );
}
