import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../widgets/app_ui.dart';
import '../../models/cooking_session.dart';
import '../../models/recipe_ingredient.dart';
import '../../models/recipe_recommendation_model.dart';
import '../../providers/auth_provider.dart';
import '../../providers/cooking_session_provider.dart';
import '../../providers/pantry_provider.dart';
import '../../providers/recipe_experience_provider.dart';

class GuidedCookingScreen extends StatelessWidget {
  final RecipeRecommendationModel recipe;

  const GuidedCookingScreen({super.key, required this.recipe});

  @override
  Widget build(BuildContext context) {
    final preferences = context.read<RecipeExperienceProvider>().preferences;
    return ChangeNotifierProvider(
      create: (_) => CookingSessionProvider(
        recipe: recipe,
        dietaryRestrictions: [
          ...preferences.dietaryNeeds,
          ...preferences.allergens,
        ],
      )..initialize(),
      child: _GuidedCookingView(recipe: recipe),
    );
  }
}

class _GuidedCookingView extends StatefulWidget {
  final RecipeRecommendationModel recipe;

  const _GuidedCookingView({required this.recipe});

  @override
  State<_GuidedCookingView> createState() => _GuidedCookingViewState();
}

class _GuidedCookingViewState extends State<_GuidedCookingView> {
  final _messageController = TextEditingController();
  final _scrollController = ScrollController();
  final _picker = ImagePicker();
  bool _timerNoticeShown = false;
  bool _pickingPhoto = false;

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _chooseTimer() async {
    final session = context.read<CookingSessionProvider>();
    final minutes = await showModalBottomSheet<int>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Step timer',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 4),
              const Text(
                'Times are estimates. Always confirm doneness from the displayed cues.',
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [1, 3, 5, 8, 10, 15, 20, 30]
                    .map(
                      (value) => ActionChip(
                        label: Text('$value min'),
                        onPressed: () => Navigator.pop(context, value),
                      ),
                    )
                    .toList(),
              ),
            ],
          ),
        ),
      ),
    );
    if (minutes != null && mounted) session.startTimer(minutes);
  }

  Future<void> _pickImage(ImageSource source) async {
    if (_pickingPhoto) return;
    _pickingPhoto = true;
    try {
      final picked = await _picker.pickImage(
        source: source,
        imageQuality: 78,
        maxWidth: 1600,
        maxHeight: 1600,
      );
      if (picked == null || !mounted) return;
      final imageBytes = await picked.readAsBytes();
      if (!mounted) return;
      final questionController = TextEditingController(
        text: 'Does this look ready for the current step?',
      );
      final shouldSend = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Check cooking progress'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: Image.memory(
                    imageBytes,
                    height: 210,
                    width: double.infinity,
                    fit: BoxFit.cover,
                  ),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: questionController,
                  maxLines: 2,
                  decoration: const InputDecoration(
                    labelText: 'Question for Chef',
                    hintText: 'Is this the right color?',
                  ),
                ),
                const SizedBox(height: 10),
                const Text(
                  'A photo can help assess visible progress, but it cannot prove internal temperature or food safety.',
                  style: TextStyle(fontSize: 11),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Retake'),
            ),
            FilledButton.icon(
              onPressed: () => Navigator.pop(dialogContext, true),
              icon: const Icon(Icons.auto_awesome_rounded),
              label: const Text('Ask Chef'),
            ),
          ],
        ),
      );
      final question = questionController.text;
      questionController.dispose();
      if (shouldSend != true || !mounted) return;
      final userId =
          context.read<AuthProvider>().currentUser?.id ?? 'guest_cook';
      await context.read<CookingSessionProvider>().submitImage(
        imageBytes: imageBytes,
        imageName: picked.name,
        imagePath: picked.path,
        question: question,
        userId: userId,
      );
      _scrollToBottom();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'That photo could not be opened. Check camera permissions or choose another photo.',
            ),
          ),
        );
      }
    } finally {
      _pickingPhoto = false;
    }
  }

  Future<void> _send() async {
    final text = _messageController.text.trim();
    if (text.isEmpty) return;
    _messageController.clear();
    await context.read<CookingSessionProvider>().submitQuestion(text);
    _scrollToBottom();
  }

  Future<void> _finishCooking() async {
    final pantry = context.read<PantryProvider>();
    final confirmedUsage = await showDialog<List<RecipeIngredient>>(
      context: context,
      builder: (dialogContext) =>
          _ConsumptionConfirmationDialog(recipe: widget.recipe, pantry: pantry),
    );
    if (confirmedUsage == null || !mounted) return;
    final experience = context.read<RecipeExperienceProvider>();
    final cookingSession = context.read<CookingSessionProvider>();
    final userId = context.read<AuthProvider>().currentUser?.id ?? 'guest_cook';
    PantryConsumptionResult consumption;
    try {
      consumption = await pantry.consumeIngredients(
        ingredients: confirmedUsage,
        recipeId: widget.recipe.id,
        recipeTitle: widget.recipe.title,
        actorId: userId,
      );
    } on Object catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error.toString().replaceFirst('Bad state: ', '')),
        ),
      );
      return;
    }
    await experience.recordCooked(widget.recipe);
    await cookingSession.clearSavedSession();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          consumption.changedItems == 0
              ? 'Meal completed and saved.'
              : 'Meal completed; ${consumption.changedItems} pantry item(s) adjusted.',
        ),
      ),
    );
    Navigator.pop(context);
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOut,
      );
    });
  }

  Future<void> _showGuidance() async {
    final session = context.read<CookingSessionProvider>();
    final detail = session.currentDetail;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.72,
        minChildSize: 0.45,
        maxChildSize: 0.92,
        builder: (context, controller) => ListView(
          controller: controller,
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
          children: [
            const Text(
              'Full step guidance',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 6),
            Text(
              detail.action.split(' Ingredients for this step:').first.trim(),
              style: const TextStyle(fontSize: 16, height: 1.45),
            ),
            const SizedBox(height: 22),
            _DetailRow(title: 'Technique', body: detail.technique),
            _DetailRow(title: 'Look for', body: detail.visualCues.join(' • ')),
            _DetailRow(
              title: 'Texture, aroma & sound',
              body: detail.textureAndAroma,
            ),
            _DetailRow(title: 'Ready when', body: detail.completionCriteria),
            if (detail.precautions.isNotEmpty)
              _DetailRow(
                title: 'Avoid',
                body: detail.precautions.join(' • '),
                warning: true,
              ),
            if (detail.proTip.isNotEmpty)
              _DetailRow(title: 'Chef tip', body: detail.proTip),
          ],
        ),
      ),
    );
  }

  Future<void> _showIngredientChecklist() async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
          children: [
            const Text(
              'Complete ingredient checklist',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 4),
            Text('${widget.recipe.servings} servings'),
            const SizedBox(height: 14),
            for (final ingredient in widget.recipe.ingredientDetails)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.check_box_outline_blank_rounded),
                title: Text(ingredient.name),
                trailing: Text(
                  '${_formatIngredientQuantity(ingredient.quantity)} ${ingredient.unit}',
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<CookingSessionProvider>(
      builder: (context, session, _) {
        if (session.timerFinished && !_timerNoticeShown) {
          _timerNoticeShown = true;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text(
                  'Timer finished — check the food, not just the clock.',
                ),
              ),
            );
            session.acknowledgeTimer();
            _timerNoticeShown = false;
          });
        }
        final isDark = Theme.of(context).brightness == Brightness.dark;
        return DefaultTabController(
          length: 2,
          child: Scaffold(
            backgroundColor: isDark ? AppTheme.bgDark : null,
            appBar: AppBar(
              title: const Text('Cook along'),
              actions: [
                IconButton(
                  tooltip: 'Ingredient checklist',
                  onPressed: _showIngredientChecklist,
                  icon: const Icon(Icons.checklist_rounded),
                ),
                PopupMenuButton<String>(
                  tooltip: 'Voice language',
                  initialValue: session.voiceLocale,
                  onSelected: session.setVoiceLocale,
                  itemBuilder: (_) => const [
                    PopupMenuItem(
                      value: 'auto',
                      child: Text('Auto / mixed voice'),
                    ),
                    PopupMenuItem(value: 'en', child: Text('English voice')),
                    PopupMenuItem(value: 'ur', child: Text('Urdu voice')),
                  ],
                  icon: const Icon(Icons.language_rounded),
                ),
              ],
              bottom: const TabBar(
                tabs: [
                  Tab(icon: Icon(Icons.soup_kitchen_rounded), text: 'Cook'),
                  Tab(icon: Icon(Icons.forum_outlined), text: 'Ask Chef'),
                ],
              ),
            ),
            body: SafeArea(
              child: AppPageBody(
                child: TabBarView(
                  children: [
                    _CookTab(
                      session: session,
                      recipe: widget.recipe,
                      onTimer: _chooseTimer,
                      onGuidance: _showGuidance,
                      onFinish: _finishCooking,
                    ),
                    _AssistantTab(
                      session: session,
                      scrollController: _scrollController,
                      messageController: _messageController,
                      onSend: _send,
                      onCamera: () => _pickImage(ImageSource.camera),
                      onGallery: () => _pickImage(ImageSource.gallery),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _CookTab extends StatelessWidget {
  final CookingSessionProvider session;
  final RecipeRecommendationModel recipe;
  final VoidCallback onTimer;
  final VoidCallback onGuidance;
  final VoidCallback onFinish;

  const _CookTab({
    required this.session,
    required this.recipe,
    required this.onTimer,
    required this.onGuidance,
    required this.onFinish,
  });

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final wide = constraints.maxWidth >= 780;
      final next = StatusNotice(
        icon: session.isLastStep
            ? Icons.restaurant_outlined
            : Icons.arrow_forward_rounded,
        message: session.isLastStep
            ? 'Ready to serve? Review the ingredients you used before finishing.'
            : 'Up next: ${recipe.instructions[session.stepIndex + 1]}',
      );
      return Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
              children: [
                Text(
                  recipe.title,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 8),
                Text(
                  '${recipe.cuisine} · ${recipe.cookTimeMinutes} min',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 22),
                _StepHeader(session: session, recipe: recipe),
                const SizedBox(height: 22),
                if (session.error != null)
                  _ErrorBanner(
                    message: session.error!,
                    onRetry: session.loadCurrentDetail,
                  ),
                if (wide)
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        flex: 3,
                        child: _InstructionCard(
                          session: session,
                          onTimer: onTimer,
                          onGuidance: onGuidance,
                        ),
                      ),
                      const SizedBox(width: 24),
                      Expanded(
                        flex: 2,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _StepControls(session: session, onFinish: onFinish),
                            const SizedBox(height: 18),
                            next,
                          ],
                        ),
                      ),
                    ],
                  )
                else ...[
                  _InstructionCard(
                    session: session,
                    onTimer: onTimer,
                    onGuidance: onGuidance,
                  ),
                  const SizedBox(height: 18),
                  next,
                ],
              ],
            ),
          ),
          if (!wide)
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 10, 24, 10),
              child: _StepControls(session: session, onFinish: onFinish),
            ),
          _CookHelpBar(session: session),
        ],
      );
    },
  );
}

