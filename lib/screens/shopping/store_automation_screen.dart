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
import '../../services/grocery_query_normalizer.dart';
import '../../services/pandamart_adapter.dart';
import '../../services/product_matching_service.dart';
import '../../services/store_adapter.dart';
import '../../services/store_selector_config.dart';

class StoreAutomationScreen extends StatefulWidget {
  const StoreAutomationScreen({super.key, required this.items});

  final List<ShoppingListItem> items;

  @override
  State<StoreAutomationScreen> createState() => _StoreAutomationScreenState();
}

class _StoreAutomationScreenState extends State<StoreAutomationScreen> {
  static const _locationPermissionChannel = MethodChannel(
    'com.enterprise.culinary_ai/location_permission',
  );
  static const _confidenceThreshold = 0.65;
  static const _highValueThreshold = 25000.0;
  static const _runLimit = Duration(minutes: 5);
  static const _itemLimit = Duration(seconds: 30);

  final _matcher = ProductMatchingService();
  final _guard = AutomationFailureGuard();
  final _random = Random();
  final _results = <AutomationItemResult>[];
  final _logs = <String>[];
  final _baselineCart = <CartLine>[];
  final _cart = <CartLine>[];

  InAppWebViewController? _controller;
  InAppWebViewController? _loginPopupController;
  StoreAdapter? _adapter;
  int? _loginPopupWindowId;
  CartComparison _comparison = const CartComparison(matched: [], missing: []);
  bool _loadingConfig = true;
  bool _pageReady = false;
  bool _running = false;
  bool _reviewing = false;
  bool _manual = false;
  bool _purchasing = false;
  bool _manualCheckoutStarted = false;
  bool _cancelled = false;
  bool _allowSubstitutions = false;
  bool _locating = false;
  bool _locateAfterLoad = false;
  int _current = 0;
  int _runId = 0;
  int _attemptId = 0;
  String _status = 'Opening PandaMart…';

  PandaMartAdapter? get _panda =>
      _adapter is PandaMartAdapter ? _adapter! as PandaMartAdapter : null;

  String get _deliveryAddressPrompt {
    return 'Select your delivery address or use current location';
  }

  double? get _total => _panda?.lastCartTotal;

  bool get _cartVerified =>
      _panda?.lastCartReadWasVerified == true &&
      _comparison.isVerified &&
      _cart.isNotEmpty &&
      _total != null;

  bool get _canPurchase =>
      _reviewing && !_purchasing && _cartVerified && (_total ?? 0) > 0;

  @override
  void initState() {
    super.initState();
    _loadAdapter();
  }

  @override
  void dispose() {
    _cancelled = true;
    _runId++;
    _attemptId++;
    _panda?.cancelPendingActions();
    super.dispose();
  }

  Future<void> _loadAdapter() async {
    try {
      final config = await StoreSelectorConfig.load('pandamart');
      if (!mounted) return;
      setState(() {
        _adapter = PandaMartAdapter(config);
        _loadingConfig = false;
        _status = 'Log in and select your address in PandaMart';
      });
    } catch (error) {
      _log('config', 'Could not load store configuration: $error');
      _continueManually('Store configuration could not be loaded.');
    }
  }

  void _log(String step, String message) {
    final line = '${DateTime.now().toIso8601String()} [$step] $message';
    _logs.add(line);
    debugPrint(line);
  }

