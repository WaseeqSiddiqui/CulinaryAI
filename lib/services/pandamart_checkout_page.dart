import 'dart:convert';

import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../models/store_models.dart';
import 'pandamart_adapter.dart';
import 'store_checkout_service.dart';
import 'store_money_parser.dart';

/// Compatibility controls are matched by visible labels, never by button
/// position. An unrecognised checkout stays open for the user to complete.
class PandaMartCheckoutPage implements StoreCheckoutPage {
  PandaMartCheckoutPage({
    required this.controller,
    required this.adapter,
    required this.isActive,
  });

  final InAppWebViewController controller;
  final PandaMartAdapter adapter;
  final bool Function() isActive;
  String? _lastSignature;

  String get _helpers =>
      '''
    const visible = element => {
      if (!element) return false;
      const rect = element.getBoundingClientRect();
      const style = window.getComputedStyle(element);
      return rect.width > 0 && rect.height > 0 &&
        style.display !== 'none' && style.visibility !== 'hidden' &&
        Number(style.opacity || 1) !== 0;
    };
    const enabled = element => element && !element.disabled &&
      !element.closest('[aria-disabled="true"], [inert]');
    const text = element => (element?.textContent || element?.value || '')
      .replace(/\\s+/g, ' ').trim().toLowerCase();
    const findLabelled = (selector, labels) =>
      Array.from(document.querySelectorAll(selector)).find(element =>
        visible(element) && enabled(element) &&
        labels.includes(text(element)));
    const cashLabels = ${jsonEncode(adapter.config.list('cash_on_delivery_labels'))};
    const cashControl = () => {
      const option = findLabelled(${jsonEncode(adapter.config.value('cash_on_delivery'))}, cashLabels);
      if (!option) return null;
      const input = option.control || option.querySelector('input[type="radio"]') ||
        (option.matches('input[type="radio"], [role="radio"]') ? option : null);
      if (!input || !enabled(input)) return null;
      return { option, input };
    };
    const cashSelected = () => {
      const cash = cashControl();
      return Boolean(cash && (cash.input.checked === true ||
        cash.input.getAttribute('aria-checked') === 'true'));
    };
    const orderButton = () => findLabelled(
      ${jsonEncode(adapter.config.value('final_purchase_button'))},
      ${jsonEncode(adapter.config.list('final_purchase_labels'))});
    const confirmation = () => findLabelled(
      ${jsonEncode(adapter.config.value('order_confirmation'))},
      ${jsonEncode(adapter.config.list('order_confirmation_labels'))});
    const firstText = selector => Array.from(document.querySelectorAll(selector))
      .filter(visible).map(element => (element.textContent || '').trim())
      .find(value => value.length > 0) || '';
    const checkoutSnapshot = () => ({
      address: firstText(${jsonEncode(adapter.config.value('checkout_address'))}),
      total: firstText(${jsonEncode(adapter.config.value('checkout_total'))}),
      cashSelected: cashSelected(),
      ready: Boolean(orderButton()),
      lines: Array.from(document.querySelectorAll(${jsonEncode(adapter.config.value('cart_line'))}))
        .filter(visible).map(line => ({
          name: (line.querySelector(${jsonEncode(adapter.config.value('cart_line_name'))})?.textContent || '').trim(),
          quantityText: (line.querySelector(${jsonEncode(adapter.config.value('cart_line_quantity'))})?.textContent || '').trim(),
          priceText: (line.querySelector(${jsonEncode(adapter.config.value('cart_line_price'))})?.textContent || '').trim()
        }))
    });
  ''';

  Future<dynamic> _evaluate(String body) async {
    if (!isActive()) {
      throw const StoreAutomationException('Checkout cancelled.');
    }
    final url = await controller.getUrl();
    if (!isActive()) {
      throw const StoreAutomationException('Checkout cancelled.');
    }
    if (!adapter.isAllowedUri(
      url == null ? null : Uri.tryParse(url.toString()),
    )) {
      throw const StoreAutomationException(
        'Return to the secure PandaMart page.',
      );
    }
    return controller.evaluateJavascript(
      source: '(() => { $_helpers $body })()',
    );
  }

