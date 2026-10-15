import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:provider/provider.dart';

import '../../models/shopping_models.dart';
import '../../models/store_models.dart';
import '../../providers/shopping_provider.dart';
import '../../services/automation_failure_guard.dart';
import '../../services/cart_comparison.dart';
import '../../services/pandamart_adapter.dart';
import '../../services/product_matching_service.dart';
import '../../services/store_selector_config.dart';

class StoreAutomationScreen extends StatefulWidget {
  const StoreAutomationScreen({super.key, required this.items});
  final List<ShoppingListItem> items;

  @override
  State<StoreAutomationScreen> createState() => _StoreAutomationScreenState();
}

class _StoreAutomationScreenState extends State<StoreAutomationScreen> {
  static const _confidenceThreshold = 0.65;
  static const _highValueThreshold = 25000.0;
  final _matcher = ProductMatchingService();
  final _guard = AutomationFailureGuard();
  final _random = Random();
  final _results = <AutomationItemResult>[];
  final _logs = <String>[];
  final _cart = <CartLine>[];
  final _cartMissing = <String>[];
  InAppWebViewController? _controller;
  PandaMartAdapter? _adapter;
  bool _loadingConfig = true;
  bool _running = false;
  bool _reviewing = false;
  bool _manual = false;
  bool _cancelled = false;
  int _current = 0;
  String _status = 'Opening PandaMart…';

  double get _total =>
      _cart.fold(0, (total, line) => total + (line.price * line.quantity));

  @override
  void initState() {
    super.initState();
    _loadAdapter();
  }

  Future<void> _loadAdapter() async {
    try {
      final config = await StoreSelectorConfig.load('pandamart');
      if (!mounted) return;
      setState(() {
        _adapter = PandaMartAdapter(config);
        _loadingConfig = false;
        _status = 'Log in to PandaMart, then tap Start adding';
      });
    } catch (error) {
      _log('config', 'Could not load selectors: $error');
      if (mounted) {
        _continueManually('Store configuration could not be loaded.');
      }
    }
  }

  void _log(String step, String message) {
    final line = '${DateTime.now().toIso8601String()} [$step] $message';
    _logs.add(line);
    debugPrint(line);
  }

  Future<void> _start() async {
    final adapter = _adapter;
    final controller = _controller;
    if (adapter == null || controller == null || _running) return;
    if (widget.items.length > 30) {
      _continueManually('Automation is capped at 30 items.');
      return;
    }
    if (!adapter.isAutomationConfigured) {
      _continueManually(
        'PandaMart selectors need live DOM snippets before automation can run safely.',
      );
      return;
    }
    if (!await adapter.isLoggedIn(controller)) {
      setState(
        () => _status = 'Please finish logging in, then tap Start adding',
      );
      return;
    }
    setState(() {
      _running = true;
      _manual = false;
      _cancelled = false;
      _results.clear();
      _cart.clear();
    });
    try {
      await _run(adapter, controller).timeout(
        const Duration(minutes: 5),
        onTimeout: () {
          _cancelled = true;
          throw TimeoutException('The five-minute run limit was reached.');
        },
      );
    } on TimeoutException catch (error) {
      _continueManually(error.message ?? 'Automation timed out.');
    } catch (error) {
      _log('run', 'Stopped: $error');
      _continueManually('The store page changed unexpectedly.');
    }
  }

  Future<void> _run(
    PandaMartAdapter adapter,
    InAppWebViewController controller,
  ) async {
    for (var index = 0; index < widget.items.length; index++) {
      if (_cancelled) return;
      final item = widget.items[index];
      if (await adapter.hasInterruption(controller)) {
        _continueManually('Captcha or OTP requires your attention.');
        return;
      }
      setState(() {
        _current = index + 1;
        _status = 'Adding $_current of ${widget.items.length} items…';
      });
      try {
        await _processItem(
          adapter,
          controller,
          item,
        ).timeout(const Duration(seconds: 30));
      } on TimeoutException {
        _recordFailure(item, 'Item exceeded the 30-second limit');
      } catch (error) {
        _recordFailure(item, 'Unexpected page or selector failure: $error');
      }
      if (_guard.consecutiveFailures >= 3) {
        _continueManually('Three consecutive selector failures occurred.');
        return;
      }
      await Future<void>.delayed(
        Duration(milliseconds: 450 + _random.nextInt(451)),
      );
    }
    _cart
      ..clear()
      ..addAll(await adapter.readCart(controller));
    final comparison = compareCart(_results, _cart);
    _cartMissing
      ..clear()
      ..addAll(comparison.missing);
    for (final missing in comparison.missing) {
      _log('verify', '$missing was not found in the cart');
    }
    if (!mounted) return;
    setState(() {
      _running = false;
      _reviewing = true;
      _status = 'Review your PandaMart cart';
    });
  }

