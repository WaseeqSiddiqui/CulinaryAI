import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/chef_name_formatter.dart';
import '../../models/backend_meal_recommendation.dart';
import '../../models/pantry_item_model.dart';
import '../../models/recipe_recommendation_model.dart';
import '../../providers/auth_provider.dart';
import '../../providers/pantry_provider.dart';
import '../../providers/recipe_experience_provider.dart';
import '../../services/chef_chat_service.dart';
import '../../services/meal_planning_api_service.dart';
import '../cooking/guided_cooking_screen.dart';

class ChatbotScreen extends StatefulWidget {
  final String? initialQuestion;
  final MealPlanningApiService? mealPlanningApi;

  const ChatbotScreen({super.key, this.initialQuestion, this.mealPlanningApi});

  @override
  State<ChatbotScreen> createState() => _ChatbotScreenState();
}

class _ChatbotScreenState extends State<ChatbotScreen> {
  final _controller = TextEditingController();
  final _scrollController = ScrollController();
  late final MealPlanningApiService _mealPlanningApi;
  late final bool _ownsMealPlanningApi;
  final List<_ChatMessage> _messages = [];
  bool _isReplying = false;

  static const _suggestions = [
    'What can I cook?',
    'What is low stock?',
    'What do I have in my pantry?',
    'How do I cook tomato pasta?',
  ];

  @override
  void initState() {
    super.initState();
    _ownsMealPlanningApi = widget.mealPlanningApi == null;
    _mealPlanningApi = widget.mealPlanningApi ?? MealPlanningApiService();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final initial = widget.initialQuestion?.trim() ?? '';
      if (initial.isNotEmpty) _send(initial);
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    if (_ownsMealPlanningApi) _mealPlanningApi.close();
    super.dispose();
  }

  Future<void> _send([String? value]) async {
    final question = (value ?? _controller.text).trim();
    if (question.isEmpty || _isReplying) return;
    final pantryItems = context
        .read<PantryProvider>()
        .allItems
        .where(
          (item) =>
              item.quantity > 0 && item.expiryStatus != ExpiryStatus.expired,
        )
        .toList();
    final preferences = context.read<RecipeExperienceProvider>().preferences;
    final dietaryPreference = context
        .read<AuthProvider>()
        .currentUser
        ?.dietaryPreference
        ?.trim();

    setState(() {
      _messages.add(_ChatMessage(text: question, isUser: true));
      _controller.clear();
      _isReplying = true;
    });
    _scrollToBottom();

    var answer = '';
    String? serviceNotice;
    var recommendations = const <BackendMealRecommendation>[];

    if (_isWeeklyPlanRequest(question)) {
      await Future<void>.delayed(const Duration(milliseconds: 180));
      answer = 'Weekly planning has its own clean screen. Open the menu and choose 7-day meal plan; it will use your pantry, people count, and calorie target.';
    } else if (ChefChatService.isMealPlanningQuestion(question)) {
      try {
        final plan = await _mealPlanningApi.generatePlan(
          question: question,
          pantryItems: pantryItems,
          servings: preferences.servings,
          mealCount: 1,
          dietaryPreferences:
              dietaryPreference == null || dietaryPreference.isEmpty
              ? preferences.dietaryNeeds
              : [...preferences.dietaryNeeds, dietaryPreference],
          maxCookTimeMinutes: preferences.maxCookMinutes,
          avoidIngredients: [
            ...preferences.allergens,
            ...preferences.dislikedIngredients,
          ],
          mealsPerDay: preferences.mealsPerDay,
          targetCaloriesPerPersonPerDay: preferences.calorieTarget,
          pantryFirst: true,
        );
        recommendations = plan.meals;
        answer = recommendations.isEmpty
            ? 'The verified recipe service did not find a suitable meal. Try changing your dietary preference or adding more pantry items.'
            : 'I checked your pantry first and found this recipe for ${preferences.servings} people. It targets about ${(preferences.calorieTarget / preferences.mealsPerDay).round()} kcal per person for this meal.';
        serviceNotice =
            'Live backend • ${plan.retrievalMethod} • ${plan.pantryItemCount} pantry items';
      } on MealPlanningApiException catch (error) {
        answer = ChefChatService.answer(question, pantryItems);
        serviceNotice = error.message;
      }
    } else {
      final result = await ChefChatService.askChefApi(question, pantryItems);
      answer = result.reply;
      if (!result.isLiveAi) {
        serviceNotice = 'Offline Chef · Connect backend for live AI';
      } else {
        serviceNotice = 'Live AI · chef-chat backend';
      }
    }
    if (!mounted) return;
    setState(() {
      _messages.add(
        _ChatMessage(
          text: answer,
          isUser: false,
          serviceNotice: serviceNotice,
          recommendations: recommendations,
        ),
      );
      _isReplying = false;
    });
    _scrollToBottom();
  }

