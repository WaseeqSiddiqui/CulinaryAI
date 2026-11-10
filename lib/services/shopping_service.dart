import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/shopping_models.dart';
import 'firebase_service.dart';

class ShoppingService {
  final FirebaseFirestore? _firestore = FirebaseService.isInitialized
      ? FirebaseFirestore.instance
      : null;

  String _listKey(String householdId) => 'culinary_shopping_list_$householdId';
  String _ordersKey(String householdId) => 'culinary_orders_$householdId';
  String _suppressedPantryKey(String householdId) =>
      'culinary_shopping_suppressed_pantry_$householdId';

  Future<bool> hasSavedList(String householdId) async =>
      (await SharedPreferences.getInstance()).containsKey(
        _listKey(householdId),
      );

  Future<List<ShoppingListItem>> loadList(String householdId) async {
    final encoded = (await SharedPreferences.getInstance()).getString(
      _listKey(householdId),
    );
    if (encoded == null) return [];
    try {
      return (jsonDecode(encoded) as List<dynamic>)
          .map(
            (item) => ShoppingListItem.fromMap(
              Map<String, dynamic>.from(item as Map),
            ),
          )
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> saveList(
    String householdId,
    List<ShoppingListItem> items,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final saved = await prefs.setString(
      _listKey(householdId),
      jsonEncode(items.map((item) => item.toMap()).toList()),
    );
    if (!saved) throw StateError('The shopping list could not be saved.');
  }

  Future<Set<String>> loadSuppressedPantryIds(String householdId) async {
    final prefs = await SharedPreferences.getInstance();
    return (prefs.getStringList(_suppressedPantryKey(householdId)) ?? const [])
        .toSet();
  }

  Future<void> saveSuppressedPantryIds(
    String householdId,
    Set<String> ids,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final sortedIds = ids.toList()..sort();
    if (!await prefs.setStringList(
      _suppressedPantryKey(householdId),
      sortedIds,
    )) {
      throw StateError('Pending restock items could not be saved.');
    }
  }

  Future<void> createOrder(ShoppingOrder order) async {
    final prefs = await SharedPreferences.getInstance();
    final key = _ordersKey(order.householdId);
    final existing = prefs.getString(key);
    final orders = existing == null
        ? <dynamic>[]
        : jsonDecode(existing) as List<dynamic>;
    final index = orders.indexWhere(
      (entry) => entry is Map && entry['id'] == order.id,
    );
    if (index < 0) {
      orders.add(order.toMap());
    }
    final savedOrder = index < 0
        ? order.toMap()
        : Map<String, dynamic>.from(orders[index] as Map);
    if (!await prefs.setString(key, jsonEncode(orders))) {
      throw StateError('The order could not be saved on this device.');
    }

    if (_firestore != null) {
      try {
        await _firestore
            .collection('households')
            .doc(order.householdId)
            .collection('orders')
            .doc(order.id)
            .set(savedOrder);
      } on FirebaseException catch (error) {
        if (kDebugMode) {
          debugPrint('Order retained locally: ${error.code}');
        }
      }
    }
  }

  Future<List<ShoppingOrder>> loadOrders(String householdId) async {
    final encoded = (await SharedPreferences.getInstance()).getString(
      _ordersKey(householdId),
    );
    if (encoded == null) return [];
    return (jsonDecode(encoded) as List<dynamic>)
        .map(
          (entry) =>
              ShoppingOrder.fromMap(Map<String, dynamic>.from(entry as Map)),
        )
        .toList()
      ..sort((left, right) => right.createdAt.compareTo(left.createdAt));
  }
}
