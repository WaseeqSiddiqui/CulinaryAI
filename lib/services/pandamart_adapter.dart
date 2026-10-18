import 'dart:async';
import 'dart:convert';

import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../models/store_models.dart';
import 'store_adapter.dart';
import 'store_money_parser.dart';
import 'store_selector_config.dart';

class StoreAutomationException implements Exception {
  const StoreAutomationException(this.message, {this.selectorFailure = false});

  final String message;
  final bool selectorFailure;

  @override
  String toString() => message;
}

class PandaMartAdapter implements StoreAdapter {
  PandaMartAdapter(this.config);

  final StoreSelectorConfig config;
  int _actionGeneration = 0;
  int _searchNavigationSequence = 0;
  Uri? _activeStoreUri;

  double? lastCartTotal;
  bool lastCartReadWasVerified = false;

  bool get isAutomationConfigured => config.hasAll(const [
    'home_url',
    'search_path_template',
    'allowed_hosts',
    'logged_in',
    'logged_out',
    'search_results_ready',
    'no_search_results',
    'product_card',
    'product_name',
    'product_price',
    'product_out_of_stock',
    'product_add_button',
    'product_increment_button',
    'product_quantity',
  ]);

  bool get isCartVerificationConfigured => config.hasAll(const [
    'cart_container',
    'cart_open_button',
    'cart_line',
    'cart_line_name',
    'cart_line_quantity',
    'cart_line_price',
    'cart_total',
  ]);

  bool get canOpenCheckout => config.hasAll(const ['checkout_button']);

  bool get canFinishCheckoutAutomatically => config.hasAll(const [
    'checkout_button',
    'cash_on_delivery',
    'final_purchase_button',
    'order_confirmation',
  ]);

  @override
  String get name => 'PandaMart';

  @override
  Uri get homeUrl => Uri.parse(config.homeUrl);

  Uri? get activeStoreUri => _activeStoreUri;

  void cancelPendingActions() => _actionGeneration++;

  bool isAllowedUri(Uri? uri) {
    if (uri == null || uri.scheme != 'https') return false;
    final host = uri.host.toLowerCase();
    return config.list('allowed_hosts').any((allowed) {
      final normalized = allowed.toLowerCase();
      return host == normalized || host.endsWith('.$normalized');
    });
  }

  bool isExternalLoginUri(Uri? uri) {
    if (uri == null || uri.scheme != 'https') return false;
    final host = uri.host.toLowerCase();
    return config.list('external_login_hosts').any((allowed) {
      final normalized = allowed.toLowerCase();
      return host == normalized || host.endsWith('.$normalized');
    });
  }

  bool isStoreUri(Uri? uri) {
    if (!isAllowedUri(uri) || uri == null) return false;
    final marker = config.value('store_path_marker').trim().toLowerCase();
    return marker.isNotEmpty && uri.path.toLowerCase().contains(marker);
  }

  bool rememberStoreUri(Uri? uri) {
    if (!isStoreUri(uri) || uri == null) return false;
    final segments = uri.pathSegments;
    final darkstoreIndex = segments.indexWhere(
      (segment) => segment.toLowerCase() == 'darkstore',
    );
    if (darkstoreIndex < 0 || segments.length < darkstoreIndex + 3) {
      return false;
    }
    final baseSegments = segments.take(darkstoreIndex + 3).toList();
    _activeStoreUri = Uri(
      scheme: uri.scheme,
      host: uri.host,
      pathSegments: baseSegments,
    );
    return true;
  }

  Uri? searchUriFor(String query) {
    final store = _activeStoreUri;
    if (store == null) return null;
    final path = config
        .value('search_path_template')
        .replaceAll('{query}', Uri.encodeQueryComponent(query.trim()));
    return Uri.tryParse(
      '${store.toString().replaceFirst(RegExp(r'/$'), '')}/$path',
    );
  }

  Future<bool> hasActiveStore(InAppWebViewController controller) async {
    return rememberStoreUri(await _currentUri(controller));
  }