  bool _isWeeklyPlanRequest(String question) {
    final normalized = question.toLowerCase();
    return normalized.contains('7 day') ||
        normalized.contains('7-day') ||
        normalized.contains('weekly plan') ||
        normalized.contains('week plan');
  }

  void _startCooking(RecipeRecommendationModel recipe) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => GuidedCookingScreen(recipe: recipe)),
    );
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final chefName = ChefNameFormatter.fromUser(
      context.watch<AuthProvider>().currentUser,
    );
    final muted = isDark
        ? AppTheme.textDarkSecondary
        : AppTheme.textLightSecondary;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Chef Chat'),
        actions: [
          if (_messages.isNotEmpty)
            IconButton(
              tooltip: 'Clear conversation',
              onPressed: () => setState(_messages.clear),
              icon: const Icon(Icons.delete_outline_rounded),
            ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: _messages.isEmpty
                  ? _EmptyChat(
                      chefName: chefName,
                      suggestions: _suggestions,
                      onSuggestion: _send,
                    )
                  : ListView.builder(
                      controller: _scrollController,
                      padding: const EdgeInsets.fromLTRB(16, 18, 16, 12),
                      itemCount: _messages.length + (_isReplying ? 1 : 0),
                      itemBuilder: (context, index) {
                        if (index == _messages.length) {
                          return const _TypingBubble();
                        }
                        return _MessageBubble(
                          message: _messages[index],
                          onCook: _startCooking,
                        );
                      },
                    ),
            ),
            if (_messages.isNotEmpty)
              SizedBox(
                height: 42,
                child: ListView.separated(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  scrollDirection: Axis.horizontal,
                  itemCount: _suggestions.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 8),
                  itemBuilder: (context, index) => ActionChip(
                    label: Text(_suggestions[index]),
                    onPressed: _isReplying
                        ? null
                        : () => _send(_suggestions[index]),
                  ),
                ),
              ),
            Container(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
              decoration: BoxDecoration(
                color: isDark ? AppTheme.surfaceDark : Colors.white,
                border: Border(
                  top: BorderSide(
                    color: isDark ? AppTheme.borderDark : AppTheme.borderLight,
                  ),
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    child: TextField(
                      key: const Key('chefChatInput'),
                      controller: _controller,
                      maxLines: 1,
                      textInputAction: TextInputAction.send,
                      onSubmitted: _isReplying ? null : _send,
                      style: const TextStyle(fontSize: 13),
                      decoration: InputDecoration(
                        hintText: 'Ask about recipes or your pantry…',
                        hintStyle: TextStyle(color: muted),
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(
                          vertical: 10,
                        ),
                        prefixIcon: const Icon(
                          Icons.chat_bubble_outline_rounded,
                          size: 19,
                        ),
                        prefixIconConstraints: const BoxConstraints(
                          minWidth: 40,
                          minHeight: 40,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  IconButton.filled(
                    key: const Key('chefChatSend'),
                    tooltip: 'Send',
                    onPressed: _isReplying ? null : _send,
                    constraints: const BoxConstraints.tightFor(
                      width: 40,
                      height: 40,
                    ),
                    padding: EdgeInsets.zero,
                    icon: const Icon(Icons.arrow_upward_rounded),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyChat extends StatelessWidget {
  final String chefName;
  final List<String> suggestions;
  final ValueChanged<String> onSuggestion;

  const _EmptyChat({
    required this.chefName,
    required this.suggestions,
    required this.onSuggestion,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final secondary = isDark
        ? AppTheme.textDarkSecondary
        : AppTheme.textLightSecondary;

    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 48, 24, 24),
      children: [
        Align(
          child: Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: AppTheme.primaryFlame.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Icon(
              Icons.soup_kitchen_outlined,
              size: 32,
              color: AppTheme.primaryFlame,
            ),
          ),
        ),
        const SizedBox(height: 18),
        Text(
          'What can I help you cook, Chef $chefName?',
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 8),
        Text(
          'Ask about your pantry, meal ideas, missing ingredients, cooking time, or step-by-step instructions.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 14, height: 1.5, color: secondary),
        ),
        const SizedBox(height: 28),
        for (final suggestion in suggestions)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: OutlinedButton(
              onPressed: () => onSuggestion(suggestion),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(suggestion),
              ),
            ),
          ),
      ],
    );
  }
}

class _MessageBubble extends StatelessWidget {
  final _ChatMessage message;
  final ValueChanged<RecipeRecommendationModel> onCook;

  const _MessageBubble({required this.message, required this.onCook});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Align(
      alignment: message.isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 350),
        child: Column(
          crossAxisAlignment: message.isUser
              ? CrossAxisAlignment.end
              : CrossAxisAlignment.start,
          children: [
            Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: message.isUser
                    ? AppTheme.primaryFlame
                    : (isDark ? AppTheme.surfaceDark2 : AppTheme.creamSurface),
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(18),
                  topRight: const Radius.circular(18),
                  bottomLeft: Radius.circular(message.isUser ? 18 : 4),
                  bottomRight: Radius.circular(message.isUser ? 4 : 18),
                ),
              ),
              child: Text(
                message.text,
                style: TextStyle(
                  height: 1.45,
                  color: message.isUser
                      ? Colors.white
                      : (isDark
                            ? AppTheme.textDarkPrimary
                            : AppTheme.textLightPrimary),
                ),
              ),
            ),
            if (message.serviceNotice != null)
              Padding(
                padding: const EdgeInsets.only(left: 4, bottom: 8),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      message.recommendations.isEmpty
                          ? Icons.cloud_off_outlined
                          : Icons.cloud_done_outlined,
                      size: 13,
                      color: message.recommendations.isEmpty
                          ? AppTheme.warmAmber
                          : AppTheme.freshHerb,
                    ),
                    const SizedBox(width: 5),
                    Flexible(
                      child: Text(
                        message.serviceNotice!,
                        style: TextStyle(
                          fontSize: 10,
                          color: isDark
                              ? AppTheme.textDarkMuted
                              : AppTheme.textLightMuted,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            for (final recommendation in message.recommendations)
              _BackendRecipeCard(
                recommendation: recommendation,
                isDark: isDark,
                onCook: () => onCook(recommendation.recipe),
              ),
            const SizedBox(height: 4),
          ],
        ),
      ),
    );
  }
}

