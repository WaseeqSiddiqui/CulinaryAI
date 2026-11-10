import 'package:flutter/material.dart';

import '../../widgets/app_ui.dart';
import '../chat/chatbot_screen.dart';
import '../household/household_screen.dart';
import '../pantry/expiry_overview_screen.dart';
import '../pantry/pantry_screen.dart';
import '../profile/profile_screen.dart';
import '../recipes/recipe_hub_screen.dart';
import '../scanner/fridge_scanner_screen.dart';
import '../scanner/meal_scanner_screen.dart';
import '../scanner/receipt_scanner_screen.dart';
import '../shopping/order_history_screen.dart';
import '../shopping/shopping_list_screen.dart';

Future<void> showAddFoodOptions(BuildContext context) async {
  final choice = await showModalBottomSheet<String>(
    context: context,
    useSafeArea: true,
    isScrollControlled: true,
    builder: (sheet) => SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            title: Text(
              'Add food to your pantry',
              style: Theme.of(context).textTheme.titleLarge,
            ),
          ),
          for (final item in <(String, String, String, IconData)>[
            (
              'manual',
              'Enter an ingredient',
              'Add its name, quantity and expiry date',
              Icons.edit_outlined,
            ),
            (
              'receipt',
              'Scan a receipt',
              'Review your groceries before saving',
              Icons.receipt_long_outlined,
            ),
            (
              'fridge',
              'Scan your fridge',
              'Identify food from a photo',
              Icons.kitchen_outlined,
            ),
          ])
            ListTile(
              leading: Icon(item.$4),
              title: Text(item.$2),
              subtitle: Text(item.$3),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.pop(sheet, item.$1),
            ),
        ],
      ),
    ),
  );
  if (!context.mounted || choice == null) return;
  if (choice == 'manual') {
    await PantryScreen.showItemEditor(context);
  } else {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => choice == 'receipt'
            ? const ReceiptScannerScreen()
            : const FridgeScannerScreen(),
      ),
    );
  }
}

class KitchenTask {
  const KitchenTask({
    required this.title,
    required this.description,
    required this.icon,
    required this.onTap,
  });
  final String title;
  final String description;
  final IconData icon;
  final VoidCallback onTap;
}

/// Each row grows with text rather than clipping labels at larger text sizes.
class KitchenTaskGrid extends StatelessWidget {
  const KitchenTaskGrid({super.key, required this.tasks});
  final List<KitchenTask> tasks;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      final columns = box.maxWidth >= 700
          ? 3
          : box.maxWidth < 300 &&
                MediaQuery.textScalerOf(context).scale(14) > 17
          ? 1
          : 2;
      return Column(
        children: [
          for (var start = 0; start < tasks.length; start += columns) ...[
            if (start > 0) const SizedBox(height: 10),
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var index = start; index < start + columns; index++) ...[
                    if (index > start) const SizedBox(width: 10),
                    Expanded(
                      child: index >= tasks.length
                          ? const SizedBox.shrink()
                          : _TaskCard(task: tasks[index]),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ],
      );
    },
  );
}

