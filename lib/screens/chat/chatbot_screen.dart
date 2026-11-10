import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';

import '../../core/theme/app_theme.dart';
import '../../widgets/app_ui.dart';
import '../../core/utils/chef_name_formatter.dart';
import '../../models/recipe_discovery.dart';
import '../../widgets/live_recipe_card.dart';
import '../../providers/auth_provider.dart';
import '../../providers/pantry_provider.dart';
import '../../providers/recipe_experience_provider.dart';
import '../../services/chef_chat_service.dart';
import '../../services/meal_planning_api_service.dart';

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
        .where((item) => item.quantity > 0)
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
    var recommendations = const <DiscoveredRecipe>[];
    String? quantitiesNote;
    var serviceError = false;

    if (_isWeeklyPlanRequest(question)) {
      await Future<void>.delayed(const Duration(milliseconds: 180));
      answer = 'Open the Recipes tab and choose Meal plan to plan the next seven days using your pantry, people count, and calorie target.';
    } else if (ChefChatService.isMealPlanningQuestion(question)) {
      try {
        final plan = await _mealPlanningApi.discoverRecipes(
          question: question,
          pantryItems: pantryItems,
          resultCount: 5,
          dietaryPreferences: [
            ...preferences.dietaryNeeds,
            if (dietaryPreference != null && dietaryPreference.isNotEmpty)
              dietaryPreference,
          ],
          avoidIngredients: [
            ...preferences.allergens,
            ...preferences.dislikedIngredients,
          ],
        );
        recommendations = plan.recipes;
        answer =
            '${DateFormat('EEEE, d MMM').format(plan.planningDate)}\n${plan.message}';
        if (plan.excludedExpiredItems.isNotEmpty) {
          answer +=
              '\nExcluded for this date: ${plan.excludedExpiredItems.join(', ')}.';
        }
        quantitiesNote = recommendations.isEmpty ? null : plan.quantitiesNote;
        serviceNotice = plan.pantryItemCount == 0
            ? 'Inventory checked'
            : 'Live recipe search ? ${plan.pantryItemCount} pantry items ? ${plan.checkedRecipeCount} recipes checked';
      } on MealPlanningApiException catch (error) {
        answer = error.message;
        serviceNotice = 'Live recipe search unavailable ? Try again';
        serviceError = true;
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
          quantitiesNote: quantitiesNote,
          serviceError: serviceError,
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
                        return _MessageBubble(message: _messages[index]);
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
                      onChanged: (_) => setState(() {}),
                      maxLines: 1,
                      textInputAction: TextInputAction.send,
                      onSubmitted: _isReplying ? null : _send,
                      style: const TextStyle(fontSize: 14),
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
                    onPressed: _isReplying || _controller.text.trim().isEmpty
                        ? null
                        : _send,
                    style: IconButton.styleFrom(
                      foregroundColor: Theme.of(context).colorScheme.onPrimary,
                    ),
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
    final colors = Theme.of(context).colorScheme;
    const icons = [
      Icons.restaurant_outlined,
      Icons.shopping_basket_outlined,
      Icons.kitchen_outlined,
      Icons.menu_book_outlined,
    ];
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const BrandMark(showName: false),
                const SizedBox(height: 26),
                Text(
                  'A little inspiration,\nChef $chefName?',
                  style: Theme.of(context).textTheme.headlineLarge,
                ),
                const SizedBox(height: 12),
                Text(
                  'Good ideas start with your ingredients. Ask for a recipe, a plan, or a helping hand.',
                  style: Theme.of(context).textTheme.bodyLarge
                      ?.copyWith(color: colors.onSurfaceVariant),
                ),
                const SizedBox(height: 30),
                Text(
                  'LET’S MAKE SOMETHING GOOD',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    letterSpacing: 1.1,
                    color: colors.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 14),
                for (var index = 0; index < suggestions.length; index++)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Material(
                      color: colors.surface,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                        side: BorderSide(color: colors.outlineVariant),
                      ),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(14),
                        onTap: () => onSuggestion(suggestions[index]),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 18,
                          ),
                          child: Row(
                            children: [
                              Icon(
                                icons[index % icons.length],
                                size: 20,
                                color: colors.primary,
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Text(
                                  suggestions[index],
                                  style: Theme.of(context).textTheme.bodyMedium,
                                ),
                              ),
                              Icon(
                                Icons.arrow_forward_rounded,
                                size: 17,
                                color: colors.onSurfaceVariant,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  final _ChatMessage message;

  const _MessageBubble({required this.message});

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
                      message.serviceError
                          ? Icons.cloud_off_outlined
                          : Icons.cloud_done_outlined,
                      size: 13,
                      color: message.serviceError
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
              LiveRecipeCard(recipe: recommendation),
            if (message.quantitiesNote != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 0, 4, 12),
                child: Text(
                  message.quantitiesNote!,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            const SizedBox(height: 4),
          ],
        ),
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
  final List<DiscoveredRecipe> recommendations;
  final String? quantitiesNote;
  final bool serviceError;

  const _ChatMessage({
    required this.text,
    required this.isUser,
    this.serviceNotice,
    this.recommendations = const [],
    this.quantitiesNote,
    this.serviceError = false,
  });
}
