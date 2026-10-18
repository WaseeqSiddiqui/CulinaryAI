import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../models/recipe_recommendation_model.dart';
import '../../providers/pantry_provider.dart';
import '../../providers/recipe_experience_provider.dart';

class GuidedCookingScreen extends StatefulWidget {
  final RecipeRecommendationModel recipe;

  const GuidedCookingScreen({super.key, required this.recipe});

  @override
  State<GuidedCookingScreen> createState() => _GuidedCookingScreenState();
}

class _GuidedCookingScreenState extends State<GuidedCookingScreen> {
  int _stepIndex = 0;
  Timer? _timer;
  int _remainingSeconds = 0;

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _chooseTimer() async {
    final minutes = await showModalBottomSheet<int>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const ListTile(
              title: Text(
                'Step timer',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
              subtitle: Text(
                'Choose a duration while you stay in cooking mode.',
              ),
            ),
            Wrap(
              spacing: 8,
              children: [1, 3, 5, 10, 15, 20]
                  .map(
                    (value) => ActionChip(
                      label: Text('$value min'),
                      onPressed: () => Navigator.pop(context, value),
                    ),
                  )
                  .toList(),
            ),
            const SizedBox(height: 18),
          ],
        ),
      ),
    );
    if (minutes == null || !mounted) return;
    _timer?.cancel();
    setState(() => _remainingSeconds = minutes * 60);
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted || _remainingSeconds <= 1) {
        timer.cancel();
        if (mounted) {
          setState(() => _remainingSeconds = 0);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Timer finished — check your food.')),
          );
        }
        return;
      }
      setState(() => _remainingSeconds--);
    });
  }

  String get _timerLabel {
    final minutes = _remainingSeconds ~/ 60;
    final seconds = _remainingSeconds % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

  Future<void> _finishCooking() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Finished cooking?'),
        content: const Text(
          'Pantry ingredients are deducted only after you confirm the meal was cooked.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Not yet'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Yes, I cooked this'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    final changed = context.read<PantryProvider>().deductIngredients(
      widget.recipe.requiredIngredients,
    );
    await context.read<RecipeExperienceProvider>().recordCooked(widget.recipe);
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        icon: const Icon(
          Icons.check_circle_rounded,
          color: AppTheme.freshHerb,
          size: 42,
        ),
        title: const Text('Meal completed'),
        content: Text(
          changed == 0
              ? 'Meal saved. No matching pantry quantities needed adjustment.'
              : '$changed pantry item(s) were safely adjusted.',
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Done'),
          ),
        ],
      ),
    );
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final steps = widget.recipe.instructions;
    final isLast = _stepIndex == steps.length - 1;
    final progress = (_stepIndex + 1) / steps.length;

    return Scaffold(
      appBar: AppBar(title: const Text('Guided cooking')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                widget.recipe.title,
                style: Theme.of(context).textTheme.titleLarge
                    ?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 18),
              LinearProgressIndicator(value: progress),
              const SizedBox(height: 10),
              Text('Step ${_stepIndex + 1} of ${steps.length}'),
              const SizedBox(height: 12),
              Center(
                child: ActionChip(
                  avatar: Icon(
                    _remainingSeconds > 0
                        ? Icons.timer_rounded
                        : Icons.timer_outlined,
                  ),
                  label: Text(
                    _remainingSeconds > 0 ? _timerLabel : 'Start a timer',
                  ),
                  onPressed: _chooseTimer,
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainer,
                  borderRadius: BorderRadius.circular(22),
                ),
                child: Column(
                  children: [
                    CircleAvatar(
                      radius: 25,
                      backgroundColor: AppTheme.primaryFlame,
                      foregroundColor: Colors.white,
                      child: Text(
                        '${_stepIndex + 1}',
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      steps[_stepIndex],
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 19, height: 1.45),
                    ),
                  ],
                ),
              ),
              const Spacer(),
              Row(
                children: [
                  if (_stepIndex > 0)
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => setState(() => _stepIndex--),
                        child: const Text('Previous'),
                      ),
                    ),
                  if (_stepIndex > 0) const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      onPressed: isLast
                          ? _finishCooking
                          : () => setState(() => _stepIndex++),
                      child: Text(isLast ? 'Finish cooking' : 'Next step'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
