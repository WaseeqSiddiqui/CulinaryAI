import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'firebase_service.dart';

class HouseholdAliasService {
  final FirebaseFirestore? _firestore = FirebaseService.isInitialized
      ? FirebaseFirestore.instance
      : null;

  String _localKey(String householdId) => 'culinary_aliases_$householdId';

  Future<Map<String, String>> getAliases(String householdId) async {
    final prefs = await SharedPreferences.getInstance();
    final cached = prefs.getString(_localKey(householdId));
    final result = <String, String>{};

    if (cached != null) {
      try {
        final decoded = jsonDecode(cached) as Map<String, dynamic>;
        for (final entry in decoded.entries) {
          result[entry.key.toLowerCase().trim()] = entry.value.toString();
        }
      } catch (_) {}
    }

    if (_firestore != null) {
      try {
        final snapshot = await _firestore
            .collection('households')
            .doc(householdId)
            .collection('aliases')
            .get();
        for (final doc in snapshot.docs) {
          final data = doc.data();
          final raw = data['raw_text']?.toString().toLowerCase().trim();
          final target = data['ingredient_name']?.toString();
          if (raw != null && target != null && raw.isNotEmpty) {
            result[raw] = target;
          }
        }
        await prefs.setString(_localKey(householdId), jsonEncode(result));
      } catch (e) {
        if (kDebugMode) {
          debugPrint('Could not fetch remote aliases: $e');
        }
      }
    }

    return result;
  }

  Future<void> saveAlias(
    String householdId,
    String rawText,
    String ingredientName,
  ) async {
    final cleanedRaw = rawText.toLowerCase().trim();
    final cleanedTarget = ingredientName.trim();
    if (cleanedRaw.isEmpty || cleanedTarget.isEmpty) return;

    // Save locally
    final prefs = await SharedPreferences.getInstance();
    final current = await getAliases(householdId);
    current[cleanedRaw] = cleanedTarget;
    await prefs.setString(_localKey(householdId), jsonEncode(current));

    // Save to Firestore if available
    if (_firestore != null) {
      try {
        // Use a safe document ID
        final docId = cleanedRaw.replaceAll(RegExp(r'[^a-zA-Z0-9_]'), '_');
        await _firestore
            .collection('households')
            .doc(householdId)
            .collection('aliases')
            .doc(docId)
            .set({
              'raw_text': cleanedRaw,
              'ingredient_name': cleanedTarget,
              'updated_at': DateTime.now().toIso8601String(),
            });
      } catch (e) {
        if (kDebugMode) {
          debugPrint('Failed to save alias to Firestore: $e');
        }
      }
    }
  }
}