class _ConsumptionConfirmationDialog extends StatefulWidget {
  final RecipeRecommendationModel recipe;
  final PantryProvider pantry;

  const _ConsumptionConfirmationDialog({
    required this.recipe,
    required this.pantry,
  });

  @override
  State<_ConsumptionConfirmationDialog> createState() =>
      _ConsumptionConfirmationDialogState();
}

class _ConsumptionConfirmationDialogState
    extends State<_ConsumptionConfirmationDialog> {
  late final List<bool> _included;
  late final List<double> _quantities;

  @override
  void initState() {
    super.initState();
    _included = List.filled(widget.recipe.ingredientDetails.length, true);
    _quantities = widget.recipe.ingredientDetails
        .map((ingredient) => ingredient.quantity)
        .toList();
  }

  List<RecipeIngredient> get _usage => [
    for (var index = 0; index < widget.recipe.ingredientDetails.length; index++)
      if (_included[index] && _quantities[index] > 0)
        RecipeIngredient(
          name: widget.recipe.ingredientDetails[index].name,
          quantity: _quantities[index],
          unit: widget.recipe.ingredientDetails[index].unit,
        ),
  ];

  @override
  Widget build(BuildContext context) {
    final checks = widget.pantry.previewConsumption(_usage);
    final checkByName = {
      for (final check in checks) check.ingredient.name: check,
    };
    final hasInsufficient = checks.any((check) => !check.isSufficient);
    return AlertDialog(
      title: const Text('Confirm ingredient usage'),
      content: SizedBox(
        width: double.maxFinite,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Adjust or uncheck anything you skipped. Stock changes only after confirmation.',
              ),
              const SizedBox(height: 12),
              for (
                var index = 0;
                index < widget.recipe.ingredientDetails.length;
                index++
              )
                Builder(
                  builder: (context) {
                    final ingredient = widget.recipe.ingredientDetails[index];
                    final check = checkByName[ingredient.name];
                    return Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Theme.of(context)
                            .colorScheme
                            .surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        children: [
                          Checkbox(
                            value: _included[index],
                            onChanged: (value) => setState(
                              () => _included[index] = value ?? false,
                            ),
                          ),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  ingredient.name,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                if (_included[index] && check != null)
                                  Text(
                                    check.isSufficient
                                        ? '${_formatIngredientQuantity(check.availableInRecipeUnit)} ${ingredient.unit} available'
                                        : 'Short by ${_formatIngredientQuantity(check.shortage)} ${ingredient.unit}',
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: check.isSufficient
                                          ? AppTheme.freshHerb
                                          : AppTheme.errorRed,
                                    ),
                                  ),
                                if (_included[index] &&
                                    check?.hasAmbiguousPackage == true)
                                  const Text(
                                    'A matching legacy package has unknown capacity.',
                                    style: TextStyle(
                                      fontSize: 10,
                                      color: AppTheme.warmAmber,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          SizedBox(
                            width: 74,
                            child: TextFormField(
                              initialValue: _formatIngredientQuantity(
                                ingredient.quantity,
                              ),
                              enabled: _included[index],
                              textAlign: TextAlign.end,
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                    decimal: true,
                                  ),
                              decoration: InputDecoration(
                                suffixText: ingredient.unit,
                                isDense: true,
                              ),
                              onChanged: (value) => setState(
                                () => _quantities[index] =
                                    double.tryParse(value) ?? 0,
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              if (hasInsufficient)
                const Text(
                  'Resolve shortages in the pantry or uncheck ingredients you did not consume.',
                  style: TextStyle(color: AppTheme.errorRed, fontSize: 12),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Keep cooking'),
        ),
        FilledButton(
          onPressed: hasInsufficient
              ? null
              : () => Navigator.pop(context, _usage),
          child: const Text('Confirm and finish'),
        ),
      ],
    );
  }
}

class _CookHelpBar extends StatelessWidget {
  final CookingSessionProvider session;
  const _CookHelpBar({required this.session});

  void _openChat(BuildContext context) {
    DefaultTabController.of(context).animateTo(1);
  }

  Future<void> _startVoice(BuildContext context) async {
    DefaultTabController.of(context).animateTo(1);
    await Future<void>.delayed(const Duration(milliseconds: 220));
    await session.toggleListening();
  }

  @override
  Widget build(BuildContext context) {
    final disabled = session.sending || session.analyzingImage;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border(
          top: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              'Need a hand?',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
          TextButton.icon(
            onPressed: disabled ? null : () => _openChat(context),
            icon: const Icon(Icons.chat_bubble_outline_rounded, size: 18),
            label: const Text('Ask Chef'),
          ),
          IconButton.filledTonal(
            tooltip: 'Talk to Chef',
            onPressed: disabled ? null : () => _startVoice(context),
            icon: const Icon(Icons.mic_outlined, size: 20),
          ),
        ],
      ),
    );
  }
}

class _AssistantTab extends StatelessWidget {
  final CookingSessionProvider session;
  final ScrollController scrollController;
  final TextEditingController messageController;
  final VoidCallback onSend;
  final VoidCallback onCamera;
  final VoidCallback onGallery;

  const _AssistantTab({
    required this.session,
    required this.scrollController,
    required this.messageController,
    required this.onSend,
    required this.onCamera,
    required this.onGallery,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Column(
      children: [
        Expanded(
          child: session.messages.isEmpty
              ? _EmptyAssistant(session: session)
              : ListView(
                  controller: scrollController,
                  padding: const EdgeInsets.fromLTRB(16, 18, 16, 12),
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 9,
                      ),
                      margin: const EdgeInsets.only(bottom: 16),
                      decoration: BoxDecoration(
                        color: isDark
                            ? AppTheme.surfaceDark
                            : Theme.of(context).colorScheme.surfaceContainer,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        'Step ${session.stepNumber}: ${session.currentInstruction}',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    for (final message in session.messages)
                      _CookingMessageBubble(message: message),
                    if (session.sending || session.analyzingImage)
                      const Padding(
                        padding: EdgeInsets.all(14),
                        child: Center(
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      ),
                  ],
                ),
        ),
        _VoiceDock(session: session),
        _Composer(
          controller: messageController,
          session: session,
          onSend: onSend,
          onCamera: onCamera,
          onGallery: onGallery,
        ),
      ],
    );
  }
}

class _EmptyAssistant extends StatelessWidget {
  final CookingSessionProvider session;
  const _EmptyAssistant({required this.session});

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    child: KitchenEmptyState(
      icon: Icons.soup_kitchen_outlined,
      title: 'A little backup, right here.',
      message:
          'Ask a question, talk hands-free or share a photo. Chef knows you are on step ${session.stepNumber}.',
    ),
  );
}

class _StepHeader extends StatelessWidget {
  final CookingSessionProvider session;
  final RecipeRecommendationModel recipe;

  const _StepHeader({required this.session, required this.recipe});

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(
        children: [
          Text(
            'CURRENT STEP',
            style: TextStyle(
              fontSize: 10,
              letterSpacing: 0.9,
              fontWeight: FontWeight.w800,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const Spacer(),
          Text(
            '${session.stepNumber} of ${recipe.instructions.length}',
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
        ],
      ),
      const SizedBox(height: 8),
      LinearProgressIndicator(
        value: session.stepNumber / recipe.instructions.length,
        minHeight: 6,
        borderRadius: BorderRadius.circular(8),
      ),
      if (session.completedSteps.isNotEmpty) ...[
        const SizedBox(height: 8),
        Wrap(
          spacing: 6,
          children: [
            for (var i = 0; i < recipe.instructions.length; i++)
              InkWell(
                onTap: () => session.revisitStep(i),
                borderRadius: BorderRadius.circular(20),
                child: CircleAvatar(
                  radius: 13,
                  backgroundColor: i == session.stepIndex
                      ? AppTheme.primaryFlame
                      : session.completedSteps.contains(i)
                      ? AppTheme.freshHerb
                      : Theme.of(context).colorScheme.surfaceContainerHighest,
                  foregroundColor: i <= session.stepIndex
                      ? Colors.white
                      : Theme.of(context).colorScheme.onSurfaceVariant,
                  child: Text('${i + 1}', style: const TextStyle(fontSize: 10)),
                ),
              ),
          ],
        ),
      ],
    ],
  );
}

class _InstructionCard extends StatelessWidget {
  final CookingSessionProvider session;
  final VoidCallback onTimer;
  final VoidCallback onGuidance;

  const _InstructionCard({
    required this.session,
    required this.onTimer,
    required this.onGuidance,
  });

  @override
  Widget build(BuildContext context) {
    final detail = session.currentDetail;
    final dark = Theme.of(context).brightness == Brightness.dark;
    return SurfacePanel(
      padding: const EdgeInsets.all(22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'STEP ${session.stepNumber}',
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              letterSpacing: .8,
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
          const SizedBox(height: 14),
          Text(
            detail.action.split(' Ingredients for this step:').first.trim(),
            style: Theme.of(context).textTheme.titleLarge
                ?.copyWith(fontSize: 22, height: 1.45),
          ),
          const SizedBox(height: 24),
          _StepIngredientPanel(
            ingredients: session.recipe.ingredientsForStep(session.stepIndex),
            isDark: dark,
          ),
          const SizedBox(height: 18),
          FormFieldPair(
            first: _MetricTile(
              icon: Icons.local_fire_department_outlined,
              title: 'Heat',
              value: detail.heatLevel,
              isDark: dark,
            ),
            second: _MetricTile(
              icon: Icons.timer_outlined,
              title: session.remainingSeconds > 0 ? 'Timer' : 'Estimate',
              value: session.remainingSeconds > 0
                  ? session.timerLabel
                  : detail.estimatedDuration,
              isDark: dark,
              onTap: onTimer,
            ),
          ),
          const SizedBox(height: 16),
          Text(detail.pace, style: Theme.of(context).textTheme.bodySmall),
          if (session.loadingDetail) ...[
            const SizedBox(height: 16),
            const LinearProgressIndicator(),
          ],
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: onGuidance,
            icon: const Icon(Icons.menu_book_outlined, size: 18),
            label: const Text('Technique & doneness guide'),
          ),
        ],
      ),
    );
  }
}

class _StepIngredientPanel extends StatelessWidget {
  final List<RecipeIngredient> ingredients;
  final bool isDark;

  const _StepIngredientPanel({required this.ingredients, required this.isDark});

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: isDark ? AppTheme.surfaceDark2 : AppTheme.creamSurface,
      borderRadius: BorderRadius.circular(14),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(
              Icons.ramen_dining_rounded,
              size: 17,
              color: AppTheme.primaryFlame,
            ),
            SizedBox(width: 7),
            Expanded(
              child: Text(
                'Ingredients for this step',
                style: TextStyle(
                  fontSize: 10,
                  letterSpacing: 0.6,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (ingredients.isEmpty)
          Text(
            'No new measured ingredients. Continue with what is already prepared or in the pan.',
            style: TextStyle(
              fontSize: 12,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          )
        else
          for (final ingredient in ingredients)
            Padding(
              padding: const EdgeInsets.only(bottom: 5),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      ingredient.name,
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                  Text(
                    '${_formatIngredientQuantity(ingredient.quantity)} ${ingredient.unit}',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
      ],
    ),
  );
}

class _MetricTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String value;
  final bool isDark;
  final VoidCallback? onTap;

  const _MetricTile({
    required this.icon,
    required this.title,
    required this.value,
    required this.isDark,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(14),
    child: Container(
      constraints: const BoxConstraints(minHeight: 86),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isDark ? AppTheme.surfaceDark2 : AppTheme.creamSurface,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Icon(icon, size: 20, color: AppTheme.primaryFlame),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title.toUpperCase(),
                  style: TextStyle(
                    fontSize: 9,
                    letterSpacing: 0.7,
                    fontWeight: FontWeight.w800,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  value,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

class _DetailRow extends StatelessWidget {
  final String title;
  final String body;
  final bool warning;
  const _DetailRow({
    required this.title,
    required this.body,
    this.warning = false,
  });
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          warning
              ? Icons.warning_amber_rounded
              : Icons.check_circle_outline_rounded,
          size: 18,
          color: warning ? AppTheme.warmAmber : AppTheme.freshHerb,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text('$title: $body', style: const TextStyle(height: 1.4)),
        ),
      ],
    ),
  );
}

String _formatIngredientQuantity(double value) {
  if (value == value.roundToDouble()) return value.toInt().toString();
  return value
      .toStringAsFixed(value < 1 ? 2 : 1)
      .replaceFirst(RegExp(r'0+$'), '')
      .replaceFirst(RegExp(r'\.$'), '');
}

class _StepControls extends StatelessWidget {
  final CookingSessionProvider session;
  final VoidCallback onFinish;
  const _StepControls({required this.session, required this.onFinish});

  @override
  Widget build(BuildContext context) => Row(
    children: [
      IconButton.outlined(
        tooltip: 'Previous step',
        onPressed: session.stepIndex == 0 ? null : session.previousStep,
        icon: const Icon(Icons.chevron_left_rounded),
      ),
      const SizedBox(width: 8),
      Expanded(
        child: FilledButton(
          onPressed: session.isLastStep ? onFinish : session.nextStep,
          child: Text(
            session.isLastStep ? 'Finish cooking' : 'Next step',
            textAlign: TextAlign.center,
          ),
        ),
      ),
      const SizedBox(width: 8),
      IconButton.outlined(
        tooltip: 'Repeat step',
        onPressed: session.repeatStep,
        icon: const Icon(Icons.replay_rounded, size: 21),
      ),
      const SizedBox(width: 8),
      IconButton.outlined(
        tooltip: session.isPaused ? 'Resume session' : 'Pause session',
        onPressed: session.togglePause,
        icon: Icon(
          session.isPaused ? Icons.play_arrow_rounded : Icons.pause_rounded,
          size: 21,
        ),
      ),
    ],
  );
}

class _CookingMessageBubble extends StatelessWidget {
  final CookingChatMessage message;
  const _CookingMessageBubble({required this.message});
  @override
  Widget build(BuildContext context) {
    final path = message.imagePath;
    final hasImage =
        path != null &&
        (kIsWeb ? path.startsWith('blob:') : File(path).existsSync());
    return Align(
      alignment: message.isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 360),
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: message.isUser
              ? AppTheme.primaryFlame
              : Theme.of(context).brightness == Brightness.dark
              ? AppTheme.surfaceDark2
              : Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(16),
          border: message.isUser
              ? null
              : Border.all(
                  color: Theme.of(context).brightness == Brightness.dark
                      ? AppTheme.borderDark
                      : Theme.of(context).colorScheme.outlineVariant,
                ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (hasImage) ...[
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: Image(
                  image: kIsWeb ? NetworkImage(path) : FileImage(File(path)),
                  height: 150,
                  width: 260,
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => const SizedBox.shrink(),
                ),
              ),
              const SizedBox(height: 8),
            ],
            if (message.visionResult != null) ...[
              Text(
                message.visionResult!.headline,
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 5),
            ],
            Text(
              message.text,
              style: TextStyle(
                height: 1.4,
                color: message.isUser ? Colors.white : null,
              ),
            ),
            if (message.visionResult != null) ...[
              const SizedBox(height: 8),
              Text(
                message.visionResult!.imageSufficient
                    ? 'Visual confidence ${(message.visionResult!.confidence * 100).round()}%'
                    : 'Image insufficient — retake in good light',
                style: const TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _VoiceDock extends StatelessWidget {
  final CookingSessionProvider session;
  const _VoiceDock({required this.session});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final disabled = session.sending || session.analyzingImage;
    final title = session.voiceInitializing
        ? 'Preparing voice'
        : session.isListening
        ? 'Listening now'
        : session.isSpeaking
        ? 'Chef is speaking'
        : session.speechAvailable
        ? 'Tap to talk'
        : 'Retry voice setup';
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 2),
      child: Material(
        color: isDark ? AppTheme.surfaceDark : Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(
            color: session.isListening
                ? Colors.red.withValues(alpha: 0.7)
                : isDark
                ? AppTheme.borderDark
                : AppTheme.creamBorder,
          ),
        ),
        child: InkWell(
          onTap: disabled ? null : session.toggleListening,
          borderRadius: BorderRadius.circular(18),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    color: session.isListening
                        ? Colors.red
                        : AppTheme.primaryFlame,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    session.voiceInitializing
                        ? Icons.more_horiz_rounded
                        : session.isListening
                        ? Icons.stop_rounded
                        : Icons.mic_rounded,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        session.statusLabel,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  session.speechAvailable
                      ? Icons.graphic_eq_rounded
                      : Icons.refresh_rounded,
                  color: session.isListening
                      ? Colors.red
                      : Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Composer extends StatelessWidget {
  final TextEditingController controller;
  final CookingSessionProvider session;
  final VoidCallback onSend;
  final VoidCallback onCamera;
  final VoidCallback onGallery;
  const _Composer({
    required this.controller,
    required this.session,
    required this.onSend,
    required this.onCamera,
    required this.onGallery,
  });
  @override
  Widget build(BuildContext context) {
    final busy = session.sending || session.analyzingImage;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
      decoration: BoxDecoration(
        color: isDark ? AppTheme.bgDark : Theme.of(context).colorScheme.surface,
        border: Border(top: BorderSide(color: Theme.of(context).dividerColor)),
      ),
      child: Row(
        children: [
          PopupMenuButton<String>(
            tooltip: 'Add cooking photo',
            enabled: !busy,
            onSelected: (value) => value == 'camera' ? onCamera() : onGallery(),
            itemBuilder: (_) => const [
              PopupMenuItem(
                value: 'camera',
                child: ListTile(
                  leading: Icon(Icons.camera_alt_rounded),
                  title: Text('Take photo'),
                ),
              ),
              PopupMenuItem(
                value: 'gallery',
                child: ListTile(
                  leading: Icon(Icons.photo_library_outlined),
                  title: Text('Choose from gallery'),
                ),
              ),
            ],
            icon: const Icon(Icons.add_a_photo_outlined),
          ),
          Expanded(
            child: TextField(
              key: const Key('cookingChatInput'),
              controller: controller,
              enabled: !busy,
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => onSend(),
              decoration: const InputDecoration(
                hintText: 'Ask Chef about this step…',
                isDense: true,
                contentPadding: EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 11,
                ),
              ),
            ),
          ),
          const SizedBox(width: 6),
          IconButton.filled(
            tooltip: 'Send message',
            onPressed: busy ? null : onSend,
            icon: const Icon(Icons.send_rounded),
          ),
        ],
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const _ErrorBanner({required this.message, required this.onRetry});
  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 10),
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: AppTheme.warmAmber.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(12),
    ),
    child: Row(
      children: [
        const Icon(Icons.wifi_off_rounded, color: AppTheme.warmAmber),
        const SizedBox(width: 10),
        Expanded(
          child: Tooltip(
            message: message,
            child: const Text(
              'Extra guidance could not load. You can continue with the recipe steps.',
              style: TextStyle(fontSize: 12),
            ),
          ),
        ),
        TextButton(onPressed: onRetry, child: const Text('Retry')),
      ],
    ),
  );
}