  Future<void> _processItem(
    PandaMartAdapter adapter,
    InAppWebViewController controller,
    ShoppingListItem item,
  ) async {
    _log(item.name, 'Searching for ${item.quantity} ${item.unit}');
    final candidates = await adapter.search(controller, item.name);
    if (candidates.isEmpty) {
      _recordFailure(
        item,
        'No in-stock search results found',
        AddStatus.notFound,
      );
      return;
    }
    final match = await _matcher.match(item, candidates);
    if (match.chosenIndex == null || match.unitsToBuy == null) {
      _results.add(
        AutomationItemResult(
          wantedName: item.name,
          wantedQuantity: item.quantity,
          wantedUnit: item.unit,
          status: AddStatus.notFound,
          reason: match.reason,
        ),
      );
      _guard.record(selectorSucceeded: true);
      _log(item.name, 'No match: ${match.reason}');
      return;
    }
    final candidate = candidates[match.chosenIndex!];
    if (match.confidence < _confidenceThreshold) {
      _results.add(
        AutomationItemResult(
          wantedName: item.name,
          wantedQuantity: item.quantity,
          wantedUnit: item.unit,
          status: AddStatus.lowConfidence,
          reason: 'Low confidence: ${match.reason}',
          productName: candidate.name,
        ),
      );
      _guard.record(selectorSucceeded: true);
      _log(item.name, 'Skipped low-confidence match ${candidate.name}');
      return;
    }
    final quantity = match.unitsToBuy!.clamp(1, 10);
    final added = await adapter.addToCart(controller, candidate, quantity);
    _guard.record(selectorSucceeded: added.status != AddStatus.failed);
    _results.add(
      AutomationItemResult(
        wantedName: item.name,
        wantedQuantity: item.quantity,
        wantedUnit: item.unit,
        status: added.status,
        reason: added.message,
        productName: candidate.name,
        unitsAdded: added.added ? quantity : null,
        unitPrice: candidate.price,
      ),
    );
    _log(item.name, '${candidate.name} x$quantity: ${added.message}');
  }

  void _recordFailure(
    ShoppingListItem item,
    String reason, [
    AddStatus status = AddStatus.failed,
  ]) {
    _results.add(
      AutomationItemResult(
        wantedName: item.name,
        wantedQuantity: item.quantity,
        wantedUnit: item.unit,
        status: status,
        reason: reason,
      ),
    );
    _guard.record(selectorSucceeded: status != AddStatus.failed);
    _log(item.name, reason);
  }

  void _continueManually(String reason) {
    _cancelled = true;
    _log('manual', reason);
    if (!mounted) return;
    setState(() {
      _running = false;
      _reviewing = false;
      _manual = true;
      _loadingConfig = false;
      _status = '$reason Continue manually.';
    });
  }

