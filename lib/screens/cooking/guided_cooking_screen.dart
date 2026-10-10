import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../models/recipe_recommendation_model.dart';
import '../../providers/pantry_provider.dart';

class GuidedCookingScreen extends StatefulWidget {
  final RecipeRecommendationModel recipe;

  const GuidedCookingScreen({super.key, required this.recipe});

  @override
  State<GuidedCookingScreen> createState() => _GuidedCookingScreenState();
}

class _GuidedCookingScreenState extends State<GuidedCookingScreen> {
  int _stepIndex = 0;

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
