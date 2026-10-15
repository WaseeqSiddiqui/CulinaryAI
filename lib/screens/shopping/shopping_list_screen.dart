import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/shopping_provider.dart';
import 'store_automation_screen.dart';

class ShoppingListScreen extends StatelessWidget {
  const ShoppingListScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final shopping = context.watch<ShoppingProvider>();
    return Scaffold(
      appBar: AppBar(title: const Text('Shopping list')),
      body: shopping.isLoading
          ? const Center(child: CircularProgressIndicator())
          : shopping.items.isEmpty
          ? const Center(child: Text('Everything is stocked'))
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
