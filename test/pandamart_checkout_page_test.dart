import 'dart:convert';
import 'dart:io';

import 'package:culinary_ai/services/pandamart_adapter.dart';
import 'package:culinary_ai/services/pandamart_checkout_page.dart';
import 'package:culinary_ai/services/store_selector_config.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_test/flutter_test.dart';

class _Controller implements InAppWebViewController {
  WebUri? url = WebUri('https://www.foodpanda.pk/checkout');
  final List<String> scripts = [];
  dynamic response;

  @override
  Future<WebUri?> getUrl() async => url;

  @override
  Future<dynamic> evaluateJavascript({
    required String source,
    ContentWorld? contentWorld,
  }) async {
    scripts.add(source);
    return response;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  final root =
      jsonDecode(File('assets/store_selectors.json').readAsStringSync()) as Map;
  final config = StoreSelectorConfig(
    Map<String, String>.from(root['pandamart'] as Map),
  );
  late _Controller controller;
  late PandaMartCheckoutPage page;
  var active = true;

  Map<String, dynamic> snapshot({
    String quantity = '2',
    String price = 'Rs. 600',
    String address = 'F-10 Islamabad',
    String total = 'Rs. 675',
  }) => {
    'signature': 'fixture-signature',
    'snapshot': {
      'ready': true,
      'cashSelected': true,
      'address': address,
      'total': total,
      'lines': [
        {'name': 'Fresh Milk 1L', 'quantityText': quantity, 'priceText': price},
      ],
    },
  };

  setUp(() {
    active = true;
    controller = _Controller()..response = snapshot();
    page = PandaMartCheckoutPage(
      controller: controller,
      adapter: PandaMartAdapter(config),
      isActive: () => active,
    );
  });

  test('checkout compatibility controls are fully configured', () {
    expect(PandaMartAdapter(config).canFinishCheckoutAutomatically, isTrue);
  });

  test('parses a complete WebView checkout snapshot', () async {
    final summary = await page.readSummary();
    expect(summary?.isComplete, isTrue);
    expect(summary?.lines.single.quantity, 2);
    expect(summary?.total, 675);
    expect(summary?.deliveryAddress, 'F-10 Islamabad');
  });

  for (final entry in <String, Map<String, dynamic>>{
    'unreadable quantity': snapshot(quantity: 'unknown'),
    'zero quantity': snapshot(quantity: '0'),
    'missing line price': snapshot(price: ''),
    'ambiguous line price': snapshot(price: 'Rs 500 Rs 600'),
    'missing address': snapshot(address: ''),
    'unselected address': snapshot(address: 'New address'),
    'missing final total': snapshot(total: ''),
  }.entries) {
    test('refuses ${entry.key}', () async {
      controller.response = entry.value;
      expect(await page.readSummary(), isNull);
    });
  }

  test(
    'rejects a partial cart rather than discarding an unreadable line',
    () async {
      final raw = snapshot();
      ((raw['snapshot'] as Map)['lines'] as List).add({
        'name': 'Eggs',
        'quantityText': '1',
        'priceText': '',
      });
      controller.response = raw;
      expect(await page.readSummary(), isNull);
    },
  );

  test(
    'blocked hosts and cancellation stop JavaScript before it can click',
    () async {
      controller.url = WebUri('https://foodpanda.pk.attacker.example/checkout');
      await expectLater(
        page.submitOrder(),
        throwsA(isA<StoreAutomationException>()),
      );
      expect(controller.scripts, isEmpty);
      controller.url = WebUri('https://www.foodpanda.pk/checkout');
      active = false;
      await expectLater(
        page.submitOrder(),
        throwsA(isA<StoreAutomationException>()),
      );
      expect(controller.scripts, isEmpty);
    },
  );
}
