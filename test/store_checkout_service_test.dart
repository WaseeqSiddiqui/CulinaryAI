import 'dart:async';

import 'package:culinary_ai/models/store_models.dart';
import 'package:culinary_ai/services/store_checkout_service.dart';
import 'package:flutter_test/flutter_test.dart';

const _cart = [CartLine(name: 'Fresh Milk 1L', quantity: 2, price: 600)];
CheckoutSummary _summary({
  double total = 675,
  String address = 'F-10 Islamabad',
  bool cash = true,
  List<CartLine> lines = _cart,
}) => CheckoutSummary(
  lines: lines,
  total: total,
  deliveryAddress: address,
  cashOnDeliverySelected: cash,
);

class _Page implements StoreCheckoutPage {
  bool opens = true;
  bool cashAvailable = true;
  bool confirmed = true;
  bool clickThrows = false;
  bool clickWorks = true;
  int submissions = 0;
  int opensCount = 0;
  String? interruption;
  CheckoutSummary? summary = _summary();

  @override
  Future<bool> openCheckout() async {
    opensCount++;
    return opens;
  }

  @override
  Future<String?> interruptionReason() async => interruption;
  @override
  Future<bool> selectCashOnDelivery() async => cashAvailable;
  @override
  Future<CheckoutSummary?> readSummary() async => summary;
  @override
  Future<bool> submitOrder() async {
    submissions++;
    if (clickThrows) throw StateError('connection lost after click');
    return clickWorks;
  }

  @override
  Future<bool> waitForConfirmation() async => confirmed;
  @override
  Future<String?> readOrderReference() async => 'panda-123';
}

void main() {
  late StoreCheckoutService service;
  late _Page page;
  setUp(() {
    service = StoreCheckoutService();
    page = _Page();
  });
  Future<CheckoutResult> run({
    CheckoutApproval? approve,
    Future<void> Function(CheckoutSummary)? beforeSubmit,
  }) => service.placeOrder(
    page: page,
    expectedCart: _cart,
    approve: approve ?? (_) async => true,
    beforeSubmit: beforeSubmit,
  );

  test('approves the final amount including fees and records merchant confirmation', () async {
    double? approvedTotal;
    final result = await run(
      approve: (summary) async {
        approvedTotal = summary.total;
        expect(summary.cashOnDeliverySelected, isTrue);
        expect(page.submissions, 0);
        return true;
      },
    );
    expect(result.state, CheckoutState.placed);
    expect(approvedTotal, 675);
    expect(result.summary?.total, 675);
    expect(result.orderReference, 'panda-123');
    expect(page.submissions, 1);
  });

  test('declining approval never submits', () async {
    expect(
      (await run(approve: (_) async => false)).state,
      CheckoutState.needsManualCompletion,
    );
    expect(page.submissions, 0);
    expect(service.hasSubmitted, isFalse);
  });

  test(
    'unavailable cash on delivery never falls back to a saved card',
    () async {
      page.cashAvailable = false;
      var approvals = 0;
      await run(
        approve: (_) async {
          approvals++;
          return true;
        },
      );
      expect(approvals, 0);
      expect(page.submissions, 0);
    },
  );

  for (final entry in <String, CheckoutSummary?>{
    'unreadable checkout': null,
    'missing address': _summary(address: ''),
    'saved card selected': _summary(cash: false),
    'zero total': _summary(total: 0),
    'infinite total': _summary(total: double.infinity),
    'empty cart': _summary(lines: []),
    'different product size': _summary(
      lines: [const CartLine(name: 'Fresh Milk 2L', quantity: 2, price: 600)],
    ),
  }.entries) {
    test('blocks ${entry.key}', () async {
      page.summary = entry.value;
      var approvals = 0;
      await run(
        approve: (_) async {
          approvals++;
          return true;
        },
      );
      expect(page.submissions, 0);
      expect(approvals, 0);
    });
  }

  for (final entry in <String, CheckoutSummary>{
    'price increase': _summary(total: 700),
    'price decrease': _summary(total: 650),
    'address change': _summary(address: 'Different address'),
    'payment change': _summary(cash: false),
    'quantity change': _summary(
      lines: [const CartLine(name: 'Fresh Milk 1L', quantity: 3, price: 900)],
    ),
  }.entries) {
    test('requires fresh approval after ${entry.key}', () async {
      final result = await run(
        approve: (_) async {
          page.summary = entry.value;
          return true;
        },
      );
      expect(result.state, CheckoutState.needsManualCompletion);
      expect(page.submissions, 0);
    });
  }

  test('interruption appearing after approval blocks submission', () async {
    await run(
      approve: (_) async {
        page.interruption = 'OTP required';
        return true;
      },
    );
    expect(page.submissions, 0);
  });

  test('failed recovery checkpoint blocks the final click', () async {
    await run(beforeSubmit: (_) async => throw StateError('disk full'));
    expect(page.submissions, 0);
    expect(service.hasSubmitted, isFalse);
  });

  test('checkpoint is durable before submission', () async {
    var saved = false;
    await run(
      beforeSubmit: (summary) async {
        expect(page.submissions, 0);
        expect(summary.total, 675);
        saved = true;
      },
    );
    expect(saved, isTrue);
    expect(page.submissions, 1);
  });

  test(
    'connection loss after click only permits confirmation checks on retry',
    () async {
      page.clickThrows = true;
      expect((await run()).state, CheckoutState.needsManualCompletion);
      expect(service.hasSubmitted, isTrue);
      expect((await run()).state, CheckoutState.placed);
      expect(page.submissions, 1);
      expect(page.opensCount, 1);
    },
  );

  test('confirmation timeout never triggers a second order', () async {
    page.confirmed = false;
    expect((await run()).state, CheckoutState.needsManualCompletion);
    expect((await run()).state, CheckoutState.needsManualCompletion);
    page.confirmed = true;
    expect((await run()).state, CheckoutState.placed);
    expect(page.submissions, 1);
  });

  test(
    'concurrent taps and cancellation while approving never submit',
    () async {
      final approval = Completer<bool>();
      final approving = Completer<void>();
      final first = run(
        approve: (_) {
          approving.complete();
          return approval.future;
        },
      );
      await approving.future;
      expect((await run()).state, CheckoutState.failed);
      service.cancel();
      approval.complete(true);
      expect((await first).state, CheckoutState.needsManualCompletion);
      expect(page.submissions, 0);
    },
  );

  test('exact cart comparison ignores order but retains duplicate quantities and prices', () {
    const eggs = CartLine(name: 'Eggs 6pcs', quantity: 1, price: 200);
    expect(
      StoreCheckoutService.sameCart([..._cart, eggs], [eggs, ..._cart]),
      isTrue,
    );
    expect(StoreCheckoutService.sameCart([..._cart, eggs], _cart), isFalse);
    expect(
      StoreCheckoutService.sameCart(_cart, [
        const CartLine(name: 'Fresh Milk 1L', quantity: 2, price: 601),
      ]),
      isFalse,
    );
  });
}
