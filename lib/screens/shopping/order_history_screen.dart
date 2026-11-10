import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../models/shopping_models.dart';
import '../../providers/shopping_provider.dart';
import '../../widgets/app_ui.dart';

class OrderHistoryScreen extends StatefulWidget {
  const OrderHistoryScreen({super.key});

  @override
  State<OrderHistoryScreen> createState() => _OrderHistoryScreenState();
}

class _OrderHistoryScreenState extends State<OrderHistoryScreen> {
  Future<List<ShoppingOrder>>? _orders;
  String? _householdId;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final shopping = context.watch<ShoppingProvider>();
    if (_orders == null || _householdId != shopping.householdId) {
      _householdId = shopping.householdId;
      _orders = shopping.loadOrders();
    }
  }

  void _reload() =>
      setState(() => _orders = context.read<ShoppingProvider>().loadOrders());

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Order history'),
      actions: [
        IconButton(
          onPressed: _reload,
          tooltip: 'Refresh orders',
          icon: const Icon(Icons.refresh),
        ),
      ],
    ),

    body: AppPageBody(
      maxWidth: 840,
      child: FutureBuilder<List<ShoppingOrder>>(
        future: _orders,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return KitchenEmptyState(
              icon: Icons.receipt_long_outlined,
              title: 'Your orders are taking a moment.',
              message: 'We could not load the saved orders. Try again when you are ready.',
              action: FilledButton(
                onPressed: _reload,
                child: const Text('Retry loading orders'),
              ),
            );
          }
          final orders = snapshot.data ?? const [];
          if (orders.isEmpty) {
            return const KitchenEmptyState(
              icon: Icons.shopping_bag_outlined,
              title: 'Your orders will appear here.',
              message: 'Orders you record will appear here, with their items, totals and store references.',
            );
          }
          return ListView(
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 36),
            children: [
              PageIntro(
                eyebrow:
                    '${orders.length} RECORDED ${orders.length == 1 ? 'ORDER' : 'ORDERS'}',
                title: 'Your grocery orders.',
                subtitle: 'A record of the groceries and good things you have ordered.',
              ),
              const SizedBox(height: 26),
              for (final order in orders)
                Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: Card(
                    clipBehavior: Clip.antiAlias,
                    child: ExpansionTile(
                      tilePadding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 12,
                      ),
                      childrenPadding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                      shape: const Border(),
                      collapsedShape: const Border(),
                      title: Wrap(
                        spacing: 16,
                        runSpacing: 8,
                        children: [
                          Text(
                            order.storeName ?? 'Shopping order',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          if (order.total != null)
                            Text(
                              'Rs ${order.total!.toStringAsFixed(2)}',
                              style: Theme.of(context).textTheme.titleMedium
                                  ?.copyWith(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .primary,
                                  ),
                            ),
                        ],
                      ),
                      subtitle: Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              DateFormat('d MMM yyyy, h:mm a')
                                  .format(order.createdAt.toLocal()),
                            ),
                            const SizedBox(height: 5),
                            Text(order.status),
                          ],
                        ),
                      ),
                      children: [
                        const Divider(),
                        const SizedBox(height: 12),
                        if (order.storeOrderReference != null)
                          ListTile(
                            contentPadding: EdgeInsets.zero,
                            title: const Text('PandaMart reference'),
                            subtitle: SelectableText(
                              order.storeOrderReference!,
                            ),
                          ),
                        for (final item in order.items)
                          ListTile(
                            contentPadding: EdgeInsets.zero,
                            title: Text(item.name),
                            trailing: Text(
                              '${NumberFormat('0.###').format(item.quantity)} ${item.unit}',
                            ),
                          ),
                        const SizedBox(height: 14),
                        const StatusNotice(
                          message: 'When your groceries arrive, scan the receipt to update your pantry.',
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    ),
  );
}
