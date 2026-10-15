import 'dart:convert';

import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../models/store_models.dart';
import 'store_adapter.dart';
import 'store_selector_config.dart';

class PandaMartAdapter implements StoreAdapter {
  PandaMartAdapter(this.config);

  final StoreSelectorConfig config;

  bool get isAutomationConfigured => config.hasAll([
    'logged_in',
    'search_input',
    'search_submit',
    'product_card',
    'product_name',
    'product_price',
    'product_out_of_stock',
    'product_add_button',
    'cart_line',
    'cart_line_name',
    'cart_line_quantity',
    'cart_line_price',
  ]);

  @override
  String get name => 'PandaMart';

  @override
  Uri get homeUrl => Uri.parse(config.homeUrl);

  String _quoted(String value) => jsonEncode(value);

  Future<dynamic> _js(InAppWebViewController controller, String source) =>
      controller.evaluateJavascript(source: source);

  @override
  Future<bool> isLoggedIn(InAppWebViewController controller) async {
    if (!config.hasAll(['logged_in'])) return false;
    return await _js(
          controller,
          'Boolean(document.querySelector(${_quoted(config.value('logged_in'))}))',
        ) ==
        true;
  }

  Future<bool> hasInterruption(InAppWebViewController controller) async {
    final selectors = [
      config.value('captcha'),
      config.value('otp_prompt'),
    ].where((value) => value.isNotEmpty).toList();
    if (selectors.isEmpty) return false;
    final expression = selectors
        .map((selector) => 'document.querySelector(${_quoted(selector)})')
        .join(' || ');
    return await _js(controller, 'Boolean($expression)') == true;
  }

  @override
  Future<List<ProductCandidate>> search(
    InAppWebViewController controller,
    String query,
  ) async {
    const keys = [
      'search_input',
      'search_submit',
      'product_card',
      'product_name',
      'product_price',
      'product_out_of_stock',
    ];
    if (!config.hasAll(keys) || await hasInterruption(controller)) return [];
    final input = _quoted(config.value('search_input'));
    final submit = _quoted(config.value('search_submit'));
    await _js(controller, '''
      (() => {
        const input = document.querySelector($input);
        if (!input) return false;
        input.focus();
        input.value = ${_quoted(query)};
        input.dispatchEvent(new Event('input', {bubbles: true}));
        input.dispatchEvent(new Event('change', {bubbles: true}));
        const submit = document.querySelector($submit);
        if (!submit) return false;
        submit.click();
        return true;
      })()
    ''');
    await Future<void>.delayed(const Duration(seconds: 2));
    final result = await _js(controller, '''
      (() => Array.from(document.querySelectorAll(${_quoted(config.value('product_card'))}))
        .slice(0, 8).map((card, index) => ({
          index,
          name: card.querySelector(${_quoted(config.value('product_name'))})?.textContent?.trim() || '',
          size: card.querySelector(${_quoted(config.value('product_size'))})?.textContent?.trim() || null,
          price: Number((card.querySelector(${_quoted(config.value('product_price'))})?.textContent || '')
            .replace(/[^0-9.]/g, '')) || 0,
          inStock: !card.querySelector(${_quoted(config.value('product_out_of_stock'))})
        })))()
    ''');
    if (result is! List) return [];
    return result
        .map((raw) {
          final map = Map<String, dynamic>.from(raw as Map);
          return ProductCandidate(
            name: map['name'] as String,
            size: map['size'] as String?,
            price: (map['price'] as num).toDouble(),
            inStock: map['inStock'] as bool,
            index: map['index'] as int,
          );
        })
        .where((item) => item.name.isNotEmpty)
        .toList();
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
    if (!config.hasAll(['product_card', 'product_add_button'])) {
      return const AddResult(
        AddStatus.failed,
        'PandaMart selectors are not configured',
      );
    }
    final added = await _js(controller, '''
      (() => {
        const card = document.querySelectorAll(${_quoted(config.value('product_card'))})[${candidate.index}];
        const button = card?.querySelector(${_quoted(config.value('product_add_button'))});
        if (!button) return false;
        for (let i = 0; i < $qty; i++) button.click();
        return true;
      })()
    ''');
    return added == true
        ? const AddResult(AddStatus.added, 'Added')
        : const AddResult(AddStatus.failed, 'Add button was not found');
  }

  @override
  Future<List<CartLine>> readCart(InAppWebViewController controller) async {
    const keys = [
      'cart_line',
      'cart_line_name',
      'cart_line_quantity',
      'cart_line_price',
    ];
    if (!config.hasAll(keys)) return [];
    final result = await _js(controller, '''
      (() => Array.from(document.querySelectorAll(${_quoted(config.value('cart_line'))})).map(line => ({
        name: line.querySelector(${_quoted(config.value('cart_line_name'))})?.textContent?.trim() || '',
        quantity: Number((line.querySelector(${_quoted(config.value('cart_line_quantity'))})?.textContent || '').replace(/[^0-9]/g, '')) || 1,
        price: Number((line.querySelector(${_quoted(config.value('cart_line_price'))})?.textContent || '').replace(/[^0-9.]/g, '')) || 0
      })))()
    ''');
    if (result is! List) return [];
    return result
        .map((raw) {
          final map = Map<String, dynamic>.from(raw as Map);
          return CartLine(
            name: map['name'] as String,
            quantity: (map['quantity'] as num).toInt(),
            price: (map['price'] as num).toDouble(),
          );
        })
        .where((line) => line.name.isNotEmpty)
        .toList();
  }

  @override
  Future<CheckoutResult> placeOrder(InAppWebViewController controller) async {
    const keys = [
      'checkout_button',
      'cash_on_delivery',
      'final_purchase_button',
    ];
    if (!config.hasAll(keys)) {
      return const CheckoutResult(
        CheckoutState.needsManualCompletion,
        'Checkout selectors are not configured. Complete checkout manually.',
      );
    }
    final clicked = await _js(controller, '''
      (() => {
        const checkout = document.querySelector(${_quoted(config.value('checkout_button'))});
        if (!checkout) return 'manual';
        checkout.click();
        return 'checkout';
      })()
    ''');
    if (clicked != 'checkout') {
      return const CheckoutResult(
        CheckoutState.needsManualCompletion,
        'Address or checkout details require manual completion.',
      );
    }
    await Future<void>.delayed(const Duration(seconds: 2));
    final placed = await _js(controller, '''
      (() => {
        const cod = document.querySelector(${_quoted(config.value('cash_on_delivery'))});
        const finalButton = document.querySelector(${_quoted(config.value('final_purchase_button'))});
        if (!cod || !finalButton) return false;
        cod.click();
        finalButton.click();
        return true;
      })()
    ''');
    return placed == true
        ? const CheckoutResult(CheckoutState.placed, 'Order submitted')
        : const CheckoutResult(
            CheckoutState.needsManualCompletion,
            'Complete address or payment selection manually.',
          );
  }
}
