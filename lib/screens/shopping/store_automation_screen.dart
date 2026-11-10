import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../models/shopping_models.dart';
import '../../widgets/app_ui.dart';
import '../../models/store_models.dart';
import '../../providers/shopping_provider.dart';
import '../../services/automation_failure_guard.dart';
import '../../services/cart_comparison.dart';
import '../../services/grocery_query_normalizer.dart';
import '../../services/pandamart_adapter.dart';
import '../../services/product_matching_service.dart';
import '../../services/store_adapter.dart';
import '../../services/store_selector_config.dart';
import '../../services/store_checkout_service.dart';
import '../../services/purchase_session_store.dart';
import '../../services/store_location_service.dart';
import '../../services/exact_product_matcher.dart';

class StoreAutomationScreen extends StatefulWidget {
  const StoreAutomationScreen({
    super.key,
    required this.items,
    this.externalStore = kIsWeb,
  });

  final List<ShoppingListItem> items;
  final bool externalStore;

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
  bool _checkingPageState = false;
  Timer? _pageStateTimer;
  bool _running = false;
  bool _starting = false;
  bool _reviewing = false;
  bool _manual = false;
  bool _purchasing = false;
  bool _recordingOrder = false;
  bool _orderConfirmed = false;
  bool _refreshingCart = false;
  CheckoutResult? _checkoutResult;
  String _orderRecordId = const Uuid().v4();
  final _purchaseSessions = PurchaseSessionStore();
  List<ShoppingListItem> _orderItems = [];
  bool _recoveredAttempt = false;
  String? _householdId;
  Set<String>? _confirmedItemIds;
  double? _confirmedTotal;
  bool _manualCheckoutStarted = false;
  bool _cancelled = false;
  bool _allowSubstitutions = false;
  bool _locating = false;
  bool _confirmingAddress = false;
  bool _addressCanConfirm = false;
  String _selectedDeliveryAddress = '';
  String? _setupAction;
  String? _pendingSetupAction;
  bool _signedIn = false;
  bool _addressSelected = false;
  bool _storeSelected = false;
  int _current = 0;
  int _runId = 0;
  int _attemptId = 0;
  int _pageGeneration = 0;
  String _status = 'Opening PandaMart…';

  PandaMartAdapter? get _panda =>
      _adapter is PandaMartAdapter ? _adapter! as PandaMartAdapter : null;

  String get _deliveryAddressPrompt {
    return 'Select your delivery address or use current location';
  }

  double? get _total => _panda?.lastCartTotal;

  bool get _cartVerified =>
      _panda?.lastCartReadWasVerified == true &&
      _results.any((item) => item.status == AddStatus.added) &&
      _comparison.isVerified &&
      _cart.isNotEmpty &&
      _total != null;

  bool get _canPurchase =>
      _reviewing &&
      !_purchasing &&
      !_refreshingCart &&
      !_orderConfirmed &&
      !_recoveredAttempt &&
      _cartVerified &&
      (_total ?? 0) > 0;

  @override
  void initState() {
    super.initState();
    _householdId = context.read<ShoppingProvider>().householdId;
    _orderItems = List.of(widget.items);
    _loadAdapter();
    if (!widget.externalStore) {
      _pageStateTimer = Timer.periodic(
        const Duration(seconds: 2),
        (_) => _refreshPageState(),
      );
    }
  }

  @override
  void dispose() {
    _pageStateTimer?.cancel();
    _cancelled = true;
    _runId++;
    _attemptId++;
    _panda?.cancelPendingActions();
    super.dispose();
  }