  Future<void> _purchase() async {
    if (_total >= _highValueThreshold) {
      final approved = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Confirm high-value order'),
          content: Text(
            'The cart total is approximately Rs ${_total.toStringAsFixed(0)}.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Continue'),
            ),
          ],
        ),
      );
      if (approved != true) return;
    }
    final adapter = _adapter;
    final controller = _controller;
    if (adapter == null || controller == null) return;
    setState(() => _status = 'Opening checkout…');
    final result = await adapter.placeOrder(controller);
    _log('checkout', result.message);
    if (result.state == CheckoutState.placed) {
      await _recordOrder();
    } else {
      _continueManually(result.message);
    }
  }

  Future<void> _recordOrder({bool manualAll = false}) async {
    final purchasedNames = manualAll
        ? widget.items.map((item) => item.name.toLowerCase()).toSet()
        : _results
              .where((result) => result.status == AddStatus.added)
              .map((result) => result.wantedName.toLowerCase())
              .toSet();
    final purchasedIds = widget.items
        .where((item) => purchasedNames.contains(item.name.toLowerCase()))
        .map((item) => item.id)
        .toSet();
    final order = await context.read<ShoppingProvider>().recordStoreOrder(
      storeName: 'PandaMart',
      total: _total,
      purchasedItemIds: purchasedIds,
    );
    if (!mounted || order == null) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Order recorded as pending delivery. Pantry was not changed.',
        ),
      ),
    );
    Navigator.pop(context);
  }

  Future<void> _exportLog() async {
    await Clipboard.setData(ClipboardData(text: _logs.join('\n')));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Debug log copied to clipboard')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('PandaMart'),
        actions: [
          IconButton(
            onPressed: _exportLog,
            tooltip: 'Export debug log',
            icon: const Icon(Icons.bug_report_outlined),
          ),
        ],
      ),
      body: Column(
        children: [
          Material(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Row(
                children: [
                  if (_running || _loadingConfig) ...[
                    const SizedBox.square(
                      dimension: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    const SizedBox(width: 10),
                  ],
                  Expanded(child: Text(_status, maxLines: 2)),
                ],
              ),
            ),
          ),
          Expanded(
            child: Stack(
              children: [
                if (_adapter != null)
                  InAppWebView(
                    initialUrlRequest: URLRequest(
                      url: WebUri(_adapter!.homeUrl.toString()),
                    ),
                    initialSettings: InAppWebViewSettings(
                      javaScriptEnabled: true,
                      thirdPartyCookiesEnabled: true,
                      sharedCookiesEnabled: true,
                    ),
                    onWebViewCreated: (controller) =>
                        setState(() => _controller = controller),
                    onLoadStop: (_, _) {
                      if (!_running && !_reviewing && !_manual && mounted) {
                        setState(
                          () => _status =
                              'Log in if needed, then tap Start adding',
                        );
                      }
                    },
                  ),
                if (_reviewing) Positioned.fill(child: _buildReview()),
              ],
            ),
          ),
          if (!_running && !_reviewing)
            SafeArea(
              minimum: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'Experimental: this integration controls the store website on your behalf. It never reads passwords, OTPs, or payment details.',
                    style: TextStyle(fontSize: 12),
                  ),
                  const SizedBox(height: 8),
                  if (!_manual)
                    FilledButton(
                      onPressed: _controller == null ? null : _start,
                      child: const Text('Start adding'),
                    ),
                  if (_manual && widget.items.isNotEmpty)
                    OutlinedButton(
                      onPressed: () => _recordOrder(manualAll: true),
                      child: const Text('I completed the purchase'),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildReview() {
    return ColoredBox(
      color: Theme.of(context).scaffoldBackgroundColor,
      child: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                const Text(
                  'Review cart',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),
                for (final result in _results)
                  ListTile(
                    leading: Icon(
                      result.status == AddStatus.added
                          ? Icons.check_circle
                          : Icons.warning_amber,
                    ),
                    title: Text(result.productName ?? result.wantedName),
                    subtitle: Text(
                      result.status == AddStatus.added
                          ? '${result.unitsAdded} × Rs ${result.unitPrice?.toStringAsFixed(0)}'
                          : '${result.reason} — keep this item on your shopping list',
                    ),
                  ),
                if (_cartMissing.isNotEmpty) ...[
                  const Divider(),
                  Text(
                    'Not verified in cart: ${_cartMissing.join(', ')}',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ],
                const Divider(),
                Text(
                  'Cart total: Rs ${_total.toStringAsFixed(0)}',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
          SafeArea(
            minimum: const EdgeInsets.all(16),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => setState(() {
                      _reviewing = false;
                      _manual = true;
                      _status = 'Edit the cart manually';
                    }),
                    child: const Text('Edit manually'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: _purchase,
                    child: const Text('Purchase'),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
