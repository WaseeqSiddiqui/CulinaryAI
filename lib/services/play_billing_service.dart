import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:in_app_purchase_android/in_app_purchase_android.dart';

import 'firebase_service.dart';
import 'subscription_api_service.dart';

const plusProductId = 'culinary_plus_monthly';
const plusBasePlanId = 'monthly';

abstract class PlayStore {
  Stream<List<PurchaseDetails>> get updates;
  Future<bool> available();
  Future<ProductDetails?> monthlyProduct();
  Future<bool> buy(ProductDetails product, String accountId);
  Future<void> restore(String accountId);
  Future<void> complete(PurchaseDetails purchase);
}

class GooglePlayStore implements PlayStore {
  final _store = InAppPurchase.instance;
  @override
  Stream<List<PurchaseDetails>> get updates => _store.purchaseStream;
  @override
  Future<bool> available() => _store.isAvailable();
  @override
  Future<ProductDetails?> monthlyProduct() async {
    final response = await _store.queryProductDetails({plusProductId});
    if (response.error != null) {
      throw Exception('Google Play could not load the subscription.');
    }
    for (final product
        in response.productDetails.whereType<GooglePlayProductDetails>()) {
      final index = product.subscriptionIndex;
      final offers = product.productDetails.subscriptionOfferDetails;
      if (index == null || offers == null || index >= offers.length) continue;
      final offer = offers[index];
      if (offer.basePlanId == plusBasePlanId && offer.offerId == null) {
        return product;
      }
    }
    return null;
  }

  @override
  Future<bool> buy(ProductDetails product, String accountId) =>
      _store.buyNonConsumable(
        purchaseParam: GooglePlayPurchaseParam(
          productDetails: product,
          applicationUserName: accountId,
          offerToken: product is GooglePlayProductDetails
              ? product.offerToken
              : null,
        ),
      );
  @override
  Future<void> restore(String accountId) =>
      _store.restorePurchases(applicationUserName: accountId);
  @override
  Future<void> complete(PurchaseDetails purchase) =>
      _store.completePurchase(purchase);
}

/// The store UI collects payment. Only the verified backend grants Plus access.
class PlayBillingController extends ChangeNotifier {
  PlayBillingController({
    PlayStore? store,
    SubscriptionApiService? api,
    String? Function()? currentUid,
    bool? supported,
  }) : _supported =
           supported ??
           (!kIsWeb &&
               defaultTargetPlatform == TargetPlatform.android &&
               FirebaseService.isInitialized),
       _api = api ?? SubscriptionApiService(),
       _ownsApi = api == null,
       _currentUid = currentUid ?? _firebaseUid {
    if (_supported) {
      _store = store ?? GooglePlayStore();
      _subscription = _store!.updates.listen(
        (purchases) {
          _queue = _queue.then((_) => _handle(purchases));
        },
        onError: (_) {
          busy = false;
          message =
              'Google Play could not finish checkout. Try Restore purchases.';
          _notify();
        },
      );
    }
  }
  final bool _supported, _ownsApi;
  final SubscriptionApiService _api;
  final String? Function() _currentUid;
  PlayStore? _store;
  StreamSubscription<List<PurchaseDetails>>? _subscription;
  Future<void> _queue = Future.value();
  final Map<String, PurchaseDetails> _retryable = {};
  ProductDetails? product;
  bool loading = false, busy = false, checkoutEnabled = false;
  bool pendingPayment = false;
  bool _disposed = false;
  String? message;
  SubscriptionStatus? _verifiedStatus;
  String? _verifiedUid;
  SubscriptionStatus? get verifiedStatus =>
      _verifiedUid == _currentUid() ? _verifiedStatus : null;
  bool get canBuy =>
      !loading &&
      !busy &&
      !pendingPayment &&
      checkoutEnabled &&
      product != null;
  bool get canRestore => _supported && !busy;
  bool get canRetry => _retryable.isNotEmpty && !busy;

  static String? _firebaseUid() => FirebaseService.isInitialized
      ? FirebaseAuth.instance.currentUser?.uid
      : null;
  void _notify() {
    if (!_disposed) notifyListeners();
  }