  Future<void> _loadAdapter() async {
    try {
      final config = await StoreSelectorConfig.load('pandamart');
      PurchaseSession? pending;
      try {
        pending = _householdId == null
            ? null
            : await _purchaseSessions.load(_householdId!);
      } catch (_) {
        if (!mounted) return;
        setState(() {
          _adapter = PandaMartAdapter(config);
          _loadingConfig = false;
          _manual = true;
          _manualCheckoutStarted = true;
          _recoveredAttempt = true;
          _status = 'Saved checkout could not be read. Check PandaMart orders before clearing this attempt.';
        });
        return;
      }
      if (!mounted) return;
      setState(() {
        _adapter = PandaMartAdapter(config);
        _loadingConfig = false;
        _status = 'Set your delivery address, then choose a nearby PandaMart';
        if (pending != null) {
          _orderRecordId = pending.id;
          _orderItems = pending.items;
          _confirmedItemIds = pending.items.map((item) => item.id).toSet();
          _confirmedTotal = pending.total;
          _orderConfirmed = pending.confirmed;
          _checkoutResult = CheckoutResult(
            CheckoutState.needsManualCompletion,
            'Recovered checkout',
            orderReference: pending.storeOrderReference,
          );
          _recoveredAttempt = true;
          _manual = true;
          _manualCheckoutStarted = true;
          _status = pending.confirmed
              ? 'Order confirmed. Tap Retry saving order to finish recording it.'
              : 'An earlier checkout was interrupted. Check PandaMart orders before purchasing again.';
        }
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
    if (!mounted ||
        _checkingPageState ||
        adapter == null ||
        controller == null ||
        _running ||
        _starting ||
        _reviewing ||
        _manual ||
        _purchasing ||
        _recordingOrder ||
        _loadingConfig) {
      return;
    }
    _checkingPageState = true;
    final generation = _pageGeneration;
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
      final addressEditing = await adapter.isAddressEntryOpen(controller);
      if (!mounted) return;
      if (interruption != null && !addressEditing) {
        setState(() {
          _pageReady = false;
          _status = '$interruption Finish it in the WebView.';
        });
        return;
      }
      final loggedIn = await adapter.isLoggedIn(controller);
      final addressSelected = await adapter.hasSelectedAddress(controller);
      final addressLabel = await adapter.selectedAddressLabel(controller);
      final addressReady =
          addressEditing && await adapter.addressSelectionReady(controller);
      final activeStore = await adapter.hasActiveStore(controller);
      if (!mounted ||
          generation != _pageGeneration ||
          controller != _controller) {
        return;
      }
      setState(() {
        _signedIn = loggedIn;
        _addressSelected = addressSelected && !addressEditing;
        _addressCanConfirm = addressReady;
        _selectedDeliveryAddress = addressLabel;
        _storeSelected = activeStore;
        _pageReady =
            loggedIn && addressSelected && activeStore && !addressEditing;
        if (addressEditing && _setupAction == null) {
          _setupAction = 'address';
          _status = 'Choose the matching suggestion, check the pin, then confirm the address.';
        }
        if (_setupAction == null) {
          _status = addressEditing
              ? 'Confirm the delivery address and pin in Foodpanda above'
              : !addressSelected
              ? _deliveryAddressPrompt
              : !activeStore
              ? 'Choose a nearby PandaMart from the Foodpanda page'
              : !loggedIn
              ? 'Sign in to Foodpanda inside PandaMart'
              : 'Ready to add ${widget.items.length} shopping-list items';
        }
      });
    } catch (error) {
      _log('page', 'Page readiness check failed: $error');
    } finally {
      _checkingPageState = false;
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

  Future<bool> _trySetupControl(String action) async {
    final adapter = _panda;
    final controller = _controller;
    if (adapter == null || controller == null) return false;
    if (action == 'store') return adapter.openStoreSelection(controller);
    for (
      var attempt = 0;
      attempt < 10 && mounted && _setupAction == action;
      attempt++
    ) {
      final opened = action == 'login'
          ? await adapter.openSignIn(controller)
          : await adapter.openAddressEntry(controller);
      if (opened) {
        if (action != 'location') return true;
        for (
          var locateAttempt = 0;
          locateAttempt < 10 && mounted && _setupAction == action;
          locateAttempt++
        ) {
          if (await adapter.clickLocateMe(controller)) return true;
          await Future<void>.delayed(const Duration(milliseconds: 200));
        }
        return false;
      }
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }
    return false;
  }

  Future<void> _openSetup(String action) async {
    if (_controller == null || _panda == null || _running || _purchasing) {
      return;
    }
    FocusManager.instance.primaryFocus?.unfocus();
    if (action == 'address' || action == 'location') {
      await _panda!.trackDeliveryAddressEdits(_controller!);
      if (!mounted) return;
    }
    setState(() {
      _setupAction = action;
      _pendingSetupAction = null;
      _pageReady = false;
      _pageGeneration++;
      _status = action == 'store'
          ? 'Choose a nearby PandaMart for the confirmed delivery address.'
          : action == 'login'
          ? 'Opening Foodpanda sign-in...'
          : 'Opening delivery address...';
    });
    try {
      final opened = await _trySetupControl(action);
      if (!mounted || _setupAction != action) return;
      if (opened) {
        if (mounted) {
          setState(
            () => _status = action == 'login'
                ? 'Complete sign-in using a method offered by Foodpanda'
                : action == 'store'
                ? 'Choose a nearby PandaMart above, then return to setup.'
                : action == 'location'
                ? 'Review the detected pin and confirm your address in Foodpanda'
                : 'Search for your address and confirm the delivery pin in Foodpanda',
          );
        }
      } else {
        _pendingSetupAction = action;
        setState(
          () => _status = action == 'login'
              ? 'Open sign-in on the Foodpanda page above.'
              : 'Open the address search above. Choose a suggestion, then confirm the pin.',
        );
      }
    } catch (error) {
      _log('setup', 'Could not open $action: $error');
      if (mounted) {
        setState(
          () => _status = 'Complete this step on the Foodpanda page above, then return to setup.',
        );
      }
    }
  }

  Future<void> _useCurrentLocation() async {
    if (_controller == null || _locating || _running) return;
    setState(() => _locating = true);
    try {
      final granted = await _requestLocationPermission();
      if (!mounted) return;
      if (!granted) {
        setState(
          () => _status = 'Location permission was not granted. Use Set delivery address to search manually.',
        );
        return;
      }
      if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
        try {
          final location = await StoreLocationService().currentAddress();
          if (!mounted) return;
          await _openSetup('address');
          if (!mounted || _setupAction != 'address') return;
          final filled = await _panda!.searchDeliveryAddress(
            _controller!,
            location.address,
          );
          if (mounted) {
            setState(
              () => _status = filled
                  ? 'Choose the matching suggestion, check the pin, then tap Confirm delivery address.'
                  : 'GPS address: ${location.address}. Enter it above and confirm the pin.',
            );
          }
        } on Object catch (error) {
          if (!mounted) return;
          await _openSetup('address');
          if (!mounted) return;
          final message = error is PlatformException ? error.message : null;
          setState(
            () => _status = message ?? 'Current location could not be resolved. Search for your address manually.',
          );
        }
      } else {
        await _openSetup('location');
      }
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  Future<void> _confirmDeliveryAddress() async {
    final controller = _controller;
    final adapter = _panda;
    if (controller == null || adapter == null || _confirmingAddress) return;
    setState(() => _confirmingAddress = true);
    try {
      if (await adapter.isAddressEntryOpen(controller)) {
        if (!await adapter.confirmDeliveryAddress(controller)) {
          if (mounted) {
            setState(
              () => _status = 'Choose a valid address suggestion and check the delivery pin first.',
            );
          }
          return;
        }
        for (var attempt = 0; attempt < 30 && mounted; attempt++) {
          await Future<void>.delayed(const Duration(milliseconds: 250));
          if (!await adapter.isAddressEntryOpen(controller) &&
              await adapter.hasSelectedAddress(controller)) {
            break;
          }
        }
      }
      if (!mounted) return;
      final confirmedLabel = await adapter.selectedAddressLabel(controller);
      if (await adapter.isAddressEntryOpen(controller) ||
          !await adapter.hasSelectedAddress(controller)) {
        setState(
          () => _status = 'Foodpanda has not confirmed this address yet. Choose a suggestion, correct the pin and try again.',
        );
        return;
      }
      setState(() {
        _setupAction = null;
        _pendingSetupAction = null;
        _pageGeneration++;
        _selectedDeliveryAddress = confirmedLabel;
      });
      await _refreshPageState();
    } catch (_) {
      if (mounted) {
        setState(
          () => _status = 'The address could not be confirmed. Check the Foodpanda form and try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _confirmingAddress = false);
    }
  }

  Future<void> _handleStoreLoadStop() async {
    if (_panda != null && _controller != null) {
      try {
        await _panda!.trackDeliveryAddressEdits(_controller!);
      } catch (_) {}
    }
    await _refreshPageState();
    final action = _pendingSetupAction;
    if (action == null || !mounted || _running || _setupAction != action) {
      return;
    }
    _pendingSetupAction = null;
    final opened = await _trySetupControl(action);
    if (!mounted || _setupAction != action) {
      return;
    }
    if (mounted) {
      setState(
        () => _status = opened
            ? action == 'login'
                  ? 'Complete Foodpanda sign-in above'
                  : 'Confirm the delivery address in Foodpanda'
            : 'Use the Foodpanda address or account control above, then return to setup.',
      );
    }
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
    if (adapter == null ||
        controller == null ||
        _running ||
        _starting ||
        _purchasing ||
        _results.isNotEmpty ||
        adapter.checkout.hasSubmitted ||
        _orderConfirmed) {
      return;
    }
    _starting = true;
    try {
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
        if (mounted) {
          setState(() => _status = '$interruption Resolve it first.');
        }
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
            () => _status = 'Choose a nearby PandaMart from Foodpanda, then tap Start adding',
          );
        }
        return;
      }
      if (!mounted) return;

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
          _continueManually('The starting cart could not be verified.');
          return;
        }
      }
      if (!_isRunActive(runId)) return;

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
    } catch (error) {
      _log('start', 'Could not start adding: $error');
      _continueManually('PandaMart was not ready to start adding.');
    } finally {
      _starting = false;
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
    if (!_isRunActive(runId)) return;
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
    final queries = [item.name.trim()];
    Future<void> appendNormalizedQuery() async {
      if (queries.length != 1 || !_isAttemptActive(runId, attemptId)) return;
      try {
        final response = await _matcher
            .normalize(item)
            .timeout(const Duration(seconds: 4));
        if (!_isAttemptActive(runId, attemptId)) return;
        for (final query in GroceryQueryNormalizer.searchQueries(
          item.name,
          response.searchQuery,
          confidence: response.confidence,
        )) {
          if (!queries.contains(query)) queries.add(query);
        }
      } catch (_) {
        _log(
          item.name,
          'Online name correction unavailable; keeping the requested product.',
        );
      }
    }

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
      if (candidates.isEmpty) {
        if (queryIndex == 0) await appendNormalizedQuery();
        continue;
      }

      final wantedForMatch = ShoppingListItem(
        id: item.id,
        name: query,
        quantity: item.quantity,
        unit: item.unit,
        keepAfterOrder: item.keepAfterOrder,
      );
      match = ExactProductMatcher.match(wantedForMatch, candidates);
      if (match == null) {
        try {
          match = await _matcher
              .match(wantedForMatch, candidates)
              .timeout(const Duration(seconds: 8));
        } catch (_) {
          _log(
            item.name,
            'Online matching unavailable; no uncertain product was added.',
          );
        }
      }
      if (!_isAttemptActive(runId, attemptId)) return;
      if (match != null &&
          match.chosenIndex != null &&
          match.unitsToBuy != null) {
        approvedGenericQuery = isGenericQuery ? query : null;
        break;
      }
      if (queryIndex == 0) await appendNormalizedQuery();
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
      productId: candidate.storeId,
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
    String? productId,
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
        productId: productId,
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
    final adapter = _panda;
    final controller = _controller;
    if (adapter == null || controller == null) return;
    final reviewed = List.of(_cart);
    final reviewedTotal = _total;
    setState(() {
      _purchasing = true;
      _status = 'Rechecking the cart…';
    });
    try {
      final latest = await adapter.readCart(controller);
      if (!mounted) return;
      if (!StoreCheckoutService.sameCart(reviewed, latest) ||
          _total != reviewedTotal) {
        await _openReview(adapter, controller);
        if (mounted) {
          setState(
            () => _status = 'The cart changed. Review the updated cart.',
          );
        }
        return;
      }
      setState(() {
        _reviewing = false;
        _status = 'Preparing cash-on-delivery checkout…';
      });
      _manualCheckoutStarted = true;
      final result = await adapter.placeOrder(
        controller,
        expectedCart: reviewed,
        approve: _approveCheckout,
        beforeSubmit: (summary) async {
          if (!mounted ||
              context.read<ShoppingProvider>().householdId != _householdId) {
            throw StateError('The household changed during checkout.');
          }
          _confirmedItemIds = _results
              .where((item) => item.status == AddStatus.added)
              .map((item) => item.wantedItemId)
              .whereType<String>()
              .toSet();
          _confirmedTotal = summary.total;
          await _savePurchaseSession(confirmed: false);
        },
      );
      _checkoutResult = result;
      _log('checkout', result.message);
      if (!mounted) return;
      if (result.state == CheckoutState.placed) {
        _orderConfirmed = true;
        _confirmedTotal = result.summary?.total;
        _confirmedItemIds = _results
            .where((item) => item.status == AddStatus.added)
            .map((item) => item.wantedItemId)
            .whereType<String>()
            .toSet();
        await _recordOrder();
      } else {
        _continueManually(result.message);
      }
    } catch (error) {
      _log('checkout', 'Checkout could not finish: $error');
      _continueManually(
        'Checkout could not finish. Check the current PandaMart page.',
      );
    } finally {
      if (mounted) setState(() => _purchasing = false);
    }
  }

  Future<bool> _approveCheckout(CheckoutSummary summary) async {
    if (!mounted ||
        context.read<ShoppingProvider>().householdId != _householdId) {
      return false;
    }
    final approved = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: Text(
          summary.total >= _highValueThreshold
              ? 'Confirm high-value order'
              : 'Confirm purchase',
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final line in summary.lines)
                Text('${line.quantity} × ${line.name}'),
              const SizedBox(height: 12),
              Text('Deliver to: ${summary.deliveryAddress}'),
              const Text('Payment: Cash on delivery'),
              const SizedBox(height: 8),
              Text(
                'Final total including fees: Rs ${summary.total.toStringAsFixed(2)}',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              const Text('Place this order with PandaMart?'),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Place order'),
          ),
        ],
      ),
    );
    return approved == true &&
        mounted &&
        context.read<ShoppingProvider>().householdId == _householdId;
  }

