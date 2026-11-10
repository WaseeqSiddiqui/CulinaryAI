import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../models/pantry_item_model.dart';
import '../../providers/pantry_provider.dart';
import '../../widgets/app_ui.dart';
import 'pantry_screen.dart';

enum _ExpiryView { all, useSoon, expired, missing }

class ExpiryOverviewScreen extends StatefulWidget {
  const ExpiryOverviewScreen({super.key});

  @override
  State<ExpiryOverviewScreen> createState() => _ExpiryOverviewScreenState();
}

class _ExpiryOverviewScreenState extends State<ExpiryOverviewScreen> {
  _ExpiryView _view = _ExpiryView.all;

  @override
  Widget build(BuildContext context) {
    final pantry = context.watch<PantryProvider>();
    final items =
        pantry.allItems
            .where(
              (item) => switch (_view) {
                _ExpiryView.all => true,
                _ExpiryView.useSoon =>
                  item.expiryStatus == ExpiryStatus.useSoon,
                _ExpiryView.expired =>
                  item.expiryStatus == ExpiryStatus.expired,
                _ExpiryView.missing => item.expiryDate == null,
              },
            )
            .toList()
          ..sort(
            (a, b) => (a.daysUntilExpiry ?? 100000).compareTo(
              b.daysUntilExpiry ?? 100000,
            ),
          );
    return Scaffold(
      appBar: AppBar(title: const Text('Check expiry')),
      body: AppPageBody(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 32),
          children: [
            Text(
              'Know what to use next',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            const Text(
              'Select an ingredient to change its expiry date or scan the date printed on its label.',
            ),
            const SizedBox(height: 20),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final entry in <(_ExpiryView, String)>[
                  (_ExpiryView.all, 'All dates'),
                  (_ExpiryView.useSoon, 'Use soon (${pantry.useSoonCount})'),
                  (_ExpiryView.expired, 'Expired (${pantry.expiredCount})'),
                  (_ExpiryView.missing, 'No date'),
                ])
                  ChoiceChip(
                    label: Text(entry.$2),
                    selected: _view == entry.$1,
                    onSelected: (_) => setState(() => _view = entry.$1),
                  ),
              ],
            ),
            const SizedBox(height: 20),
            if (pantry.isLoading)
              const Center(child: CircularProgressIndicator())
            else if (items.isEmpty)
              KitchenEmptyState(
                icon: Icons.event_available_outlined,
                title: pantry.allItems.isEmpty
                    ? 'Add your first ingredient'
                    : 'No ingredients in this group',
                message: pantry.allItems.isEmpty
                    ? 'Add food to your pantry to keep track of its expiry date.'
                    : 'Choose another date filter to see the rest of your pantry.',
                action: pantry.allItems.isEmpty
                    ? FilledButton.icon(
                        onPressed: () => PantryScreen.showItemEditor(context),
                        icon: const Icon(Icons.add),
                        label: const Text('Add food'),
                      )
                    : null,
              )
            else
              SurfacePanel(
                padding: EdgeInsets.zero,
                child: Column(
                  children: [
                    for (var i = 0; i < items.length; i++) ...[
                      if (i > 0) const Divider(height: 1),
                      _ExpiryItem(item: items[i]),
                    ],
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _ExpiryItem extends StatelessWidget {
  const _ExpiryItem({required this.item});
  final PantryItemModel item;

  @override
  Widget build(BuildContext context) {
    final date = item.expiryDate;
    final status = switch (item.expiryStatus) {
      ExpiryStatus.expired => 'Expired',
      ExpiryStatus.useSoon => 'Use soon',
      ExpiryStatus.fresh => 'Fresh',
      ExpiryStatus.unknown => 'No expiry date',
    };
    return ListTile(
      key: ValueKey('expiry-item-${item.id}'),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      leading: Icon(
        item.expiryStatus == ExpiryStatus.expired
            ? Icons.error_outline
            : Icons.event_outlined,
        color: item.expiryStatus == ExpiryStatus.expired
            ? Theme.of(context).colorScheme.error
            : Theme.of(context).colorScheme.primary,
      ),
      title: Text(item.name),
      subtitle: Text(
        [
          status,
          if (date != null) DateFormat('d MMM yyyy').format(date),
          if (item.hasEstimatedExpiry) 'Estimated',
          '${item.quantity} ${item.unit} · ${item.location}',
        ].join('\n'),
      ),
      trailing: const Icon(Icons.chevron_right),
      onTap: () =>
          PantryScreen.showItemEditor(context, item: item, focusExpiry: true),
    );
  }
}
