import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/shopping_models.dart';

/// A durable receipt of a submission attempt. Resuming an interrupted screen
/// requires checking the merchant's order status, never resubmitting the cart.
class PurchaseSession {
  const PurchaseSession({
    required this.id,
    required this.householdId,
    required this.items,
    required this.total,
    required this.confirmed,
    this.storeOrderReference,
  });

  final String id;
  final String householdId;
  final List<ShoppingListItem> items;
  final double total;
  final bool confirmed;
  final String? storeOrderReference;

  Map<String, dynamic> toMap() => {
    'id': id,
    'householdId': householdId,
    'items': items.map((item) => item.toMap()).toList(),
    'total': total,
    'confirmed': confirmed,
    'storeOrderReference': storeOrderReference,
  };

  factory PurchaseSession.fromMap(Map<String, dynamic> map) => PurchaseSession(
    id: map['id'] as String,
    householdId: map['householdId'] as String,
    items: (map['items'] as List)
        .map(
          (item) =>
              ShoppingListItem.fromMap(Map<String, dynamic>.from(item as Map)),
        )
        .toList(),
    total: (map['total'] as num).toDouble(),
    confirmed: map['confirmed'] == true,
    storeOrderReference: map['storeOrderReference'] as String?,
  );
}

class PurchaseSessionStore {
  String _key(String householdId) => 'culinary_pandamart_checkout_$householdId';

  Future<PurchaseSession?> load(String householdId) async {
    final raw = (await SharedPreferences.getInstance()).getString(
      _key(householdId),
    );
    if (raw == null) return null;
    // Do not silently discard a corrupt checkpoint and enable another purchase.
    return PurchaseSession.fromMap(
      Map<String, dynamic>.from(jsonDecode(raw) as Map),
    );
  }

  Future<void> save(PurchaseSession session) async {
    if (!await (await SharedPreferences.getInstance()).setString(
      _key(session.householdId),
      jsonEncode(session.toMap()),
    )) {
      throw StateError('Could not save checkout recovery information.');
    }
  }

  Future<void> clear(String householdId) async {
    if (!await (await SharedPreferences.getInstance()).remove(
      _key(householdId),
    )) {
      throw StateError('Could not finish saving checkout.');
    }
  }
}
