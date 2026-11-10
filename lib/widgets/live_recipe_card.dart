import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/recipe_discovery.dart';
import 'app_ui.dart';

class LiveRecipeCard extends StatelessWidget {
  const LiveRecipeCard({super.key, required this.recipe});
  final DiscoveredRecipe recipe;

  Future<void> _open(BuildContext context) async {
    try {
      if (await launchUrl(
        recipe.sourceUrl,
        mode: LaunchMode.externalApplication,
        webOnlyWindowName: '_blank',
      )) {
        return;
      }
    } catch (_) {}
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'The recipe website could not be opened. Please try again.',
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final missing = recipe.ingredients
        .where(
          (item) => item.status == 'missing' || item.status == 'insufficient',
        )
        .toList();
    final uncertain = recipe.ingredients
        .where((item) => item.status == 'check_quantity')
        .toList();
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: SurfacePanel(
        padding: EdgeInsets.zero,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (recipe.imageUrl.isNotEmpty)
              Image.network(
                recipe.imageUrl,
                height: 150,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => const SizedBox.shrink(),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    recipe.canCookNow
                        ? 'PANTRY COVERS THIS RECIPE'
                        : 'A CLOSE MATCH · CHECK FIRST',
                    style: Theme.of(context).textTheme.labelSmall
                        ?.copyWith(color: colors.primary, letterSpacing: .5),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    recipe.name,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    [
                      recipe.cuisine,
                      recipe.category,
                    ].where((item) => item.isNotEmpty).join(' · '),
                    style: Theme.of(context).textTheme.bodySmall
                        ?.copyWith(color: colors.onSurfaceVariant),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    '${recipe.pantryMatchPercent}% of ingredient quantities confirmed',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  if (missing.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(
                      'Need: ${missing.map((item) => item.name).join(', ')}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                  if (uncertain.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(
                      'Check amounts: ${uncertain.map((item) => item.name).join(', ')}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ],
              ),
            ),
            ExpansionTile(
              title: Text(
                'Check ${recipe.ingredients.length} ${recipe.ingredients.length == 1 ? 'ingredient' : 'ingredients'}',
                style: Theme.of(context).textTheme.labelLarge,
              ),
              tilePadding: const EdgeInsets.symmetric(horizontal: 16),
              childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              children: [
                for (final item in recipe.ingredients)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          item.status == 'available'
                              ? Icons.check_circle_outline
                              : item.status == 'check_quantity'
                              ? Icons.help_outline
                              : Icons.shopping_bag_outlined,
                          size: 18,
                          color: item.status == 'available'
                              ? colors.primary
                              : colors.onSurfaceVariant,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                item.name,
                                style: Theme.of(context).textTheme.labelLarge,
                              ),
                              Text(
                                item.measure,
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                              Text(
                                _status(item),
                                style: Theme.of(context).textTheme.bodySmall
                                    ?.copyWith(color: colors.onSurfaceVariant),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
              child: FilledButton.icon(
                onPressed: () => _open(context),
                icon: const Icon(Icons.open_in_new, size: 17),
                label: Text('View recipe · ${recipe.source}'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _status(RecipeIngredientCheck item) => switch (item.status) {
    'available' => 'In your pantry',
    'insufficient' =>
      item.missingQuantity == null
          ? 'Not enough in pantry'
          : 'Need ${NumberFormat('0.###').format(item.missingQuantity)} ${item.unit} more',
    'missing' => 'Not in your pantry',
    _ => 'Check the amount or unit before cooking',
  };
}
