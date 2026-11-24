import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../services/subscription_api_service.dart';
import '../../services/play_billing_service.dart';
import '../../widgets/app_ui.dart';

class PlusScreen extends StatefulWidget {
  const PlusScreen({super.key, this.service, this.billing});
  final SubscriptionApiService? service;
  final PlayBillingController? billing;
  @override
  State<PlusScreen> createState() => _PlusScreenState();
}

class _PlusScreenState extends State<PlusScreen> {
  late final _service = widget.service ?? SubscriptionApiService();
  SubscriptionStatus? _status;
  bool _loading = true;
  bool _failed = false;
  late final PlayBillingController _billing;
  late final bool _ownsBilling;

  @override
  void initState() {
    super.initState();
    final shared = context.read<PlayBillingController?>();
    _billing = widget.billing ?? shared ?? PlayBillingController();
    _ownsBilling = widget.billing == null && shared == null;
    _billing.addListener(_billingChanged);
    _billing.load();
    _load();
  }

  void _billingChanged() {
    if (!mounted) return;
    setState(() {
      if (_billing.verifiedStatus != null) _status = _billing.verifiedStatus;
    });
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
    _billing.removeListener(_billingChanged);
    if (_ownsBilling) _billing.dispose();
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
          _PlanCard(
            name: 'CulinaryAI Plus',
            price: _billing.product == null
                ? 'Price available on Google Play'
                : '${_billing.product!.price} / month',
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
          FilledButton(
            onPressed:
                _billing.canBuy && _status != null && _status!.plan != 'plus'
                ? _billing.purchase
                : null,
            child: Text(
              _billing.busy
                  ? 'Checking payment...'
                  : _status?.plan == 'plus'
                  ? 'Plus is active'
                  : 'Subscribe with Google Play',
            ),
          ),
          const SizedBox(height: 8),
          if (_billing.message != null)
            Text(_billing.message!, textAlign: TextAlign.center),
          TextButton(
            onPressed: _billing.canRestore ? _billing.restore : null,
            child: const Text('Restore purchases'),
          ),
          if (_billing.canRetry)
            TextButton(
              onPressed: _billing.retryVerification,
              child: const Text('Retry payment verification'),
            ),
          if (_status?.plan == 'plus')
            TextButton(
              onPressed: () async {
                final opened = await launchUrl(
                  Uri.https('play.google.com', '/store/account/subscriptions', {
                    'sku': plusProductId,
                    'package': 'com.enterprise.culinaryAI',
                  }),
                  mode: LaunchMode.externalApplication,
                );
                if (!opened && context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text(
                        'Open Google Play → Payments & subscriptions to manage Plus.',
                      ),
                    ),
                  );
                }
              },
              child: const Text('Manage Google Play subscription'),
            ),
          Text(
            'Monthly subscription. Google Play shows the final local price before you confirm. '
            'Renews automatically until canceled in Google Play. Cancellation stops the next renewal; '
            'access continues until the paid period ends. Monthly AI allowances reset on the 1st (UTC); unused allowance does not roll over.',
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