  Future<bool> clickLocateMe(InAppWebViewController controller) async {
    await _requireAllowedPage(controller);
    final selector = config.value('locate_me_button');
    final label = config.value('locate_me_text').trim().toLowerCase();
    if (selector.isEmpty || label.isEmpty) return false;
    final result = await _js(controller, '''
      (() => {
        const button = Array.from(document.querySelectorAll(${_quoted(selector)}))
          .find((candidate) => {
            const text = (candidate.textContent || '').trim().toLowerCase();
            const style = window.getComputedStyle(candidate);
            const rect = candidate.getBoundingClientRect();
            return text === ${_quoted(label)} &&
              style.display !== 'none' &&
              style.visibility !== 'hidden' &&
              rect.width > 0 && rect.height > 0;
          });
        if (!button || button.disabled) return false;
        button.click();
        return true;
      })()
    ''');
    return result == true;
  }

  String _quoted(String value) => jsonEncode(value);

  Future<dynamic> _js(InAppWebViewController controller, String source) =>
      controller.evaluateJavascript(source: source);

  Future<Uri?> _currentUri(InAppWebViewController controller) async {
    final url = await controller.getUrl();
    return url == null ? null : Uri.tryParse(url.toString());
  }

  Future<void> _requireAllowedPage(InAppWebViewController controller) async {
    final uri = await _currentUri(controller);
    if (!isAllowedUri(uri)) {
      throw StoreAutomationException(
        'PandaMart opened an unexpected page. Continue manually.',
      );
    }
  }

  Future<bool> _isVisible(
    InAppWebViewController controller,
    String selector,
  ) async {
    if (selector.trim().isEmpty) return false;
    final result = await _js(controller, '''
      (() => {
        const element = document.querySelector(${_quoted(selector)});
        if (!element) return false;
        const style = window.getComputedStyle(element);
        const rect = element.getBoundingClientRect();
        return style.display !== 'none' &&
          style.visibility !== 'hidden' &&
          Number(style.opacity || 1) !== 0 &&
          rect.width > 0 && rect.height > 0;
      })()
    ''');
    return result == true;
  }

  Future<String?> interruptionReason(InAppWebViewController controller) async {
    final uri = await _currentUri(controller);
    if (!isAllowedUri(uri)) return 'The store opened an unexpected page.';
    final bodyText = await _js(
      controller,
      "(document.body?.innerText || '').toLowerCase()",
    );
    final unavailableReason = unavailableReasonForText(
      bodyText is String ? bodyText : '',
    );
    if (unavailableReason != null) return unavailableReason;
    final addressPromptText = config.value('address_prompt_text').trim();
    if (addressPromptText.isNotEmpty) {
      final hasAddressPrompt = await _js(controller, '''
        (document.body?.innerText || '').toLowerCase().includes(
          ${_quoted(addressPromptText.toLowerCase())}
        )
      ''');
      if (hasAddressPrompt == true) {
        return 'Confirm your exact delivery location in Foodpanda.';
      }
    }
    if (await _isVisible(controller, config.value('captcha'))) {
      return 'PandaMart requires a captcha.';
    }
    if (await _isVisible(controller, config.value('otp_prompt'))) {
      return 'PandaMart requires an OTP.';
    }
    if (await _isVisible(controller, config.value('mobile_redirect_modal'))) {
      return 'PandaMart is asking to open its mobile app.';
    }
    if (await _isVisible(controller, config.value('address_prompt'))) {
      return 'Select your delivery address in PandaMart.';
    }
    return null;
  }

  String? unavailableReasonForText(String pageText) {
    final normalized = pageText.trim().toLowerCase();
    if (normalized.isEmpty) return null;
    for (final marker in config.list('store_unavailable_markers')) {
      if (normalized.contains(marker.toLowerCase())) {
        return 'This PandaMart branch is unavailable for the selected address.';
      }
    }
    return null;
  }

  Future<bool> hasInterruption(InAppWebViewController controller) async =>
      await interruptionReason(controller) != null;

