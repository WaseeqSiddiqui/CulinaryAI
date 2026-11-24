import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../services/subscription_api_service.dart';
import '../../widgets/app_ui.dart';

class PlusScreen extends StatefulWidget {
  const PlusScreen({super.key, this.service});
  final SubscriptionApiService? service;
  @override
  State<PlusScreen> createState() => _PlusScreenState();
}

class _PlusScreenState extends State<PlusScreen> {
  late final _service = widget.service ?? SubscriptionApiService();
  SubscriptionStatus? _status;
  bool _loading = true;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _failed = false;
    });
    try {
      final status = await _service.status();
      if (mounted) setState(() => _status = status);
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    if (widget.service == null) _service.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('CulinaryAI Plus')),
    body: AppPageBody(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
        children: [
          Icon(
            Icons.auto_awesome,
            color: Theme.of(context).colorScheme.primary,
            size: 36,
          ),
          const SizedBox(height: 16),
          Text(
            'More help in your kitchen',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 8),
          const Text(
            'Compare your monthly allowance and see what Plus includes.',
          ),
          const SizedBox(height: 20),
          if (_loading)
            const Center(child: CircularProgressIndicator())
          else if (_failed)
            SurfacePanel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Usage could not be loaded. Your plan has not changed.',
                  ),
                  TextButton(onPressed: _load, child: const Text('Try again')),
                ],
              ),
            )
          else if (_status == null)
            const SurfacePanel(
              child: Text('Sign in to see your plan and monthly usage.'),
            )
          else
            SurfacePanel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _status!.plan == 'plus'
                        ? 'Your Plus allowance'
                        : 'Your Free allowance',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 16),
                  _UsageRow(
                    label: 'Chef requests',
                    used: _status!.chatUsed,
                    limit: _status!.chatLimit,
                  ),
                  const SizedBox(height: 16),
                  _UsageRow(
                    label: 'Photo scans',
                    used: _status!.photoUsed,
                    limit: _status!.photoLimit,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Resets ${DateFormat('d MMM yyyy').format(_status!.resetsAt.toLocal())}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          const SizedBox(height: 20),
          const _PlanCard(name: 'Free', price: 'PKR 0', chat: 20, photos: 3),
          const SizedBox(height: 14),
          const _PlanCard(
            name: 'CulinaryAI Plus',
            price: 'PKR 999 / month',
            chat: 500,
            photos: 50,
            plus: true,
          ),
          const SizedBox(height: 20),
          const Text(
            'Chef requests include chat, detailed cooking guidance and AI shopping assistance. Photo scans include receipts, fridge checks, meal estimates and cooking photos.',
          ),
          const SizedBox(height: 10),
          const Text(
            'Failed AI requests do not use your allowance. Pantry tracking and manual updates remain available when your AI allowance is used up.',
          ),
          const SizedBox(height: 20),
          const FilledButton(
            onPressed: null,
            child: Text('Payments coming soon'),
          ),
          const SizedBox(height: 8),
          Text(
            'No payment will be collected here yet.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    ),
  );
}

class _UsageRow extends StatelessWidget {
  const _UsageRow({
    required this.label,
    required this.used,
    required this.limit,
  });
  final String label;
  final int used, limit;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text('$label: $used / $limit'),
      const SizedBox(height: 6),
      LinearProgressIndicator(
        value: limit > 0 ? (used / limit).clamp(0.0, 1.0) : 0,
      ),
    ],
  );
}

class _PlanCard extends StatelessWidget {
  const _PlanCard({
    required this.name,
    required this.price,
    required this.chat,
    required this.photos,
    this.plus = false,
  });
  final String name, price;
  final int chat, photos;
  final bool plus;
  @override
  Widget build(BuildContext context) => SurfacePanel(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            if (plus) ...[
              const Icon(Icons.auto_awesome, size: 20),
              const SizedBox(width: 8),
            ],
            Expanded(
              child: Text(name, style: Theme.of(context).textTheme.titleLarge),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(price, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 14),
        Text('$chat Chef requests / month'),
        const SizedBox(height: 6),
        Text('$photos photo scans / month'),
        if (plus) ...[const SizedBox(height: 10), const Text('Coming soon')],
      ],
    ),
  );
}

class PlusPlanBanner extends StatelessWidget {
  const PlusPlanBanner({super.key});
  @override
  Widget build(BuildContext context) => SurfacePanel(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('CulinaryAI Plus', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 4),
        const Text('More Chef requests and photo scans for your kitchen.'),
        TextButton.icon(
          key: const Key('viewPlusPlans'),
          onPressed: () =>
              Navigator.of(context)
                  .push(MaterialPageRoute(builder: (_) => const PlusScreen())),
          icon: const Icon(Icons.auto_awesome, size: 18),
          label: const Text('View Plus'),
        ),
      ],
    ),
  );
}