  Future<void> _refreshPageState() async {
    final adapter = _panda;
    final controller = _controller;
    if (adapter == null || controller == null || _running || _reviewing) {
      return;
    }
    try {
      final current = await controller.getUrl();
      final uri = current == null ? null : Uri.tryParse(current.toString());
      if (adapter.isExternalLoginUri(uri)) {
        if (mounted) {
          setState(() {
            _pageReady = false;
            _status = 'Complete social sign-in inside CulinaryAI';
          });
        }
        return;
      }
      if (!adapter.isAllowedUri(uri)) {
        if (mounted) {
          setState(() {
            _pageReady = false;
            _status = 'Blocked an unexpected page. Return to PandaMart.';
          });
        }
        return;
      }
      final interruption = await adapter.interruptionReason(controller);
      if (!mounted) return;
      if (interruption != null) {
        setState(() {
          _pageReady = false;
          _status = '$interruption Finish it in the WebView.';
        });
        return;
      }
      final loggedIn = await adapter.isLoggedIn(controller);
      final addressSelected =
          loggedIn && await adapter.hasSelectedAddress(controller);
      final activeStore = await adapter.hasActiveStore(controller);
      if (!mounted) return;
      setState(() {
        _pageReady = loggedIn && addressSelected && activeStore;
        _status = !loggedIn
            ? 'Log in with Google or Facebook inside PandaMart'
            : !addressSelected
            ? _deliveryAddressPrompt
            : !activeStore
            ? 'Choose a nearby PandaMart from the Foodpanda page'
            : 'Ready to add ${widget.items.length} shopping-list items';
      });
    } catch (error) {
      _log('page', 'Page readiness check failed: $error');
    }
  }

  Future<bool> _requestLocationPermission() async {
    try {
      return await _locationPermissionChannel.invokeMethod<bool>(
            'requestLocationPermission',
          ) ==
          true;
    } on MissingPluginException {
      // iOS asks from WKWebView using the Info.plist usage description.
      return true;
    } on PlatformException catch (error) {
      _log('location', 'Permission request failed: ${error.message}');
      return false;
    }
  }

  Future<void> _useCurrentLocation() async {
    final adapter = _panda;
    final controller = _controller;
    if (adapter == null || controller == null || _running || _locating) return;
    setState(() {
      _locating = true;
      _pageReady = false;
      _status = 'Requesting location permission…';
    });
    final granted = await _requestLocationPermission();
    if (!mounted) return;
    if (!granted) {
      setState(() {
        _locating = false;
        _status = 'Location permission denied. Enter an address manually.';
      });
      return;
    }
    _locateAfterLoad = true;
    setState(() => _status = 'Opening nearby-store discovery…');
    await controller.loadUrl(
      urlRequest: URLRequest(url: WebUri(adapter.homeUrl.toString())),
    );
  }

  Future<void> _handleStoreLoadStop() async {
    await _refreshPageState();
    if (!_locateAfterLoad || !mounted || _running) return;
    _locateAfterLoad = false;
    final adapter = _panda;
    final controller = _controller;
    final clicked =
        adapter != null &&
        controller != null &&
        await adapter.clickLocateMe(controller);
    if (!mounted) return;
    setState(() {
      _locating = false;
      _status = clicked
          ? 'Confirm the detected address, then choose a nearby PandaMart'
          : 'Tap Locate me or enter your address, then choose PandaMart';
    });
  }

  Future<GeolocationPermissionShowPromptResponse> _handleGeolocationPrompt(
    String origin,
  ) async {
    final uri = Uri.tryParse(origin);
    final allowedOrigin = _panda?.isAllowedUri(uri) == true;
    final granted = allowedOrigin && await _requestLocationPermission();
    if (!granted && mounted) {
      setState(
        () => _status =
            'Location access was not granted. Enter your address manually.',
      );
    }
    return GeolocationPermissionShowPromptResponse(
      origin: origin,
      allow: granted,
      retain: granted,
    );
  }

  Future<void> _cancelLoginPopup() async {
    final controller = _loginPopupController;
    if (controller != null) {
      try {
        await controller.evaluateJavascript(source: 'window.close();');
      } catch (_) {
        // The provider may already have closed its popup.
      }
    }
    _finishLoginPopup(cancelled: true);
  }

  void _finishLoginPopup({bool cancelled = false}) {
    if (_loginPopupWindowId == null) return;
    if (mounted) {
      setState(() {
        _loginPopupWindowId = null;
        _loginPopupController = null;
        _pageReady = false;
        _status = cancelled
            ? 'Social sign-in cancelled'
            : 'Finishing PandaMart sign-in...';
      });
    }
    if (!cancelled) {
      Future<void>.delayed(const Duration(milliseconds: 700), () {
        if (mounted) _refreshPageState();
      });
      Future<void>.delayed(const Duration(seconds: 2), () {
        if (mounted) _refreshPageState();
      });
    }
  }

