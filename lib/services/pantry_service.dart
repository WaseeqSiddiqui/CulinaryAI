import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/pantry_item_model.dart';
import 'firebase_service.dart';

class PantryStockDeduction {
  final String itemId;
  final double amount;
  final String unit;

  const PantryStockDeduction({
    required this.itemId,
    required this.amount,
    required this.unit,
  });
}

class PantryConcurrencyException implements Exception {
  final String message;
  const PantryConcurrencyException(this.message);
  @override
  String toString() => message;
}

class PantryService {
  final FirebaseFirestore? _firestore = FirebaseService.isInitialized
      ? FirebaseFirestore.instance
      : null;

  bool get supportsCloudSync => _firestore != null;

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

  Future<void> recordLedgerEvent(
    String householdId,
    Map<String, dynamic> event, {
    bool syncRemote = true,
  }) async {
    // 1. Save to local preferences
    final prefs = await SharedPreferences.getInstance();
    final cacheKey = 'culinary_ledger_$householdId';
    final existingJson = prefs.getString(cacheKey);
    final list = existingJson != null
        ? (jsonDecode(existingJson) as List<dynamic>)
              .cast<Map<String, dynamic>>()
        : <Map<String, dynamic>>[];
    list.add(event);
    await prefs.setString(cacheKey, jsonEncode(list));

    // 2. Save to Firestore if available
    if (_firestore != null && syncRemote) {
      try {
        final eventId =
            event['id'] as String? ??
            DateTime.now().millisecondsSinceEpoch.toString();
        await _firestore
            .collection('households')
            .doc(householdId)
            .collection('ledger')
            .doc(eventId)
            .set(event);
      } on FirebaseException catch (error) {
        if (kDebugMode) {
          debugPrint('Ledger event queued locally: ${error.code}');
        }
      }
    }
  }

  Future<List<Map<String, dynamic>>> loadLocalLedger(String householdId) async {
    final prefs = await SharedPreferences.getInstance();
    final encoded = prefs.getString('culinary_ledger_$householdId');
    if (encoded == null) return [];
    try {
      return (jsonDecode(encoded) as List<dynamic>)
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .toList();
    } catch (_) {
      return [];
    }
  }

  /// Applies all shared-pantry deductions in one Firestore transaction. The
  /// transaction rereads current stock and rejects stale or negative updates.
  Future<void> consumeAtomically({
    required String householdId,
    required List<PantryStockDeduction> deductions,
    required Map<String, dynamic> ledgerEvent,
  }) async {
    if (deductions.isEmpty) return;
    final firestore = _firestore;
    if (firestore == null) return;
    try {
      await firestore.runTransaction((transaction) async {
        final references = [
          for (final deduction in deductions)
            firestore
                .collection('households')
                .doc(householdId)
                .collection('pantry')
                .doc(deduction.itemId),
        ];
        final snapshots = <DocumentSnapshot<Map<String, dynamic>>>[];
        for (final reference in references) {
          snapshots.add(await transaction.get(reference));
        }
        final nextQuantities = <double>[];
        final openedDates = <Object?>[];
        for (var index = 0; index < deductions.length; index++) {
          final deduction = deductions[index];
          final snapshot = snapshots[index];
          final data = snapshot.data();
          if (!snapshot.exists || data == null) {
            throw const PantryConcurrencyException(
              'A pantry item was removed by another household member.',
            );
          }
          final current = (data['quantity'] as num?)?.toDouble() ?? 0;
          final currentUnit = data['unit']?.toString() ?? '';
          if (currentUnit.toLowerCase() != deduction.unit.toLowerCase()) {
            throw const PantryConcurrencyException(
              'A pantry unit changed. Review the latest inventory and retry.',
            );
          }
          if (deduction.amount < 0 || current + 0.000001 < deduction.amount) {
            throw const PantryConcurrencyException(
              'Stock changed while cooking. Review the available quantity.',
            );
          }
          nextQuantities.add(current - deduction.amount);
          openedDates.add(
            data['opened_date'] ?? DateTime.now().toIso8601String(),
          );
        }
        for (var index = 0; index < references.length; index++) {
          transaction.update(references[index], {
            'quantity': nextQuantities[index],
            'remaining_quantity': nextQuantities[index],
            'opened_date': openedDates[index],
            'package_status': 'opened',
            'updated_at': DateTime.now().toIso8601String(),
          });
        }
        final eventId = ledgerEvent['id'] as String;
        final ledgerReference = firestore
            .collection('households')
            .doc(householdId)
            .collection('ledger')
            .doc(eventId);
        transaction.set(ledgerReference, ledgerEvent);
      });
    } on PantryConcurrencyException {
      rethrow;
    } on FirebaseException catch (error) {
      throw PantryConcurrencyException(
        'Could not safely update the shared pantry (${error.code}). Try again online.',
      );
    }
  }
}