  Future<void> _confirmManualOrder() async {
    if (_purchasing || _recordingOrder) return;
    final form = GlobalKey<FormState>();
    final totalController = TextEditingController(
      text: _confirmedTotal?.toStringAsFixed(2) ?? '',
    );
    final selected = Set<String>.of(
      _confirmedItemIds ??
          _results
              .where((item) => item.status == AddStatus.added)
              .map((item) => item.wantedItemId)
              .whereType<String>()
              .toSet(),
    );
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, update) => AlertDialog(
          title: const Text('Confirm PandaMart order'),
          content: SizedBox(
            width: 380,
            child: SingleChildScrollView(
              child: Form(
                key: form,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'Only continue if PandaMart shows a successful order. Select the shopping items on that order and enter its final total.',
                    ),
                    for (final item in _orderItems)
                      CheckboxListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(item.name),
                        value: selected.contains(item.id),
                        onChanged: (value) => update(() {
                          if (value == true) {
                            selected.add(item.id);
                          } else {
                            selected.remove(item.id);
                          }
                        }),
                      ),
                    TextFormField(
                      controller: totalController,
                      decoration: const InputDecoration(
                        labelText: 'Final order total (Rs)',
                      ),
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      validator: (value) {
                        final total = double.tryParse(value?.trim() ?? '');
                        if (selected.isEmpty) {
                          return 'Select at least one purchased item';
                        }
                        return total == null || !total.isFinite || total <= 0
                            ? 'Enter the confirmed order total'
                            : null;
                      },
                    ),
                  ],
                ),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Not yet'),
            ),
            FilledButton(
              onPressed: () {
                if (form.currentState?.validate() == true) {
                  Navigator.pop(context, true);
                }
              },
              child: const Text('Order confirmed'),
            ),
          ],
        ),
      ),
    );
    final total = double.tryParse(totalController.text.trim());
    totalController.dispose();
    if (confirmed == true && mounted) {
      _orderConfirmed = true;
      _confirmedTotal = total;
      _confirmedItemIds = selected;
      await _recordOrder();
    }
  }

  Future<void> _recordOrder() async {
    if (_recordingOrder || !_orderConfirmed || !mounted) return;
    final purchasedItemIds = _confirmedItemIds ?? const <String>{};
    if (purchasedItemIds.isEmpty || _confirmedTotal == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No cart-verified items are ready to record.'),
          ),
        );
      }
      return;
    }
    setState(() => _recordingOrder = true);
    final shopping = context.read<ShoppingProvider>();
    try {
      await _savePurchaseSession(confirmed: true);
      final order = await shopping.recordStoreOrder(
        storeName: _adapter?.name ?? 'PandaMart',
        total: _confirmedTotal!,
        purchasedItemIds: purchasedItemIds,
        purchasedItems: _orderItems,
        expectedHouseholdId: _householdId,
        orderId: _orderRecordId,
        storeOrderReference: _checkoutResult?.orderReference,
      );
      if (!mounted) return;
      if (order == null) {
        setState(() {
          _manual = true;
          _reviewing = false;
          _status = 'Order confirmed. Return to the original household to save this order.';
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('The order could not be recorded.')),
        );
        return;
      }
      if (_householdId != null) await _purchaseSessions.clear(_householdId!);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Order recorded as pending delivery. Pantry stock was not changed.',
          ),
        ),
      );
      Navigator.pop(context);
    } catch (error) {
      _log('record', 'Order saving failed: $error');
      if (mounted) {
        setState(() {
          _reviewing = false;
          _manual = true;
          _status = 'PandaMart order confirmed. Saving failed; tap Retry saving order.';
        });
      }
    } finally {
      if (mounted) setState(() => _recordingOrder = false);
    }
  }

  Future<void> _savePurchaseSession({required bool confirmed}) async {
    if (_householdId == null || _confirmedTotal == null) {
      throw StateError('A household and final total are required.');
    }
    await _purchaseSessions.save(
      PurchaseSession(
        id: _orderRecordId,
        householdId: _householdId!,
        items: _orderItems
            .where((item) => _confirmedItemIds?.contains(item.id) == true)
            .toList(),
        total: _confirmedTotal!,
        confirmed: confirmed,
        storeOrderReference: _checkoutResult?.orderReference,
      ),
    );
  }

  Future<void> _reviewCurrentCart() async {
    final adapter = _panda;
    final controller = _controller;
    if (adapter == null ||
        controller == null ||
        _purchasing ||
        _refreshingCart ||
        _orderConfirmed ||
        _recoveredAttempt ||
        adapter.checkout.hasSubmitted) {
      return;
    }
    setState(() => _refreshingCart = true);
    try {
      await _openReview(adapter, controller);
    } finally {
      if (mounted) setState(() => _refreshingCart = false);
    }
  }

  Future<void> _checkOrderStatus() async {
    final adapter = _panda;
    final controller = _controller;
    if (adapter == null ||
        controller == null ||
        _purchasing ||
        !adapter.checkout.hasSubmitted) {
      return;
    }
    setState(() => _purchasing = true);
    try {
      final result = await adapter.placeOrder(
        controller,
        expectedCart: _cart,
        approve: (_) async => false,
      );
      _checkoutResult = result;
      if (!mounted) return;
      if (result.state == CheckoutState.placed) {
        _orderConfirmed = true;
        await _recordOrder();
      } else {
        setState(() => _status = result.message);
      }
    } finally {
      if (mounted) setState(() => _purchasing = false);
    }
  }

  Future<void> _dismissUnplacedAttempt() async {
    if (_purchasing || _recordingOrder || _householdId == null) return;
    final checked = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('No order was placed?'),
        content: const Text(
          'Check PandaMart order history first. Only continue if this checkout created no order. Your cart remains in PandaMart; remove unwanted items before adding your list again.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Go back'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('I checked: no order'),
          ),
        ],
      ),
    );
    if (checked != true || !mounted) return;
    try {
      await _purchaseSessions.clear(_householdId!);
      if (mounted) Navigator.pop(context);
    } catch (_) {
      if (mounted) {
        setState(
          () => _status = 'Could not clear checkout recovery. Try again.',
        );
      }
    }
  }

  Future<void> _exportLog() async {
    await Clipboard.setData(ClipboardData(text: _logs.join('\n')));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Debug log copied to clipboard')),
      );
    }
  }

  Future<void> _openExternalStore() async {
    try {
      final opened = await launchUrl(
        _adapter?.homeUrl ?? Uri.parse('https://www.foodpanda.pk/groceries'),
        mode: LaunchMode.externalApplication,
        webOnlyWindowName: '_blank',
      );
      if (!opened) throw StateError('Store did not open');
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('PandaMart could not be opened. Please try again.'),
          ),
        );
      }
    }
  }

  Widget _buildExternalShopping() => Scaffold(
    appBar: AppBar(title: const Text('Shop with PandaMart')),
    body: SafeArea(
      child: AppPageBody(
        maxWidth: 760,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 36),
          children: [
            const PageIntro(
              eyebrow: 'YOUR NEXT GROCERY SHOP',
              title: 'A good kitchen starts here.',
              subtitle: 'Take your list to PandaMart, then record the items you ordered when checkout is complete.',
            ),
            const SizedBox(height: 24),
            const StatusNotice(
              message: 'In the browser, checkout opens in a separate tab. Automatic cart building is available in the mobile app.',
            ),
            if (_recoveredAttempt || _orderConfirmed) ...[
              const SizedBox(height: 16),
              StatusNotice(message: _status),
            ],
            const SizedBox(height: 24),
            FormSection(
              title: 'Your shopping list',
              description:
                  '${_orderItems.length} ${_orderItems.length == 1 ? 'item' : 'items'} to look for. Check pack sizes and availability in the store.',
              children: [
                for (final item in _orderItems)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.shopping_bag_outlined),
                    title: Text(item.name),
                    subtitle: Text(
                      '${item.quantity == item.quantity.roundToDouble() ? item.quantity.toStringAsFixed(0) : item.quantity} ${item.unit}',
                    ),
                  ),
                if (_orderItems.isEmpty)
                  const Text(
                    'Check your earlier order in PandaMart before starting a new shop.',
                  ),
                const SizedBox(height: 16),
                OutlinedButton.icon(
                  onPressed: _orderItems.isEmpty
                      ? null
                      : () async {
                          await Clipboard.setData(
                            ClipboardData(
                              text: _orderItems
                                  .map(
                                    (item) =>
                                        '${item.name} — ${item.quantity} ${item.unit}',
                                  )
                                  .join('\n'),
                            ),
                          );
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Shopping list copied'),
                              ),
                            );
                          }
                        },
                  icon: const Icon(Icons.copy_outlined),
                  label: const Text('Copy shopping list'),
                ),
              ],
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: _loadingConfig || _recordingOrder
                  ? null
                  : _openExternalStore,
              icon: const Icon(Icons.open_in_new_rounded),
              label: const Text('Open PandaMart'),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed:
                  _loadingConfig || _recordingOrder || _orderItems.isEmpty
                  ? null
                  : _orderConfirmed
                  ? _recordOrder
                  : _confirmManualOrder,
              icon: const Icon(Icons.receipt_long_outlined),
              label: Text(
                _recordingOrder
                    ? 'Saving order…'
                    : _orderConfirmed
                    ? 'Retry saving order'
                    : 'Record completed order',
              ),
            ),
            if (_recoveredAttempt && !_orderConfirmed)
              TextButton(
                onPressed: _recordingOrder ? null : _dismissUnplacedAttempt,
                child: const Text('I checked PandaMart: no order was placed'),
              ),
          ],
        ),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    if (widget.externalStore) return _buildExternalShopping();
    final adapter = _panda;
    return Scaffold(
      appBar: AppBar(
        leading: _setupAction == null
            ? null
            : IconButton(
                tooltip: 'Back to setup',
                onPressed: _leaveSetup,
                icon: const Icon(Icons.arrow_back),
              ),
        title: Text(
          _setupAction == 'login'
              ? 'Foodpanda sign-in'
              : _setupAction == 'store'
              ? 'Choose PandaMart'
              : _setupAction != null
              ? 'Delivery address'
              : 'PandaMart',
        ),
        actions: [
          PopupMenuButton<String>(
            tooltip: 'Shopping options',
            icon: const Icon(Icons.more_horiz_rounded),
            onSelected: (_) => _exportLog(),
            itemBuilder: (_) => const [
              PopupMenuItem(
                value: 'support',
                child: Text('Copy support details'),
              ),
            ],
          ),
          const SizedBox(width: 12),
        ],
      ),
      body: Column(
        children: [
          if (_setupAction == null &&
              (_running || _reviewing || _purchasing || _orderConfirmed))
            AppPageBody(
              maxWidth: 960,
              shrinkWrap: true,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
                child: Column(
                  children: [
                    _PurchasePhases(
                      current:
                          _orderConfirmed ||
                              _reviewing ||
                              _purchasing ||
                              _manualCheckoutStarted
                          ? 2
                          : _running || _results.isNotEmpty
                          ? 1
                          : 0,
                    ),
                    const SizedBox(height: 14),
                    SurfacePanel(
                      padding: const EdgeInsets.all(14),
                      child: Row(
                        children: [
                          if (_running ||
                              _loadingConfig ||
                              _purchasing ||
                              _recordingOrder ||
                              _refreshingCart)
                            const SizedBox.square(
                              dimension: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          else
                            Icon(
                              _orderConfirmed
                                  ? Icons.check_circle_outline_rounded
                                  : Icons.shopping_bag_outlined,
                              size: 19,
                              color: Theme.of(context).colorScheme.primary,
                            ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Tooltip(
                              message: _status,
                              child: Text(
                                _status,
                                maxLines: 3,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          Expanded(
            key: const ValueKey('pandamart-store-page'),
            child: Stack(
              children: [
                if (adapter != null)
                  InAppWebView(
                    key: const ValueKey('pandamart-webview'),
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
                      _pageGeneration++;
                      if (mounted && !_running && !_reviewing) {
                        setState(() => _pageReady = false);
                      }
                    },
                    onLoadStop: (_, _) => _handleStoreLoadStop(),
                    onUpdateVisitedHistory: (_, _, _) => _refreshPageState(),
                    onGeolocationPermissionsShowPrompt: (_, origin) =>
                        _handleGeolocationPrompt(origin),
                    onCreateWindow: (controller, action) async {
                      final value = action.request.url?.toString();
                      final uri = value == null ? null : Uri.tryParse(value);
                      final openerUrl = await controller.getUrl();
                      final opener = Uri.tryParse(openerUrl?.toString() ?? '');
                      if (!adapter.canOpenLoginPopup(
                            opener: opener,
                            target: uri,
                            hasGesture: action.hasGesture == true,
                          ) ||
                          _loginPopupWindowId != null) {
                        _log(
                          'navigation',
                          'Blocked untrusted popup host: ${uri?.host ?? 'unknown'}',
                        );
                        return false;
                      }
                      _log('navigation', 'Opening Foodpanda sign-in popup');
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
                if (_running || _purchasing)
                  const Positioned.fill(
                    child: AbsorbPointer(
                      child: ColoredBox(color: Colors.transparent),
                    ),
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
          if (_running)
            SafeArea(
              child: TextButton(
                onPressed: () => _continueManually(
                  'Adding stopped. Review any items already added.',
                ),
                child: const Text('Stop adding'),
              ),
            ),
          if (!_running &&
              !_reviewing &&
              !_purchasing &&
              !_recordingOrder &&
              _loginPopupWindowId == null)
            _buildControls(),
        ],
      ),
    );
  }

  Future<void> _leaveSetup() async {
    if (_setupAction != 'login' &&
        _setupAction != 'store' &&
        _controller != null &&
        _panda != null &&
        await _panda!.isAddressEntryOpen(_controller!)) {
      if (!mounted) return;
      final discard = await showDialog<bool>(
        context: context,
        builder: (dialog) => AlertDialog(
          title: const Text('Address is not confirmed'),
          content: const Text(
            'Choose an address suggestion and confirm the delivery pin to change your location.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialog, false),
              child: const Text('Keep editing'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(dialog, true),
              child: const Text('Discard changes'),
            ),
          ],
        ),
      );
      if (discard != true || !mounted) return;
      await _panda!.closeAddressEntry(_controller!);
    }
    if (!mounted) return;
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      _setupAction = null;
      _pendingSetupAction = null;
    });
    await _refreshPageState();
  }

  Widget _setupChip(String label, bool ready) => Chip(
    avatar: Icon(
      ready ? Icons.check_circle : Icons.circle_outlined,
      size: 16,
      color: ready
          ? Theme.of(context).colorScheme.primary
          : Theme.of(context).colorScheme.onSurfaceVariant,
    ),
    label: Text(label),
    visualDensity: VisualDensity.compact,
  );

  Future<void> _showSetupOptions() async {
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (sheet) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.location_on_outlined),
                title: const Text('Change delivery address'),
                onTap: () => Navigator.pop(sheet, 'address'),
              ),
              ListTile(
                leading: const Icon(Icons.my_location),
                title: const Text('Use current location'),
                onTap: () => Navigator.pop(sheet, 'location'),
              ),
              ListTile(
                leading: const Icon(Icons.storefront_outlined),
                title: const Text('Choose PandaMart'),
                enabled: _addressSelected,
                onTap: () => Navigator.pop(sheet, 'store'),
              ),
              ListTile(
                leading: const Icon(Icons.person_outline),
                title: Text(
                  _signedIn ? 'Signed in to Foodpanda' : 'Sign in to Foodpanda',
                ),
                enabled: !_signedIn,
                onTap: () => Navigator.pop(sheet, 'login'),
              ),
              StatefulBuilder(
                builder: (context, updateSheet) => SwitchListTile(
                  title: const Text('Allow equivalent substitutions'),
                  value: _allowSubstitutions,
                  onChanged: (value) {
                    setState(() => _allowSubstitutions = value);
                    updateSheet(() {});
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (!mounted || action == null) return;
    if (action == 'location') {
      await _useCurrentLocation();
    } else {
      await _openSetup(action);
    }
  }

  Widget _buildControls() {
    if (_setupAction != null || _recoveredAttempt) {
      return _buildDetailedControls();
    }
    if (_manual || _orderConfirmed) {
      return SafeArea(
        top: false,
        minimum: const EdgeInsets.fromLTRB(16, 4, 16, 8),
        child: Row(
          children: [
            Expanded(
              child: FilledButton(
                onPressed: _recordingOrder || _refreshingCart
                    ? null
                    : _orderConfirmed
                    ? _recordOrder
                    : _panda?.checkout.hasSubmitted == true
                    ? _checkOrderStatus
                    : _reviewCurrentCart,
                child: Text(
                  _orderConfirmed
                      ? 'Retry saving order'
                      : _panda?.checkout.hasSubmitted == true
                      ? 'Check order status'
                      : 'Review current cart',
                ),
              ),
            ),
            if (_manualCheckoutStarted && !_orderConfirmed) ...[
              const SizedBox(width: 8),
              IconButton(
                tooltip: 'Record confirmed order',
                onPressed: _confirmManualOrder,
                icon: const Icon(Icons.receipt_long_outlined),
              ),
            ],
            IconButton(
              tooltip: 'Shopping setup',
              onPressed: _showSetupOptions,
              icon: const Icon(Icons.tune),
            ),
          ],
        ),
      );
    }
    final nextAction = !_addressSelected
        ? 'address'
        : !_storeSelected
        ? 'store'
        : !_signedIn
        ? 'login'
        : null;
    final nextLabel = !_addressSelected
        ? 'Set delivery address'
        : !_storeSelected
        ? 'Choose nearby PandaMart'
        : !_signedIn
        ? 'Sign in to Foodpanda'
        : 'Review setup';
    return SafeArea(
      top: false,
      minimum: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  _selectedDeliveryAddress.isEmpty
                      ? 'Set up your delivery'
                      : _selectedDeliveryAddress.replaceFirst(
                          RegExp(r'^New\s*address\s*', caseSensitive: false),
                          '',
                        ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
              TextButton.icon(
                onPressed: _controller == null ? null : _showSetupOptions,
                icon: const Icon(Icons.tune, size: 18),
                label: const Text('Setup'),
              ),
            ],
          ),
          FilledButton(
            onPressed: _controller == null || _loadingConfig
                ? null
                : _pageReady
                ? _start
                : nextAction == null
                ? _showSetupOptions
                : () => _openSetup(nextAction),
            child: Text(_pageReady ? 'Build my cart' : nextLabel),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailedControls() {
    if (_setupAction != null) {
      if (MediaQuery.viewInsetsOf(context).bottom > 0) {
        return const SizedBox.shrink();
      }
      return SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _status,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall,
              ),
              Row(
                children: [
                  TextButton(
                    onPressed: _confirmingAddress ? null : _leaveSetup,
                    child: const Text('Back to setup'),
                  ),
                  if (_setupAction == 'address' ||
                      _setupAction == 'location') ...[
                    const SizedBox(width: 8),
                    Expanded(
                      child: FilledButton(
                        onPressed:
                            _confirmingAddress ||
                                _locating ||
                                !_addressCanConfirm
                            ? null
                            : _confirmDeliveryAddress,
                        child: Text(
                          _confirmingAddress
                              ? 'Confirming…'
                              : 'Confirm delivery address',
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      );
    }
    return SafeArea(
      child: AppPageBody(
        maxWidth: 880,
        shrinkWrap: true,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * .44,
          ),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 12, 24, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Set your delivery address, choose a nearby PandaMart, then sign in to Foodpanda. You will review the final cart before ordering.',
                  style: TextStyle(fontSize: 12),
                ),
                const SizedBox(height: 14),
                if (!_manual && !_orderConfirmed) ...[
                  if (_selectedDeliveryAddress.isNotEmpty) ...[
                    Text(
                      'Deliver to: $_selectedDeliveryAddress',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: 10),
                  ],
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _setupChip('Address', _addressSelected),
                      _setupChip('PandaMart', _storeSelected),
                      _setupChip('Sign-in', _signedIn),
                    ],
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: _controller == null || !_addressSelected
                        ? null
                        : () => _openSetup('store'),
                    icon: const Icon(Icons.storefront_outlined),
                    label: Text(
                      _storeSelected
                          ? 'Change PandaMart'
                          : 'Choose nearby PandaMart',
                    ),
                  ),
                  const SizedBox(height: 8),
                  FilledButton.icon(
                    onPressed: _controller == null
                        ? null
                        : () => _openSetup('address'),
                    icon: const Icon(Icons.location_on_outlined),
                    label: Text(
                      _addressSelected
                          ? 'Change delivery address'
                          : 'Set delivery address',
                    ),
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: _controller == null || _signedIn
                        ? null
                        : () => _openSetup('login'),
                    icon: Icon(
                      _signedIn
                          ? Icons.check_circle_outline
                          : Icons.person_outline,
                    ),
                    label: Text(
                      _signedIn
                          ? 'Signed in to Foodpanda'
                          : 'Sign in to Foodpanda',
                    ),
                  ),
                  TextButton.icon(
                    onPressed: _controller == null || _locating
                        ? null
                        : _useCurrentLocation,
                    icon: const Icon(Icons.my_location, size: 18),
                    label: Text(
                      _locating
                          ? 'Finding location...'
                          : 'Use current location',
                    ),
                  ),
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
                        : (value) => setState(
                            () => _allowSubstitutions = value ?? false,
                          ),
                    controlAffinity: ListTileControlAffinity.leading,
                  ),
                  FilledButton(
                    onPressed: _controller == null || !_pageReady
                        ? null
                        : _start,
                    child: const Text('Build my cart'),
                  ),
                ],
                if (_manual &&
                    !_orderConfirmed &&
                    !_recoveredAttempt &&
                    _panda?.checkout.hasSubmitted != true)
                  OutlinedButton(
                    onPressed: _refreshingCart ? null : _reviewCurrentCart,
                    child: const Text('Review current cart'),
                  ),
                if (_manual &&
                    !_orderConfirmed &&
                    _panda?.checkout.hasSubmitted == true)
                  OutlinedButton(
                    onPressed: _checkOrderStatus,
                    child: const Text('Check order status'),
                  ),
                if (_manual && _manualCheckoutStarted && !_orderConfirmed)
                  FilledButton(
                    onPressed: _confirmManualOrder,
                    child: const Text('I see PandaMart order confirmation'),
                  ),
                if (_orderConfirmed)
                  FilledButton(
                    onPressed: _recordOrder,
                    child: const Text('Retry saving order'),
                  ),
                if (!_orderConfirmed &&
                    (_recoveredAttempt ||
                        _panda?.checkout.hasSubmitted == true))
                  TextButton(
                    onPressed: _dismissUnplacedAttempt,
                    child: const Text(
                      'I checked PandaMart: no order was placed',
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildReview() => ColoredBox(
    color: Theme.of(context).scaffoldBackgroundColor,
    child: AppPageBody(
      maxWidth: 880,
      child: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 28),
              children: [
                const PageIntro(
                  eyebrow: 'BEFORE YOU CHECK OUT',
                  title: 'A last look at your cart.',
                  subtitle: 'Check the products and quantities before continuing to the store checkout.',
                ),
                const SizedBox(height: 26),
                FormSection(
                  title: 'Your shopping items',
                  children: [
                    for (final result in _results)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(
                          result.status == AddStatus.added
                              ? Icons.check_circle_outline_rounded
                              : Icons.info_outline_rounded,
                          size: 21,
                          color: result.status == AddStatus.added
                              ? Theme.of(context).colorScheme.primary
                              : Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                        title: Text(result.productName ?? result.wantedName),
                        subtitle: Text(
                          result.status == AddStatus.added
                              ? '${result.unitsAdded} × Rs ${result.unitPrice?.toStringAsFixed(2)}'
                              : '${result.reason} — kept on your shopping list',
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 18),
                FormSection(
                  title: 'In your PandaMart cart',
                  description: 'Includes anything already in the cart before we started.',
                  children: [
                    if (_cart.isEmpty)
                      Text(
                        'The cart could not be verified automatically.',
                        style: Theme.of(context).textTheme.bodyMedium,
                      )
                    else
                      for (final line in _cart)
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(line.name),
                          subtitle: Text('Quantity ${line.quantity}'),
                          trailing: Text('Rs ${line.price.toStringAsFixed(2)}'),
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
                    const SizedBox(height: 12),
                    const Divider(),
                    const SizedBox(height: 18),
                    Text(
                      _total == null
                          ? 'Cart total not verified'
                          : 'Cart total: Rs ${_total!.toStringAsFixed(2)}',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'The store will show the final amount, including any fees, before you approve the order.',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
                if (!_cartVerified) ...[
                  const SizedBox(height: 18),
                  const StatusNotice(
                    message: 'Check the cart items, quantities and total. Checkout becomes available once these are verified.',
                  ),
                ],
              ],
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 12, 24, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  FilledButton(
                    onPressed: _canPurchase ? _purchase : null,
                    child: _purchasing
                        ? SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Theme.of(context).colorScheme.onPrimary,
                            ),
                          )
                        : const Text('Continue to checkout'),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: TextButton(
                          onPressed: _purchasing || _refreshingCart
                              ? null
                              : () => setState(() {
                                  _reviewing = false;
                                  _manual = true;
                                  _manualCheckoutStarted = true;
                                  _status =
                                      'Edit and complete the cart manually';
                                }),
                          child: const Text('Edit cart in PandaMart'),
                        ),
                      ),
                      IconButton(
                        onPressed: _purchasing || _refreshingCart
                            ? null
                            : _reviewCurrentCart,
                        tooltip: 'Recheck cart',
                        icon: const Icon(Icons.refresh_rounded),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    ),
  );

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

class _PurchasePhases extends StatelessWidget {
  const _PurchasePhases({required this.current});
  final int current;
  @override
  Widget build(BuildContext context) => Row(
    children: [
      for (var index = 0; index < 3; index++)
        Expanded(
          child: Row(
            children: [
              Container(
                width: 24,
                height: 24,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: index <= current
                      ? Theme.of(context).colorScheme.primaryContainer
                      : Theme.of(context).colorScheme.surface,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: Theme.of(context).colorScheme.outlineVariant,
                  ),
                ),
                child: index < current
                    ? Icon(
                        Icons.check_rounded,
                        size: 13,
                        color: Theme.of(context).colorScheme.primary,
                      )
                    : Text(
                        '${index + 1}',
                        style: Theme.of(context).textTheme.labelSmall,
                      ),
              ),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  ['Set up', 'Build cart', 'Review & order'][index],
                  maxLines: 2,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: index == current
                        ? Theme.of(context).colorScheme.primary
                        : Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              if (index < 2) const SizedBox(width: 8),
            ],
          ),
        ),
    ],
  );
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