  Future<void> _start() async {
    final adapter = _panda;
    final controller = _controller;
    if (adapter == null || controller == null || _running || _purchasing) {
      return;
    }
    if (widget.items.isEmpty) return;
    if (widget.items.length > 30) {
      _continueManually('Automation is capped at 30 items.');
      return;
    }
    if (!adapter.isAutomationConfigured) {
      _continueManually(
        'PandaMart search and add controls are not fully configured.',
      );
      return;
    }
    final interruption = await adapter.interruptionReason(controller);
    if (interruption != null) {
      if (mounted) setState(() => _status = '$interruption Resolve it first.');
      return;
    }
    if (!await adapter.isLoggedIn(controller)) {
      if (mounted) {
        setState(() => _status = 'Please log in, then tap Start adding');
      }
      return;
    }
    if (!await adapter.hasSelectedAddress(controller)) {
      if (mounted) {
        setState(
          () => _status = '$_deliveryAddressPrompt, then tap Start adding',
        );
      }
      return;
    }
    if (!await adapter.hasActiveStore(controller)) {
      if (mounted) {
        setState(
          () => _status =
              'Choose a nearby PandaMart from Foodpanda, then tap Start adding',
        );
      }
      return;
    }

    _cancelled = false;
    _guard.reset();
    final runId = ++_runId;
    _attemptId++;
    adapter.cancelPendingActions();
    _results.clear();
    _baselineCart.clear();
    _cart.clear();
    _comparison = const CartComparison(matched: [], missing: []);
    if (mounted) {
      setState(() {
        _running = true;
        _reviewing = false;
        _manual = false;
        _manualCheckoutStarted = false;
        _current = 0;
      });
    }

    if (adapter.isCartVerificationConfigured) {
      try {
        _baselineCart.addAll(await adapter.readCart(controller));
        _log('cart', 'Captured ${_baselineCart.length} pre-existing lines');
      } catch (error) {
        _log('cart', 'Could not capture the starting cart: $error');
      }
    }

    final timeout = Completer<_RunOutcome>();
    final timer = Timer(_runLimit, () {
      if (!_isRunActive(runId)) return;
      _cancelled = true;
      _attemptId++;
      adapter.cancelPendingActions();
      timeout.complete(const _RunOutcome.timedOut());
    });
    final work = _run(adapter, controller, runId).then(
      (_) => const _RunOutcome.completed(),
      onError: (Object error, StackTrace stack) =>
          _RunOutcome.failed(error, stack),
    );
    final outcome = await Future.any([work, timeout.future]);
    timer.cancel();
    if (!mounted || runId != _runId) return;
    if (outcome.timedOut) {
      _continueManually('The five-minute automation limit was reached.');
    } else if (outcome.error != null) {
      _log('run', 'Stopped: ${outcome.error}');
      _continueManually('PandaMart changed unexpectedly.');
    }
  }

  Future<void> _run(
    PandaMartAdapter adapter,
    InAppWebViewController controller,
    int runId,
  ) async {
    for (var index = 0; index < widget.items.length; index++) {
      if (!_isRunActive(runId)) return;
      final interruption = await adapter.interruptionReason(controller);
      if (interruption != null) {
        _continueManually(interruption);
        return;
      }

      final item = widget.items[index];
      if (mounted) {
        setState(() {
          _current = index + 1;
          _status = 'Adding $_current of ${widget.items.length} items…';
        });
      }
      await _processItemWithTimeout(adapter, controller, item, runId);
      if (!_isRunActive(runId)) return;
      if (_guard.consecutiveFailures >= 3) {
        adapter.cancelPendingActions();
        _continueManually('Three consecutive store-control failures occurred.');
        return;
      }
      await Future<void>.delayed(
        Duration(milliseconds: 500 + _random.nextInt(501)),
      );
    }
    if (!_isRunActive(runId)) return;
    await _openReview(adapter, controller);
  }