class _TaskCard extends StatelessWidget {
  const _TaskCard({required this.task});
  final KitchenTask task;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Material(
      color: colors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: colors.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: task.onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(task.icon, color: colors.primary, size: 24),
              const SizedBox(height: 10),
              Text(
                task.title,
                style: Theme.of(context).textTheme.titleSmall
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 4),
              Text(
                task.description,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class KitchenFeaturesScreen extends StatefulWidget {
  const KitchenFeaturesScreen({super.key});

  @override
  State<KitchenFeaturesScreen> createState() => _KitchenFeaturesScreenState();
}

class _KitchenFeaturesScreenState extends State<KitchenFeaturesScreen> {
  String _query = '';
  void _open(Widget screen) =>
      Navigator.of(context)
          .push<void>(MaterialPageRoute(builder: (_) => screen));

  @override
  Widget build(BuildContext context) {
    final groups = <(String, List<KitchenTask>)>[
      (
        'Food and expiry',
        [
          KitchenTask(
            title: 'Add food',
            description: 'Type an ingredient or scan groceries',
            icon: Icons.add_circle_outline,
            onTap: () => showAddFoodOptions(context),
          ),
          KitchenTask(
            title: 'My pantry',
            description: 'View food, quantities and storage zones',
            icon: Icons.kitchen_outlined,
            onTap: () => _open(const PantryScreen()),
          ),
          KitchenTask(
            title: 'Check expiry',
            description: 'See dates, use soon items and scan labels',
            icon: Icons.event_outlined,
            onTap: () => _open(const ExpiryOverviewScreen()),
          ),
          KitchenTask(
            title: 'Scan receipt',
            description: 'Add groceries from a receipt photo',
            icon: Icons.receipt_long_outlined,
            onTap: () => _open(const ReceiptScannerScreen()),
          ),
          KitchenTask(
            title: 'Scan fridge',
            description: 'Identify food from a fridge photo',
            icon: Icons.document_scanner_outlined,
            onTap: () => _open(const FridgeScannerScreen()),
          ),
        ],
      ),
      (
        'Cooking and nutrition',
        [
          KitchenTask(
            title: 'Find recipes',
            description: 'Cook with ingredients you already have',
            icon: Icons.restaurant_menu,
            onTap: () => _open(const RecipeHubScreen()),
          ),
          KitchenTask(
            title: 'Create a recipe',
            description: 'Get a recipe for your own idea',
            icon: Icons.auto_awesome_outlined,
            onTap: () =>
                _open(const RecipeHubScreen(section: RecipeSection.create)),
          ),
          KitchenTask(
            title: 'Meal plan',
            description: 'Plan meals for the next seven days',
            icon: Icons.calendar_month_outlined,
            onTap: () =>
                _open(const RecipeHubScreen(section: RecipeSection.weekly)),
          ),
          KitchenTask(
            title: 'Nutrition goals',
            description: 'Track calories and daily targets',
            icon: Icons.monitor_heart_outlined,
            onTap: () =>
                _open(const RecipeHubScreen(section: RecipeSection.macros)),
          ),
          KitchenTask(
            title: 'Scan a meal',
            description: 'Estimate nutrition from a plate photo',
            icon: Icons.add_a_photo_outlined,
            onTap: () => _open(const MealScannerScreen()),
          ),
          KitchenTask(
            title: 'Saved recipes',
            description: 'Open recipes in your cookbook',
            icon: Icons.bookmark_outline,
            onTap: () =>
                _open(const RecipeHubScreen(section: RecipeSection.saved)),
          ),
          KitchenTask(
            title: 'Cooking preferences',
            description: 'Set portions, dietary needs and allergens',
            icon: Icons.tune,
            onTap: () => _open(const CookingPreferencesScreen()),
          ),
          KitchenTask(
            title: 'Ask Chef',
            description: 'Ask a cooking question in Chef Chat',
            icon: Icons.chat_bubble_outline,
            onTap: () => _open(const ChatbotScreen()),
          ),
        ],
      ),
      (
        'Shopping and account',
        [
          KitchenTask(
            title: 'Shopping list',
            description: 'Add groceries and restock low items',
            icon: Icons.shopping_bag_outlined,
            onTap: () => _open(const ShoppingListScreen()),
          ),
          KitchenTask(
            title: 'Order history',
            description: 'Review recorded orders and their status',
            icon: Icons.history,
            onTap: () => _open(const OrderHistoryScreen()),
          ),
          KitchenTask(
            title: 'Household',
            description: 'Invite people and share your pantry',
            icon: Icons.groups_outlined,
            onTap: () => _open(const HouseholdScreen()),
          ),
          KitchenTask(
            title: 'Profile',
            description: 'Edit your name and personal details',
            icon: Icons.person_outline,
            onTap: () => _open(const ProfileScreen()),
          ),
        ],
      ),
    ];
    var count = 0;
    final visibleGroups = [
      for (final group in groups)
        (
          group.$1,
          group.$2
              .where(
                (task) => '${task.title} ${task.description}'
                    .toLowerCase()
                    .contains(_query.trim().toLowerCase()),
              )
              .toList(),
        ),
    ];
    for (final group in visibleGroups) {
      count += group.$2.length;
    }
    return Scaffold(
      appBar: AppBar(title: const Text('All features')),
      body: AppPageBody(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 32),
          children: [
            const Text('Find a tool and see what it does.'),
            const SizedBox(height: 16),
            TextField(
              onChanged: (value) => setState(() => _query = value),
              decoration: const InputDecoration(
                labelText: 'Search features',
                hintText: 'Try expiry, receipt or meal plan',
                prefixIcon: Icon(Icons.search),
              ),
            ),
            if (count == 0)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Text(
                  'No matching feature. Try expiry, recipes or shopping.',
                ),
              ),
            for (final group in visibleGroups)
              if (group.$2.isNotEmpty) ...[
                const SizedBox(height: 24),
                Text(group.$1, style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                SurfacePanel(
                  padding: EdgeInsets.zero,
                  child: Column(
                    children: [
                      for (var i = 0; i < group.$2.length; i++) ...[
                        if (i > 0) const Divider(height: 1),
                        ListTile(
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 6,
                          ),
                          leading: Icon(group.$2[i].icon),
                          title: Text(group.$2[i].title),
                          subtitle: Text(group.$2[i].description),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: group.$2[i].onTap,
                        ),
                      ],
                    ],
                  ),
                ),
              ],
          ],
        ),
      ),
    );
  }
}
