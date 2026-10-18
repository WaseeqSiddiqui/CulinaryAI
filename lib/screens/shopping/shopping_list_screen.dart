import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/shopping_provider.dart';
import 'store_automation_screen.dart';

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
      appBar: AppBar(title: const Text('Shopping list')),
      body: shopping.isLoading
          ? const Center(child: CircularProgressIndicator())
          : shopping.items.isEmpty
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'No shopping items yet. Low-stock pantry items appear here automatically, or add one manually.',
                  textAlign: TextAlign.center,
                ),
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 120),
              itemCount: shopping.items.length,
              itemBuilder: (context, index) {
                final item = shopping.items[index];
                return Card(
                  child: ListTile(
                    title: Text(item.name),
                    subtitle: Text('${item.quantity} ${item.unit}'),
                    trailing: IconButton(
                      tooltip: 'Remove',
                      icon: const Icon(Icons.close),
                      onPressed: () => shopping.remove(item.id),
                    ),
                  ),
                );
              },
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showAddItemDialog(context),
        icon: const Icon(Icons.add),
        label: const Text('Add item'),
      ),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            FilledButton.icon(
              onPressed: shopping.items.isEmpty
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
              label: const Text('Buy from PandaMart'),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
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