  Future<void> _processItemWithTimeout(
    PandaMartAdapter adapter,
    InAppWebViewController controller,
    ShoppingListItem item,
    int runId,
  ) async {
    final attemptId = ++_attemptId;
    final timeout = Completer<_ItemOutcome>();
    final timer = Timer(_itemLimit, () {
      if (!_isAttemptActive(runId, attemptId)) return;
      _attemptId++;
      adapter.cancelPendingActions();
      timeout.complete(const _ItemOutcome.timedOut());
    });
    final work = _processItem(adapter, controller, item, runId, attemptId).then(
      (_) => const _ItemOutcome.completed(),
      onError: (Object error, StackTrace stack) =>
          _ItemOutcome.failed(error, stack),
    );
    final outcome = await Future.any([work, timeout.future]);
    timer.cancel();
    if (outcome.timedOut) {
      _recordFailure(
        item,
        'Item exceeded the 30-second limit',
        selectorFailure: false,
      );
      return;
    }
    if (outcome.error case final error?) {
      final selectorFailure =
          error is StoreAutomationException && error.selectorFailure;
      _recordFailure(
        item,
        error is StoreAutomationException
            ? error.message
            : 'Unexpected PandaMart error: $error',
        selectorFailure: selectorFailure,
      );
    }
  }

  Future<void> _processItem(
    PandaMartAdapter adapter,
    InAppWebViewController controller,
    ShoppingListItem item,
    int runId,
    int attemptId,
  ) async {
    _log(item.name, 'Understanding ${item.quantity} ${item.unit}');
    ShoppingQueryNormalization? normalization;
    try {
      final response = await _matcher.normalize(item);
      if (_isAttemptActive(runId, attemptId) &&
          GroceryQueryNormalizer.isSafeNormalization(
            item.name,
            response.searchQuery,
          )) {
        normalization = response;
        if (response.changed) {
          _log(
            item.name,
            'Recognized as "${response.searchQuery}" (${(response.confidence * 100).round()}%)',
          );
        }
      }
    } catch (error) {
      _log(item.name, 'Could not normalize name; using exact text: $error');
    }
    if (!_isAttemptActive(runId, attemptId)) return;

    final queries = GroceryQueryNormalizer.searchQueries(
      item.name,
      normalization?.searchQuery ?? item.name,
      confidence: normalization?.confidence ?? 0,
    );
    List<ProductCandidate> candidates = const [];
    ProductMatch? match;
    String? approvedGenericQuery;
    for (var queryIndex = 0; queryIndex < queries.length; queryIndex++) {
      final query = queries[queryIndex];
      final isGenericQuery =
          query.toLowerCase() != item.name.trim().toLowerCase();
      _log(
        item.name,
        isGenericQuery
            ? 'Searching PandaMart for: $query'
            : 'Searching exact name: $query',
      );
      candidates = await adapter.search(controller, query);
      if (!_isAttemptActive(runId, attemptId)) return;
      if (candidates.isEmpty) continue;

      final wantedForMatch = ShoppingListItem(
        id: item.id,
        name: query,
        quantity: item.quantity,
        unit: item.unit,
        keepAfterOrder: item.keepAfterOrder,
      );
      match = await _matcher.match(wantedForMatch, candidates);
      if (!_isAttemptActive(runId, attemptId)) return;
      if (match.chosenIndex != null && match.unitsToBuy != null) {
        approvedGenericQuery = isGenericQuery ? query : null;
        break;
      }
    }
    if (candidates.isEmpty) {
      _addResult(
        item,
        status: AddStatus.notFound,
        reason: 'No matching products were found',
      );
      _guard.record(selectorSucceeded: true);
      return;
    }
    if (match == null ||
        match.chosenIndex == null ||
        match.unitsToBuy == null) {
      final reason = match?.reason ?? 'No suitable fresh product was found';
      _addResult(item, status: AddStatus.notFound, reason: reason);
      _guard.record(selectorSucceeded: true);
      _log(item.name, 'No match: $reason');
      return;
    }
    final candidate = candidates[match.chosenIndex!];
    if (match.confidence < _confidenceThreshold) {
      _addResult(
        item,
        status: AddStatus.lowConfidence,
        reason: 'Low confidence: ${match.reason}',
        productName: candidate.name,
      );
      _guard.record(selectorSucceeded: true);
      return;
    }
    if (!_allowSubstitutions &&
        _isPossibleSubstitution(
          item,
          candidate,
          approvedGenericQuery: approvedGenericQuery,
        )) {
      _addResult(
        item,
        status: AddStatus.lowConfidence,
        reason: 'Possible substitution needs your approval',
        productName: candidate.name,
      );
      _guard.record(selectorSucceeded: true);
      return;
    }

    final quantity = match.unitsToBuy!.clamp(1, 10).toInt();
    final added = await adapter.addToCart(controller, candidate, quantity);
    if (!_isAttemptActive(runId, attemptId)) return;
    _guard.record(selectorSucceeded: added.status != AddStatus.failed);
    _addResult(
      item,
      status: added.status,
      reason: added.message,
      productName: candidate.name,
      unitsAdded: added.added ? quantity : null,
      unitPrice: candidate.price,
    );
    _log(item.name, '${candidate.name} ×$quantity: ${added.message}');
  }

