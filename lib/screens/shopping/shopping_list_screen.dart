import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../providers/shopping_provider.dart';
import '../../widgets/app_ui.dart';
import 'store_automation_screen.dart';
import 'order_history_screen.dart';
import '../../services/purchase_session_store.dart';

class ShoppingListScreen extends StatelessWidget {
  const ShoppingListScreen({super.key});

  static const _units = ['pcs', 'g', 'kg', 'ml', 'L', 'dozen'];

  Future<void> _showAddItemDialog(BuildContext context) async {
    final formKey = GlobalKey<FormState>();
    final nameController = TextEditingController();
    final quantityController = TextEditingController(text: '1');
    var unit = _units.first;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Add shopping item'),
          content: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: nameController,
                  autofocus: true,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(
                    labelText: 'Item name',
                    hintText: 'e.g. Milk',
                  ),
                  validator: (value) => value == null || value.trim().isEmpty
                      ? 'Enter an item name'
                      : null,
                ),
                const SizedBox(height: 12),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: quantityController,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: const InputDecoration(
                          labelText: 'Quantity',
                        ),
                        validator: (value) {
                          final quantity = double.tryParse(value?.trim() ?? '');
                          return quantity == null ||
                                  !quantity.isFinite ||
                                  quantity <= 0
                              ? 'Enter a valid quantity'
                              : null;
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        initialValue: unit,
                        decoration: const InputDecoration(labelText: 'Unit'),
                        items: _units
                            .map(
                              (value) => DropdownMenuItem(
                                value: value,
                                child: Text(value),
                              ),
                            )
                            .toList(),
                        onChanged: (value) {
                          if (value != null) {
                            setDialogState(() => unit = value);
                          }
                        },
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () async {
                if (!(formKey.currentState?.validate() ?? false)) return;
                await dialogContext.read<ShoppingProvider>().addManualItem(
                  name: nameController.text,
                  quantity: double.parse(quantityController.text.trim()),
                  unit: unit,
                );
                if (dialogContext.mounted) Navigator.pop(dialogContext);
              },
              child: const Text('Add'),
            ),
          ],
        ),
      ),
    );
    nameController.dispose();
    quantityController.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final shopping = context.watch<ShoppingProvider>();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Shopping list'),
        actions: [
          IconButton(
            tooltip: 'Order history',
            icon: const Icon(Icons.history),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const OrderHistoryScreen()),
            ),
          ),
        ],
      ),

      body: shopping.isLoading
          ? const Center(child: CircularProgressIndicator())
          : shopping.items.isEmpty
          ? KitchenEmptyState(
              icon: Icons.shopping_basket_outlined,
              title: 'All stocked up.',
              message: 'Your low-stock ingredients will land here. You can add something for your next good meal, too.',
              action: OutlinedButton.icon(
                onPressed: () => _showAddItemDialog(context),
                icon: const Icon(Icons.add_rounded),
                label: const Text('Add an item'),
              ),
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(24, 12, 24, 32),
              children: [
                PageIntro(
                  eyebrow: '${shopping.items.length} ITEMS ON YOUR LIST',
                  title: 'A fresh little restock.',
                  subtitle: 'The essentials for whatever comes next.',
                ),
                const SizedBox(height: 24),
                SurfacePanel(
                  padding: EdgeInsets.zero,
                  child: Column(
                    children: [
                      for (
                        var index = 0;
                        index < shopping.items.length;
                        index++
                      ) ...[
                        if (index > 0)
                          const Padding(
                            padding: EdgeInsets.only(left: 20, right: 20),
                            child: Divider(),
                          ),
                        ListTile(
                          contentPadding: const EdgeInsets.fromLTRB(
                            18,
                            12,
                            8,
                            12,
                          ),
                          leading: Container(
                            width: 42,
                            height: 42,
                            decoration: BoxDecoration(
                              color: Theme.of(context)
                                  .colorScheme
                                  .primaryContainer,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Icon(
                              Icons.eco_outlined,
                              color: Theme.of(context).colorScheme.primary,
                              size: 21,
                            ),
                          ),
                          title: Text(shopping.items[index].name),
                          subtitle: Text(
                            '${NumberFormat('0.###').format(shopping.items[index].quantity)} ${shopping.items[index].unit}',
                          ),
                          trailing: IconButton(
                            tooltip: 'Remove ${shopping.items[index].name}',
                            icon: const Icon(Icons.close_rounded, size: 19),
                            onPressed: () =>
                                shopping.remove(shopping.items[index].id),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                TextButton.icon(
                  onPressed: () => _showAddItemDialog(context),
                  icon: const Icon(Icons.add_rounded, size: 19),
                  label: const Text('Add an item'),
                ),
                const SizedBox(height: 22),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.info_outline_rounded,
                      size: 17,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Low-stock ingredients are added automatically. Review products and the final total before placing your order.',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                  ],
                ),
              ],
            ),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.fromLTRB(24, 12, 24, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            FutureBuilder<PurchaseSession?>(
              future: shopping.householdId == null
                  ? Future.value(null)
                  : PurchaseSessionStore().load(shopping.householdId!),
              builder: (context, snapshot) {
                final recovering = snapshot.hasData || snapshot.hasError;
                return FilledButton.icon(
                  onPressed:
                      shopping.isLoading ||
                          snapshot.connectionState != ConnectionState.done ||
                          (shopping.items.isEmpty && !recovering)
                      ? null
                      : () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => StoreAutomationScreen(
                              items: List.of(shopping.items),
                            ),
                          ),
                        ),
                  icon: const Icon(Icons.shopping_cart_checkout),
                  label: Text(
                    recovering
                        ? 'Resume PandaMart checkout'
                        : 'Buy from PandaMart',
                  ),
                );
              },
            ),
            const SizedBox(height: 8),
            TextButton.icon(
              onPressed: shopping.items.isEmpty
                  ? null
                  : () async {
                      final order = await context
                          .read<ShoppingProvider>()
                          .placePendingOrder();
                      if (context.mounted && order != null) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text(
                              'Pending order created. Pantry stock was not changed.',
                            ),
                          ),
                        );
                      }
                    },
              icon: const Icon(Icons.receipt_long),
              label: const Text('Place order without store'),
            ),
          ],
        ),
      ),
    );
  }
}
