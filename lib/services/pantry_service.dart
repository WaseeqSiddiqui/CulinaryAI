import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/pantry_item_model.dart';
import 'firebase_service.dart';

class PantryService {
  final FirebaseFirestore? _firestore = FirebaseService.isInitialized
      ? FirebaseFirestore.instance
      : null;

  String _cacheKey(String householdId) => 'culinary_pantry_$householdId';

  CollectionReference<Map<String, dynamic>>? _items(String householdId) =>
      _firestore
          ?.collection('households')
          .doc(householdId)
          .collection('pantry');

  Future<List<PantryItemModel>> loadLocal(String householdId) async {
    final preferences = await SharedPreferences.getInstance();
    final encoded = preferences.getString(_cacheKey(householdId));
    if (encoded == null) return [];
    try {
      final records = jsonDecode(encoded) as List<dynamic>;
      return records.map((record) {
        final map = Map<String, dynamic>.from(record as Map);
        return PantryItemModel.fromMap(map, map['id'] as String);
      }).toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> saveLocal(
    String householdId,
    List<PantryItemModel> items,
  ) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(
      _cacheKey(householdId),
      jsonEncode(items.map((item) => item.toMap()).toList()),
    );
  }

  Stream<List<PantryItemModel>> watch(String householdId) {
    final collection = _items(householdId);
    if (collection == null) return const Stream.empty();
    return collection.snapshots().map(
      (snapshot) => snapshot.docs
          .map(
            (document) => PantryItemModel.fromMap(document.data(), document.id),
          )
          .toList(),
    );
  }

  Future<void> upsert(PantryItemModel item) async {
    final collection = _items(item.householdId);
    if (collection == null) return;
    try {
      await collection.doc(item.id).set(item.toMap());
    } on FirebaseException catch (error) {
      if (kDebugMode) {
        debugPrint('Pantry write queued locally: ${error.code}');
      }
    }
  }

  Future<void> delete(String householdId, String itemId) async {
    final collection = _items(householdId);
    if (collection == null) return;
    try {
      await collection.doc(itemId).delete();
    } on FirebaseException catch (error) {
      if (kDebugMode) {
        debugPrint('Pantry delete kept locally: ${error.code}');
      }
    }
  }
}