  bool _isPossibleSubstitution(
    ShoppingListItem wanted,
    ProductCandidate candidate, {
    String? approvedGenericQuery,
  }) {
    if (approvedGenericQuery != null &&
        GroceryQueryNormalizer.isApprovedEquivalent(
          approvedGenericQuery,
          candidate.name,
        )) {
      return false;
    }
    final wantedTokens = RegExp(r'[a-z0-9]+')
        .allMatches(wanted.name.toLowerCase())
        .map((match) => match.group(0)!)
        .where((token) => token.length > 1)
        .toSet();
    final candidateTokens = RegExp(r'[a-z0-9]+')
        .allMatches(candidate.name.toLowerCase())
        .map((match) => match.group(0)!)
        .toSet();
    return wantedTokens.any((token) => !candidateTokens.contains(token));
  }

  bool _isRunActive(int runId) =>
      mounted && !_cancelled && _running && runId == _runId;

  bool _isAttemptActive(int runId, int attemptId) =>
      _isRunActive(runId) && attemptId == _attemptId;

  void _addResult(
    ShoppingListItem item, {
    required AddStatus status,
    required String reason,
    String? productName,
    int? unitsAdded,
    double? unitPrice,
  }) {
    _results.add(
      AutomationItemResult(
        wantedItemId: item.id,
        wantedName: item.name,
        wantedQuantity: item.quantity,
        wantedUnit: item.unit,
        status: status,
        reason: reason,
        productName: productName,
        unitsAdded: unitsAdded,
        unitPrice: unitPrice,
      ),
    );
  }

  void _recordFailure(
    ShoppingListItem item,
    String reason, {
    bool selectorFailure = true,
  }) {
    _addResult(item, status: AddStatus.failed, reason: reason);
    _guard.record(selectorSucceeded: !selectorFailure);
    _log(item.name, reason);
  }

  Future<void> _openReview(
    PandaMartAdapter adapter,
    InAppWebViewController controller,
  ) async {
    _cart.clear();
    if (adapter.isCartVerificationConfigured) {
      try {
        _cart.addAll(await adapter.readCart(controller));
      } catch (error) {
        _log('verify', 'Cart read failed: $error');
      }
    } else {
      _log('verify', 'Live filled-cart selectors are not configured yet');
    }
    _comparison = compareCart(_results, _cart, baseline: _baselineCart);
    for (final missing in _comparison.missing) {
      _log('verify', '$missing was not found in the cart');
    }
    for (final mismatch in _comparison.quantityMismatches) {
      _log(
        'verify',
        '${mismatch.name}: expected ${mismatch.expected}, found ${mismatch.actual}',
      );
    }
    if (!mounted) return;
    setState(() {
      _running = false;
      _reviewing = true;
      _status = _cartVerified
          ? 'Cart verified — review before purchase'
          : 'Cart needs manual review before purchase';
    });
  }

