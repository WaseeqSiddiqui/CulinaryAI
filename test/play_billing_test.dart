import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:culinary_ai/services/play_billing_service.dart';
import 'package:culinary_ai/services/subscription_api_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:in_app_purchase/in_app_purchase.dart';

class FakeApi extends SubscriptionApiService {
  bool enabled = true, fail = false;
  int verified = 0;
  Completer<void>? gate;
  @override
  Future<Map<String, dynamic>> billingConfiguration() async => {
    'checkout_enabled': enabled,
    'product_id': plusProductId,
    'base_plan_id': plusBasePlanId,
  };
  @override
  Future<SubscriptionStatus> verifyPlayPurchase(String purchaseToken) async {
    verified++;
    if (gate != null) await gate!.future;
    if (fail) throw Exception('Verification temporarily unavailable.');
    return SubscriptionStatus(
      plan: 'plus',
      chatUsed: 7,
      photoUsed: 2,
      chatLimit: 500,
      photoLimit: 50,
      resetsAt: DateTime.utc(2026, 12),
    );
  }
}

class FakeStore implements PlayStore {
  final events = StreamController<List<PurchaseDetails>>.broadcast();
  String? buyer;
  int completions = 0;
  final product = ProductDetails(
    id: plusProductId,
    title: 'Plus',
    description: 'Monthly',
    price: 'Rs 999.00',
    rawPrice: 999,
    currencyCode: 'PKR',
  );
  @override
  Stream<List<PurchaseDetails>> get updates => events.stream;
  @override
  Future<bool> available() async => true;
  @override
  Future<ProductDetails?> monthlyProduct() async => product;
  @override
  Future<bool> buy(ProductDetails product, String accountId) async {
    buyer = accountId;
    return true;
  }

  @override
  Future<void> restore(String accountId) async =>
      events.add([purchase(PurchaseStatus.restored)]);
  @override
  Future<void> complete(PurchaseDetails purchase) async {
    completions++;
  }
}

PurchaseDetails purchase(PurchaseStatus status) => PurchaseDetails(
  productID: plusProductId,
  verificationData: PurchaseVerificationData(
    localVerificationData: '',
    serverVerificationData: 'private-purchase-token',
    source: 'google_play',
  ),
  transactionDate: null,
  status: status,
)..pendingCompletePurchase = true;

Future<void> drain() async {
  for (var i = 0; i < 8; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  late FakeApi api;
  late FakeStore store;
  late PlayBillingController billing;
  String? uid;
  setUp(() {
    api = FakeApi();
    store = FakeStore();
    uid = 'alice';
    billing = PlayBillingController(
      store: store,
      api: api,
      currentUid: () => uid,
      supported: true,
    );
  });
  tearDown(() async {
    billing.dispose();
    api.close();
    await store.events.close();
  });

  test('checkout uses store price and hashed Firebase identity; no local Plus grant', () async {
    await billing.load();
    expect(billing.product!.price, 'Rs 999.00');
    await billing.purchase();
    expect(store.buyer, sha256.convert(utf8.encode('alice')).toString());
    expect(billing.verifiedStatus, isNull);
    expect(api.verified, 0);
  });

  test('pending and canceled payments never verify or complete', () async {
    store.events.add([
      purchase(PurchaseStatus.pending),
      purchase(PurchaseStatus.canceled),
    ]);
    await drain();
    expect(api.verified, 0);
    expect(store.completions, 0);
    expect(billing.verifiedStatus, isNull);
    expect(billing.busy, false);
  });

  test(
    'verification failure keeps purchase incomplete and retryable',
    () async {
      api.fail = true;
      store.events.add([purchase(PurchaseStatus.purchased)]);
      await drain();
      expect(store.completions, 0);
      expect(billing.verifiedStatus, isNull);
      expect(billing.canRetry, true);
      api.fail = false;
      await billing.retryVerification();
      expect(store.completions, 1);
      expect(billing.verifiedStatus!.plan, 'plus');
      expect(billing.canRetry, false);
    },
  );

  test('restore verifies with backend before completing', () async {
    await billing.restore();
    await drain();
    expect(api.verified, 1);
    expect(store.completions, 1);
    expect(billing.verifiedStatus!.chatUsed, 7);
  });

  test('disabled checkout and signed-out users cannot start payment', () async {
    api.enabled = false;
    await billing.load();
    await billing.purchase();
    expect(billing.canBuy, false);
    expect(store.buyer, isNull);
    api.enabled = true;
    uid = null;
    await billing.load();
    await billing.purchase();
    expect(store.buyer, isNull);
    expect(billing.message, contains('Sign in'));
  });

  test(
    'switching accounts while verifying does not display the other users Plus',
    () async {
      api.gate = Completer<void>();
      store.events.add([purchase(PurchaseStatus.purchased)]);
      await drain();
      uid = 'bob';
      api.gate!.complete();
      await drain();
      expect(billing.verifiedStatus, isNull);
    },
  );
}