  Future<bool> _waitForSelector(
    InAppWebViewController controller,
    String selector, {
    required Duration timeout,
    required int generation,
  }) async {
    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      if (generation != _actionGeneration) return false;
      await _requireAllowedPage(controller);
      final exists = await _js(
        controller,
        'Boolean(document.querySelector(${_quoted(selector)}))',
      );
      if (exists == true) return true;
      await Future<void>.delayed(const Duration(milliseconds: 250));
    }
    return false;
  }

  @override
  Future<bool> isLoggedIn(InAppWebViewController controller) async {
    await _requireAllowedPage(controller);
    if (await _isVisible(controller, config.value('logged_out'))) return false;
    return _isVisible(controller, config.value('logged_in'));
  }

  Future<bool> hasSelectedAddress(InAppWebViewController controller) async {
    await _requireAllowedPage(controller);
    final selector = config.value('address_label');
    if (selector.trim().isEmpty) return false;
    final value = await _js(controller, '''
      (() => {
        const element = document.querySelector(${_quoted(selector)});
        return element ? (element.textContent || '').trim() : '';
      })()
    ''');
    return addressTextShowsSelection(value?.toString() ?? '');
  }

  bool addressTextShowsSelection(String value) {
    final address = value.trim();
    if (address.isEmpty) return false;
    final normalizedAddress = address.toLowerCase();
    if (config
        .list('address_unselected_markers')
        .any((marker) => normalizedAddress.contains(marker.toLowerCase()))) {
      return false;
    }
    final unselected = config.value('address_unselected_text').trim();
    if (unselected.isEmpty) return true;
    final selectedPart = address.replaceFirst(
      RegExp(RegExp.escape(unselected), caseSensitive: false),
      '',
    );
    if (selectedPart.trim().isEmpty) return false;
    final requiredMarkers = config.list('address_required_markers');
    return requiredMarkers.isEmpty ||
        requiredMarkers.any(
          (marker) => normalizedAddress.contains(marker.toLowerCase()),
        );
  }

  bool searchUriMatches(Uri? uri, String query) {
    if (!isAllowedUri(uri) || uri == null) return false;
    if (!uri.path.toLowerCase().endsWith('/search')) return false;
    final actual = uri.queryParameters['q']?.trim().toLowerCase();
    return actual == query.trim().toLowerCase();
  }

  Future<bool> _waitForSearchResults(
    InAppWebViewController controller,
    String query, {
    required Duration timeout,
    required int generation,
    required String navigationToken,
  }) async {
    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      if (generation != _actionGeneration) return false;
      final uri = await _currentUri(controller);
      if (!isAllowedUri(uri)) {
        throw const StoreAutomationException(
          'PandaMart opened an unexpected search page.',
          selectorFailure: true,
        );
      }
      if (searchUriMatches(uri, query)) {
        final ready = await _js(controller, '''
          window.__culinarySearchNavigation !== ${_quoted(navigationToken)} &&
          document.readyState !== 'loading' &&
          Boolean(document.querySelector(${_quoted(config.value('search_results_ready'))}))
        ''');
        if (ready == true) return true;
      }
      await Future<void>.delayed(const Duration(milliseconds: 250));
    }
    return false;
  }

  @override
  Future<List<ProductCandidate>> search(
    InAppWebViewController controller,
    String query,
  ) async {
    if (!isAutomationConfigured) {
      throw const StoreAutomationException(
        'PandaMart search selectors are incomplete.',
        selectorFailure: true,
      );
    }
    await _requireAllowedPage(controller);
    rememberStoreUri(await _currentUri(controller));
    final generation = _actionGeneration;
    final uri = searchUriFor(query);
    if (uri == null) {
      throw const StoreAutomationException(
        'Choose a PandaMart that delivers to your selected address first.',
      );
    }
    if (!isAllowedUri(uri)) {
      throw const StoreAutomationException(
        'The configured PandaMart search URL is not allowed.',
        selectorFailure: true,
      );
    }

    // Mark the current document before navigating. The URL can change before
    // Foodpanda replaces the old DOM, so URL + selector checks alone can read
    // the previous item's cards. A full navigation creates a new window and
    // clears this marker.
    final navigationToken =
        'culinary-${++_searchNavigationSequence}-${DateTime.now().microsecondsSinceEpoch}';
    await _js(
      controller,
      'window.__culinarySearchNavigation = ${_quoted(navigationToken)}; true;',
    );
    await controller.loadUrl(
      urlRequest: URLRequest(url: WebUri(uri.toString())),
    );
    final ready = await _waitForSearchResults(
      controller,
      query,
      timeout: const Duration(seconds: 12),
      generation: generation,
      navigationToken: navigationToken,
    );
    if (!ready) {
      if (generation != _actionGeneration) {
        throw const StoreAutomationException('Automation was cancelled.');
      }
      final interruption = await interruptionReason(controller);
      if (interruption != null) throw StoreAutomationException(interruption);
      throw const StoreAutomationException(
        'PandaMart search results did not load.',
        selectorFailure: true,
      );
    }
    if (await _isVisible(controller, config.value('no_search_results'))) {
      return const [];
    }

    final sizeSelector = config.value('product_size');
    final sizeExpression = sizeSelector.isEmpty
        ? 'null'
        : '''card.querySelector(${_quoted(sizeSelector)})?.textContent?.trim() || null''';
    final result = await _js(controller, '''
      (() => Array.from(document.querySelectorAll(${_quoted(config.value('product_card'))}))
        .slice(0, 8)
        .map((card, index) => ({
          index,
          storeId: card.getAttribute('data-id') || card.getAttribute('data-testid'),
          name: card.querySelector(${_quoted(config.value('product_name'))})?.textContent?.trim() || '',
          size: $sizeExpression,
          priceText: card.querySelector(${_quoted(config.value('product_price'))})?.textContent?.trim() || '',
          inStock: !card.querySelector(${_quoted(config.value('product_out_of_stock'))})
        })))()
    ''');
    if (result is! List) {
      throw const StoreAutomationException(
        'PandaMart returned an unreadable product list.',
        selectorFailure: true,
      );
    }

    return result.indexed
        .map((entry) {
          final raw = entry.$2;
          if (raw is! Map) return null;
          final map = Map<String, dynamic>.from(raw);
          final price = parseStoreMoney(map['priceText']?.toString());
          final name = map['name']?.toString().trim() ?? '';
          if (name.isEmpty || price == null || price <= 0) return null;
          return ProductCandidate(
            name: name,
            size: map['size']?.toString(),
            price: price,
            inStock: map['inStock'] == true,
            index: (map['index'] as num?)?.toInt() ?? entry.$1,
            storeId: map['storeId']?.toString(),
          );
        })
        .whereType<ProductCandidate>()
        .toList(growable: false);
  }

  String _cardLookup(ProductCandidate candidate) =>
      '''
    const cards = Array.from(document.querySelectorAll(${_quoted(config.value('product_card'))}));
    const stableId = ${jsonEncode(candidate.storeId)};
    const card = stableId
      ? cards.find((entry) =>
          entry.getAttribute('data-id') === stableId ||
          entry.getAttribute('data-testid') === stableId)
      : cards[${candidate.index}];
  ''';

  Future<int> _readProductQuantity(
    InAppWebViewController controller,
    ProductCandidate candidate,
  ) async {
    final result = await _js(controller, '''
      (() => {
        ${_cardLookup(candidate)}
        if (!card) return -1;
        const quantity = card.querySelector(${_quoted(config.value('product_quantity'))});
        if (!quantity) return 0;
        const match = (quantity.textContent || '').match(/[0-9]+/);
        return match ? Number(match[0]) : 0;
      })()
    ''');
    return (result as num?)?.toInt() ?? -1;
  }

  Future<bool> _clickNextQuantity(
    InAppWebViewController controller,
    ProductCandidate candidate,
    int currentQuantity,
  ) async {
    final result = await _js(controller, '''
      (() => {
        ${_cardLookup(candidate)}
        if (!card) return false;
        const selector = ${currentQuantity <= 0 ? _quoted(config.value('product_add_button')) : _quoted(config.value('product_increment_button'))};
        const button = card.querySelector(selector);
        if (!button || button.disabled) return false;
        const rect = button.getBoundingClientRect();
        if (rect.width <= 0 || rect.height <= 0) return false;
        button.click();
        return true;
      })()
    ''');
    return result == true;
  }

  @override
  Future<AddResult> addToCart(
    InAppWebViewController controller,
    ProductCandidate candidate,
    int qty,
  ) async {
    if (!candidate.inStock) {
      return const AddResult(AddStatus.outOfStock, 'Product is out of stock');
    }
    if (qty < 1 || qty > 10) {
      return const AddResult(AddStatus.failed, 'Quantity must be from 1 to 10');
    }
    await _requireAllowedPage(controller);
    final generation = _actionGeneration;
    final baseline = await _readProductQuantity(controller, candidate);
    if (baseline < 0) {
      return const AddResult(
        AddStatus.failed,
        'The selected PandaMart product is no longer visible',
      );
    }
    final target = baseline + qty;
    var current = baseline;
    while (current < target) {
      if (generation != _actionGeneration) {
        return const AddResult(AddStatus.failed, 'Automation was cancelled');
      }
      final interruption = await interruptionReason(controller);
      if (interruption != null) {
        return AddResult(AddStatus.failed, interruption);
      }
      if (!await _clickNextQuantity(controller, candidate, current)) {
        return const AddResult(
          AddStatus.failed,
          'PandaMart quantity control was not found',
        );
      }

      final deadline = DateTime.now().add(const Duration(seconds: 4));
      var updated = current;
      while (DateTime.now().isBefore(deadline)) {
        if (generation != _actionGeneration) {
          return const AddResult(AddStatus.failed, 'Automation was cancelled');
        }
        await Future<void>.delayed(const Duration(milliseconds: 250));
        updated = await _readProductQuantity(controller, candidate);
        if (updated > current) break;
      }
      if (updated <= current) {
        return const AddResult(
          AddStatus.failed,
          'PandaMart did not confirm the quantity change',
        );
      }
      current = updated;
    }
    return AddResult(
      AddStatus.added,
      'Added and verified at quantity $current',
    );
  }

  @override
  Future<List<CartLine>> readCart(InAppWebViewController controller) async {
    lastCartReadWasVerified = false;
    lastCartTotal = null;
    if (!isCartVerificationConfigured) {
      throw const StoreAutomationException(
        'Cart selectors still need verification from a live filled cart.',
        selectorFailure: true,
      );
    }
    await _requireAllowedPage(controller);
    if (!await _isVisible(controller, config.value('cart_container'))) {
      final opened = await _clickVisibleSelector(
        controller,
        config.value('cart_open_button'),
      );
      if (!opened ||
          !await _waitForVisibleSelector(
            controller,
            config.value('cart_container'),
            timeout: const Duration(seconds: 8),
            generation: _actionGeneration,
          )) {
        throw const StoreAutomationException(
          'PandaMart cart could not be opened for verification.',
          selectorFailure: true,
        );
      }
    }
    final result = await _js(controller, '''
      (() => Array.from(document.querySelectorAll(${_quoted(config.value('cart_line'))}))
        .map((line) => ({
          storeId: line.getAttribute('data-id') || line.getAttribute('data-testid'),
          name: line.querySelector(${_quoted(config.value('cart_line_name'))})?.textContent?.trim() || '',
          quantityText: line.querySelector(${_quoted(config.value('cart_line_quantity'))})?.textContent?.trim() || '',
          priceText: line.querySelector(${_quoted(config.value('cart_line_price'))})?.textContent?.trim() || ''
        })))()
    ''');
    if (result is! List) {
      throw const StoreAutomationException(
        'PandaMart cart could not be read.',
        selectorFailure: true,
      );
    }

    final lines = result
        .map((raw) {
          if (raw is! Map) return null;
          final map = Map<String, dynamic>.from(raw);
          final name = map['name']?.toString().trim() ?? '';
          final quantityMatch = RegExp(r'\d+')
              .firstMatch(map['quantityText']?.toString() ?? '');
          final quantity = int.tryParse(quantityMatch?.group(0) ?? '') ?? 0;
          final price = parseStoreMoney(map['priceText']?.toString());
          if (name.isEmpty || quantity <= 0 || price == null) return null;
          return CartLine(
            name: name,
            quantity: quantity,
            price: price,
            storeId: map['storeId']?.toString(),
          );
        })
        .whereType<CartLine>()
        .toList(growable: false);

    final totalText = await _js(controller, '''
      document.querySelector(${_quoted(config.value('cart_total'))})?.textContent?.trim() || ''
    ''');
    lastCartTotal = parseStoreMoney(totalText?.toString());
    if (lastCartTotal == null) {
      throw const StoreAutomationException(
        'PandaMart cart total could not be verified.',
        selectorFailure: true,
      );
    }
    lastCartReadWasVerified = true;
    return lines;
  }

  Future<bool> _waitForVisibleSelector(
    InAppWebViewController controller,
    String selector, {
    required Duration timeout,
    required int generation,
  }) async {
    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      if (generation != _actionGeneration) return false;
      await _requireAllowedPage(controller);
      if (await _isVisible(controller, selector)) return true;
      await Future<void>.delayed(const Duration(milliseconds: 250));
    }
    return false;
  }

  Future<bool> _clickVisibleSelector(
    InAppWebViewController controller,
    String selector,
  ) async {
    if (selector.isEmpty) return false;
    final result = await _js(controller, '''
      (() => {
        const button = Array.from(document.querySelectorAll(${_quoted(selector)}))
          .find((candidate) => {
            const style = window.getComputedStyle(candidate);
            const rect = candidate.getBoundingClientRect();
            return style.display !== 'none' &&
              style.visibility !== 'hidden' &&
              Number(style.opacity || 1) !== 0 &&
              rect.width > 0 && rect.height > 0;
          });
        if (!button || button.disabled) return false;
        button.click();
        return true;
      })()
    ''');
    return result == true;
  }

  @override
  Future<CheckoutResult> placeOrder(InAppWebViewController controller) async {
    await _requireAllowedPage(controller);
    if (!canOpenCheckout) {
      return const CheckoutResult(
        CheckoutState.needsManualCompletion,
        'Open and complete PandaMart checkout manually.',
      );
    }
    if (!await _clickVisibleSelector(
      controller,
      config.value('checkout_button'),
    )) {
      return const CheckoutResult(
        CheckoutState.needsManualCompletion,
        'The checkout button is not ready. Check the address and minimum order.',
      );
    }

    await Future<void>.delayed(const Duration(seconds: 2));
    final interruption = await interruptionReason(controller);
    if (interruption != null) {
      return CheckoutResult(
        CheckoutState.needsManualCompletion,
        '$interruption Complete checkout manually.',
      );
    }
    if (!canFinishCheckoutAutomatically) {
      return const CheckoutResult(
        CheckoutState.needsManualCompletion,
        'Checkout is open. Choose the address and cash on delivery manually.',
      );
    }

    if (!await _clickVisibleSelector(
      controller,
      config.value('cash_on_delivery'),
    )) {
      return const CheckoutResult(
        CheckoutState.needsManualCompletion,
        'Cash on delivery is unavailable. Finish checkout manually.',
      );
    }
    if (!await _clickVisibleSelector(
      controller,
      config.value('final_purchase_button'),
    )) {
      return const CheckoutResult(
        CheckoutState.needsManualCompletion,
        'The final order button is not ready. Finish checkout manually.',
      );
    }

    final confirmed = await _waitForSelector(
      controller,
      config.value('order_confirmation'),
      timeout: const Duration(seconds: 30),
      generation: _actionGeneration,
    );
    return confirmed
        ? const CheckoutResult(
            CheckoutState.placed,
            'PandaMart confirmed the order',
          )
        : const CheckoutResult(
            CheckoutState.needsManualCompletion,
            'PandaMart has not confirmed the order yet. Verify it manually.',
          );
  }
}
