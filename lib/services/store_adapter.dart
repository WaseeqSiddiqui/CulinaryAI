import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../models/store_models.dart';

abstract class StoreAdapter {
  String get name;
  Uri get homeUrl;
  Future<bool> isLoggedIn(InAppWebViewController controller);
  Future<List<ProductCandidate>> search(
    InAppWebViewController controller,
    String query,
  );
  Future<AddResult> addToCart(
    InAppWebViewController controller,
    ProductCandidate candidate,
    int qty,
  );
  Future<List<CartLine>> readCart(InAppWebViewController controller);
  Future<CheckoutResult> placeOrder(InAppWebViewController controller);
}