  Future<void> load() async {
    if (loading) return;
    loading = true;
    product = null;
    message = null;
    _notify();
    try {
      if (!_supported) {
        message =
            'Subscribe through the Android app installed from Google Play.';
        return;
      }
      final config = await _api.billingConfiguration();
      checkoutEnabled =
          config['checkout_enabled'] == true &&
          config['product_id'] == plusProductId &&
          config['base_plan_id'] == plusBasePlanId;
      if (!checkoutEnabled) {
        message = 'Google Play subscriptions are not available yet.';
      } else if (!await _store!.available()) {
        message = 'Google Play is unavailable. Open the app installed from Google Play and try again.';
      } else {
        product = await _store!.monthlyProduct();
        if (product == null) message = 'The monthly subscription is currently unavailable on Google Play.';
      }
    } catch (_) {
      message = 'Google Play could not load checkout. Please try again.';
    } finally {
      loading = false;
      _notify();
    }
  }

  String? _account() {
    final uid = _currentUid();
    if (uid == null) {
      message = 'Sign in before purchasing or restoring Plus.';
      _notify();
      return null;
    }
    return sha256.convert(utf8.encode(uid)).toString();
  }

  Future<void> purchase() async {
    if (!canBuy) return;
    final account = _account();
    if (account == null) return;
    busy = true;
    message = 'Finish checkout in Google Play.';
    _notify();
    try {
      if (!await _store!.buy(product!, account)) {
        busy = false;
        message = 'Checkout did not start. Please try again.';
      }
    } catch (_) {
      busy = false;
      message = 'Checkout could not start. Try Restore purchases if you already paid.';
    }
    _notify();
  }

  Future<void> restore() async {
    if (!canRestore) return;
    final account = _account();
    if (account == null) return;
    busy = true;
    message = 'Checking Google Play purchases...';
    _notify();
    try {
      await _store!.restore(account);
      await _queue;
      if (message == 'Checking Google Play purchases...') {
        message = 'Restore finished. No active Plus purchase was found for this account.';
      }
    } catch (_) {
      message = 'Purchases could not be restored. Please try again.';
    } finally {
      busy = false;
      _notify();
    }
  }

  Future<void> retryVerification() async {
    if (!canRetry) return;
    await _handle(_retryable.values.toList());
  }

  Future<void> _handle(List<PurchaseDetails> purchases) async {
    for (final purchase in purchases) {
      if (purchase.productID != plusProductId) continue;
      if (purchase.status == PurchaseStatus.pending) {
        pendingPayment = true;
        busy =
            false; // A pending wallet/card payment must not lock this screen.
        message = 'Payment is pending with Google Play. Plus activates after confirmation.';
        _notify();
        continue;
      }
      if (purchase.status == PurchaseStatus.canceled ||
          purchase.status == PurchaseStatus.error) {
        pendingPayment = false;
        busy = false;
        message = purchase.status == PurchaseStatus.canceled
            ? 'Checkout canceled.'
            : 'Google Play could not complete payment. Try Restore purchases if you paid.';
        _notify();
        continue;
      }
      if (purchase.status != PurchaseStatus.purchased &&
          purchase.status != PurchaseStatus.restored) {
        continue;
      }
      final token = purchase.verificationData.serverVerificationData;
      pendingPayment = false;
      busy = true;
      message = 'Verifying your subscription...';
      _notify();
      try {
        if (_currentUid() == null || token.isEmpty) {
          throw Exception('Sign in to verify your purchase.');
        }
        final uid = _currentUid();
        final status = await _api.verifyPlayPurchase(token);
        if (status.plan == 'plus' && purchase.pendingCompletePurchase) {
          await _store!.complete(purchase);
        }
        _retryable.remove(token);
        _verifiedStatus = status;
        _verifiedUid = uid;
        message = status.plan == 'plus'
            ? 'Plus is active. Thank you!'
            : 'Purchase checked. No active Plus subscription was found.';
      } catch (error) {
        _retryable[token] = purchase;
        message = error.toString().replaceFirst('Exception: ', '');
      } finally {
        busy = false;
        _notify();
      }
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _subscription?.cancel();
    if (_ownsApi) _api.close();
    super.dispose();
  }
}