  void _continueManually(String reason) {
    _cancelled = true;
    _attemptId++;
    _panda?.cancelPendingActions();
    _log('manual', reason);
    if (!mounted) return;
    setState(() {
      _running = false;
      _reviewing = false;
      _manual = true;
      _loadingConfig = false;
      _status = '$reason Continue manually in PandaMart.';
    });
  }

  Future<void> _purchase() async {
    if (!_canPurchase) return;
    final total = _total!;
    final message = total >= _highValueThreshold
        ? 'This cart is approximately Rs ${total.toStringAsFixed(0)}. Continue to PandaMart checkout?'
        : 'Continue to PandaMart checkout? The app will prefer cash on delivery and will never enter card details.';
    final approved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          total >= _highValueThreshold
              ? 'Confirm high-value order'
              : 'Confirm purchase',
        ),
        content: Text(message),
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
    if (approved != true || !mounted) return;

    final adapter = _adapter;
    final controller = _controller;
    if (adapter == null || controller == null || _purchasing) return;
    setState(() {
      _purchasing = true;
      _status = 'Opening PandaMart checkout…';
    });
    final result = await adapter.placeOrder(controller);
    _log('checkout', result.message);
    if (!mounted) return;
    setState(() => _purchasing = false);
    if (result.state == CheckoutState.placed) {
      await _recordOrder();
      return;
    }
    _manualCheckoutStarted = true;
    _continueManually(result.message);
  }

  Future<void> _confirmManualOrder() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirm PandaMart order'),
        content: const Text(
          'Only continue if PandaMart now shows that the order was placed successfully.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Not yet'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Order confirmed'),
          ),
        ],
      ),
    );
    if (confirmed == true) await _recordOrder();
  }

  Future<void> _recordOrder() async {
    final invalidNames = {
      ..._comparison.missing.map((name) => name.toLowerCase()),
      ..._comparison.quantityMismatches.map(
        (mismatch) => mismatch.name.toLowerCase(),
      ),
    };
    final purchasedItemIds = _results
        .where(
          (result) =>
              result.status == AddStatus.added &&
              !invalidNames.contains(result.wantedName.toLowerCase()),
        )
        .map((result) => result.wantedItemId)
        .whereType<String>()
        .toSet();
    if (purchasedItemIds.isEmpty || _total == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No cart-verified items are ready to record.'),
          ),
        );
      }
      return;
    }
    final order = await context.read<ShoppingProvider>().recordStoreOrder(
      storeName: _adapter?.name ?? 'PandaMart',
      total: _total!,
      purchasedItemIds: purchasedItemIds,
    );
    if (!mounted) return;
    if (order == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('The order could not be recorded.')),
      );
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Order recorded as pending delivery. Pantry stock was not changed.',
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
    final adapter = _panda;
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
                  if (_running || _loadingConfig || _purchasing) ...[
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
                if (adapter != null)
                  InAppWebView(
                    initialUrlRequest: URLRequest(
                      url: WebUri(adapter.homeUrl.toString()),
                    ),
                    initialSettings: InAppWebViewSettings(
                      javaScriptEnabled: true,
                      domStorageEnabled: true,
                      databaseEnabled: true,
                      cacheEnabled: true,
                      thirdPartyCookiesEnabled: true,
                      sharedCookiesEnabled: true,
                      geolocationEnabled: true,
                      preferredContentMode: UserPreferredContentMode.DESKTOP,
                      useWideViewPort: true,
                      loadWithOverviewMode: true,
                      supportZoom: true,
                      useShouldOverrideUrlLoading: true,
                      javaScriptCanOpenWindowsAutomatically: true,
                      supportMultipleWindows: true,
                    ),
                    onWebViewCreated: (controller) {
                      _controller = controller;
                      if (mounted) setState(() {});
                    },
                    shouldOverrideUrlLoading: (_, action) async {
                      final value = action.request.url?.toString();
                      final uri = value == null ? null : Uri.tryParse(value);
                      if (uri?.scheme == 'about' || adapter.isAllowedUri(uri)) {
                        return NavigationActionPolicy.ALLOW;
                      }
                      if (adapter.isExternalLoginUri(uri)) {
                        _log(
                          'navigation',
                          'Allowing secure social-login navigation: ${uri?.host}',
                        );
                        if (mounted) {
                          setState(() {
                            _pageReady = false;
                            _status =
                                'Complete social sign-in inside CulinaryAI';
                          });
                        }
                        return NavigationActionPolicy.ALLOW;
                      }
                      _log('navigation', 'Blocked external navigation: $value');
                      if (mounted) {
                        setState(() {
                          _status = 'Blocked a PandaMart app redirect';
                        });
                      }
                      return NavigationActionPolicy.CANCEL;
                    },
                    onLoadStart: (_, _) {
                      if (mounted && !_running && !_reviewing) {
                        setState(() => _pageReady = false);
                      }
                    },
                    onLoadStop: (_, _) => _handleStoreLoadStop(),
                    onGeolocationPermissionsShowPrompt: (_, origin) =>
                        _handleGeolocationPrompt(origin),
                    onCreateWindow: (_, action) async {
                      final value = action.request.url?.toString();
                      final uri = value == null ? null : Uri.tryParse(value);
                      if (!adapter.isExternalLoginUri(uri) ||
                          _loginPopupWindowId != null) {
                        _log(
                          'navigation',
                          'Blocked untrusted popup host: ${uri?.host ?? 'unknown'}',
                        );
                        return false;
                      }
                      _log(
                        'navigation',
                        'Opening secure login popup: ${uri!.host}',
                      );
                      if (mounted) {
                        setState(() {
                          _loginPopupWindowId = action.windowId;
                          _pageReady = false;
                          _status = 'Complete social sign-in inside CulinaryAI';
                        });
                      }
                      return true;
                    },
                  ),
                if (_loginPopupWindowId case final windowId?)
                  Positioned.fill(
                    child: Material(
                      color: Theme.of(context).scaffoldBackgroundColor,
                      child: Column(
                        children: [
                          SizedBox(
                            height: 48,
                            child: Row(
                              children: [
                                const SizedBox(width: 16),
                                const Icon(Icons.lock_outline, size: 18),
                                const SizedBox(width: 8),
                                const Expanded(
                                  child: Text('Secure PandaMart sign-in'),
                                ),
                                IconButton(
                                  tooltip: 'Cancel sign-in',
                                  onPressed: _cancelLoginPopup,
                                  icon: const Icon(Icons.close),
                                ),
                              ],
                            ),
                          ),
                          const Divider(height: 1),
                          Expanded(
                            child: InAppWebView(
                              key: ValueKey('login-popup-$windowId'),
                              windowId: windowId,
                              initialSettings: InAppWebViewSettings(
                                javaScriptEnabled: true,
                                domStorageEnabled: true,
                                databaseEnabled: true,
                                cacheEnabled: true,
                                thirdPartyCookiesEnabled: true,
                                sharedCookiesEnabled: true,
                                useShouldOverrideUrlLoading: true,
                              ),
                              onWebViewCreated: (controller) {
                                _loginPopupController = controller;
                              },
                              shouldOverrideUrlLoading: (_, action) async {
                                final value = action.request.url?.toString();
                                final uri = value == null
                                    ? null
                                    : Uri.tryParse(value);
                                if (uri?.scheme == 'about' ||
                                    adapter!.isExternalLoginUri(uri) ||
                                    adapter.isAllowedUri(uri)) {
                                  return NavigationActionPolicy.ALLOW;
                                }
                                _log(
                                  'navigation',
                                  'Blocked login-popup navigation: ${uri?.host ?? value}',
                                );
                                return NavigationActionPolicy.CANCEL;
                              },
                              onCloseWindow: (_) => _finishLoginPopup(),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                if (_reviewing) Positioned.fill(child: _buildReview()),
              ],
            ),
          ),
          if (!_running && !_reviewing && _loginPopupWindowId == null)
            _buildControls(),
        ],
      ),
    );
  }

  Widget _buildControls() {
    return SafeArea(
      minimum: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'Experimental: this controls PandaMart on your behalf. Google/Facebook sign-in opens securely inside CulinaryAI. Email magic links may open the Foodpanda app instead. Passwords, OTPs and card details are never read or entered.',
            style: TextStyle(fontSize: 12),
          ),
          if (!_manual) ...[
            OutlinedButton.icon(
              onPressed: _controller == null || _locating
                  ? null
                  : _useCurrentLocation,
              icon: _locating
                  ? const SizedBox.square(
                      dimension: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.my_location),
              label: const Text('Use current location'),
            ),
            const SizedBox(height: 4),
            CheckboxListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: const Text(
                'Allow equivalent substitutions',
                style: TextStyle(fontSize: 13),
              ),
              value: _allowSubstitutions,
              onChanged: _running
                  ? null
                  : (value) =>
                        setState(() => _allowSubstitutions = value ?? false),
              controlAffinity: ListTileControlAffinity.leading,
            ),
            FilledButton(
              onPressed: _controller == null || !_pageReady ? null : _start,
              child: const Text('Start adding'),
            ),
          ],
          if (_manual && _manualCheckoutStarted)
            FilledButton(
              onPressed: _confirmManualOrder,
              child: const Text('I see PandaMart order confirmation'),
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
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(
                      result.status == AddStatus.added
                          ? Icons.check_circle
                          : Icons.warning_amber,
                    ),
                    title: Text(result.productName ?? result.wantedName),
                    subtitle: Text(
                      result.status == AddStatus.added
                          ? '${result.unitsAdded} × Rs ${result.unitPrice?.toStringAsFixed(0)}'
                          : '${result.reason} — kept on your shopping list',
                    ),
                  ),
                const Divider(),
                Text(
                  'Entire PandaMart cart',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                if (_cart.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 8),
                    child: Text('Cart could not be verified automatically.'),
                  )
                else
                  for (final line in _cart)
                    ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      title: Text(line.name),
                      trailing: Text(
                        '${line.quantity} × Rs ${line.price.toStringAsFixed(0)}',
                      ),
                    ),
                if (_comparison.missing.isNotEmpty)
                  _warning(
                    'Missing from cart: ${_comparison.missing.join(', ')}',
                  ),
                for (final mismatch in _comparison.quantityMismatches)
                  _warning(
                    '${mismatch.name}: expected ${mismatch.expected}, found ${mismatch.actual}',
                  ),
                if (_comparison.unexpected.isNotEmpty)
                  _warning(
                    'Extra cart items: ${_comparison.unexpected.map((line) => line.name).join(', ')}',
                  ),
                const Divider(),
                Text(
                  _total == null
                      ? 'Cart total not verified'
                      : 'Cart total: Rs ${_total!.toStringAsFixed(0)}',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                if (!_cartVerified)
                  const Padding(
                    padding: EdgeInsets.only(top: 8),
                    child: Text(
                      'Purchase stays disabled until cart items, quantities and total are verified.',
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
                      _status = 'Edit and complete the cart manually';
                    }),
                    child: const Text('Edit manually'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: _canPurchase ? _purchase : null,
                    child: _purchasing
                        ? const SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Purchase'),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _warning(String message) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Text(
        message,
        style: TextStyle(color: Theme.of(context).colorScheme.error),
      ),
    );
  }
}

class _ItemOutcome {
  const _ItemOutcome.completed() : timedOut = false, error = null, stack = null;
  const _ItemOutcome.timedOut() : timedOut = true, error = null, stack = null;
  const _ItemOutcome.failed(this.error, this.stack) : timedOut = false;

  final bool timedOut;
  final Object? error;
  final StackTrace? stack;
}

class _RunOutcome {
  const _RunOutcome.completed() : timedOut = false, error = null, stack = null;
  const _RunOutcome.timedOut() : timedOut = true, error = null, stack = null;
  const _RunOutcome.failed(this.error, this.stack) : timedOut = false;

  final bool timedOut;
  final Object? error;
  final StackTrace? stack;
}