class _BackendRecipeCard extends StatelessWidget {
  final BackendMealRecommendation recommendation;
  final bool isDark;
  final VoidCallback onCook;

  const _BackendRecipeCard({
    required this.recommendation,
    required this.isDark,
    required this.onCook,
  });

  @override
  Widget build(BuildContext context) {
    final recipe = recommendation.recipe;
    return Container(
      width: 350,
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark ? AppTheme.surfaceDark : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: AppTheme.primaryFlame.withValues(alpha: 0.24),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  recipe.title,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: AppTheme.freshHerb.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  '${recommendation.pantryMatchPercent}% match',
                  style: const TextStyle(
                    color: AppTheme.freshHerb,
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            '${recipe.mealType} • ${recipe.cookTimeMinutes} min • ${recipe.servings} servings',
            style: TextStyle(
              fontSize: 11,
              color: isDark
                  ? AppTheme.textDarkSecondary
                  : AppTheme.textLightSecondary,
            ),
          ),
          if (recommendation.missingIngredients.isNotEmpty) ...[
            const SizedBox(height: 7),
            Text(
              'Missing: ${recommendation.missingIngredients.join(', ')}',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 11, color: AppTheme.warmAmber),
            ),
          ],
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: recipe.instructions.isEmpty ? null : onCook,
              icon: const Icon(Icons.soup_kitchen_rounded, size: 17),
              label: const Text('Cook this recipe'),
            ),
          ),
        ],
      ),
    );
  }
}

class _TypingBubble extends StatelessWidget {
  const _TypingBubble();

  @override
  Widget build(BuildContext context) => const Align(
    alignment: Alignment.centerLeft,
    child: Padding(
      padding: EdgeInsets.fromLTRB(8, 4, 8, 16),
      child: SizedBox(
        width: 18,
        height: 18,
        child: CircularProgressIndicator(strokeWidth: 2),
      ),
    ),
  );
}

class _ChatMessage {
  final String text;
  final bool isUser;
  final String? serviceNotice;
  final List<BackendMealRecommendation> recommendations;

  const _ChatMessage({
    required this.text,
    required this.isUser,
    this.serviceNotice,
    this.recommendations = const [],
  });
}