  Future<bool> _wait(Future<bool> Function() ready, Duration timeout) async {
    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      if (await ready()) return true;
      if (await interruptionReason() != null) return false;
      await Future<void>.delayed(const Duration(milliseconds: 250));
    }
    return false;
  }

  @override
  Future<bool> openCheckout() async {
    if (!adapter.canFinishCheckoutAutomatically) return false;
    if (await _evaluate('return Boolean(confirmation());') == true) {
      return false;
    }
    if (await _evaluate('return Boolean(cashControl() && orderButton());') ==
        true) {
      return true;
    }
    final clicked = await _evaluate('''
      const button = Array.from(document.querySelectorAll(
        ${jsonEncode(adapter.config.value('checkout_button'))}))
        .find(element => visible(element) && enabled(element));
      if (!button) return false;
      button.click(); return true;
    ''');
    if (clicked != true) return false;
    return _wait(
      () async =>
          await _evaluate('return Boolean(cashControl() || orderButton());') ==
          true,
      const Duration(seconds: 12),
    );
  }

  @override
  Future<String?> interruptionReason() =>
      adapter.interruptionReason(controller);

  @override
  Future<bool> selectCashOnDelivery() async {
    if (!await _wait(
      () async => await _evaluate('return Boolean(cashControl());') == true,
      const Duration(seconds: 8),
    )) {
      return false;
    }
    final clicked = await _evaluate('''
      const cash = cashControl();
      if (!cash) return false;
      if (!cashSelected()) cash.option.click();
      return true;
    ''');
    if (clicked != true) return false;
    return _wait(
      () async => await _evaluate('return cashSelected();') == true,
      const Duration(seconds: 8),
    );
  }

  @override
  Future<CheckoutSummary?> readSummary() async {
    _lastSignature = null;
    final raw = await _evaluate('''
      const snapshot = checkoutSnapshot();
      return { snapshot, signature: JSON.stringify(snapshot) };
    ''');
    if (raw is! Map || raw['snapshot'] is! Map || raw['signature'] is! String) {
      return null;
    }
    final result = raw['snapshot'] as Map;
    if (result['ready'] != true) return null;
    final rawLines = result['lines'];
    if (rawLines is! List || rawLines.isEmpty) return null;
    final lines = <CartLine>[];
    for (final line in rawLines) {
      if (line is! Map) return null;
      final quantity = int.tryParse(
        line['quantityText']?.toString().trim() ?? '',
      );
      final price = parseStoreMoney(line['priceText']?.toString());
      final name = line['name']?.toString().trim() ?? '';
      if (quantity == null ||
          quantity <= 0 ||
          price == null ||
          price < 0 ||
          name.isEmpty) {
        return null;
      }
      lines.add(CartLine(name: name, quantity: quantity, price: price));
    }
    final total = parseStoreMoney(result['total']?.toString());
    final address = result['address']?.toString() ?? '';
    if (total == null || !adapter.addressTextShowsSelection(address)) {
      return null;
    }
    _lastSignature = raw['signature'] as String;
    return CheckoutSummary(
      lines: lines,
      total: total,
      deliveryAddress: address,
      cashOnDeliverySelected: result['cashSelected'] == true,
    );
  }

  @override
  Future<bool> submitOrder() async =>
      await _evaluate('''
    const expected = ${jsonEncode(_lastSignature)};
    if (!expected || JSON.stringify(checkoutSnapshot()) !== expected || confirmation()) return false;
    const button = orderButton();
    if (!button || !cashSelected()) return false;
    button.click(); return true;
  ''') ==
      true;

  @override
  Future<bool> waitForConfirmation() => _wait(
    () async => await _evaluate('return Boolean(confirmation());') == true,
    const Duration(seconds: 30),
  );

  @override
  Future<String?> readOrderReference() async {
    final selector = adapter.config.value('order_reference');
    if (selector.isEmpty) return null;
    final result = await _evaluate('''
      if (!confirmation()) return null;
      const element = Array.from(document.querySelectorAll(${jsonEncode(selector)})).find(visible);
      return (element?.textContent || '').trim() || null;
    ''');
    return result?.toString();
  }
}
