import 'dart:convert';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../models/household_model.dart';
import 'firebase_service.dart';

class HouseholdService {
  static const _localKey = 'culinary_households';
  static const _uuid = Uuid();
  static const _codeCharacters = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';

  final FirebaseFirestore? _firestore = FirebaseService.isInitialized
      ? FirebaseFirestore.instance
      : null;

  Future<List<HouseholdModel>> _loadLocalHouseholds() async {
    final preferences = await SharedPreferences.getInstance();
    final encoded = preferences.getString(_localKey);
    if (encoded == null) return [];
    try {
      final records = jsonDecode(encoded) as List<dynamic>;
      return records.map((record) {
        final map = Map<String, dynamic>.from(record as Map);
        return HouseholdModel.fromMap(map, map['id'] as String);
      }).toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> _saveLocalHousehold(HouseholdModel household) async {
    final preferences = await SharedPreferences.getInstance();
    final households = await _loadLocalHouseholds();
    final index = households.indexWhere((item) => item.id == household.id);
    if (index == -1) {
      households.add(household);
    } else {
      households[index] = household;
    }
    await preferences.setString(
      _localKey,
      jsonEncode(households.map((item) => item.toMap()).toList()),
    );
  }

  Future<HouseholdModel?> loadForUser(
    String userId, {
    String? householdId,
  }) async {
    final local = await _loadLocalHouseholds();
    HouseholdModel? localMatch;
    for (final household in local) {
      if (household.id == householdId || household.memberIds.contains(userId)) {
        localMatch = household;
        break;
      }
    }

    final firestore = _firestore;
    if (firestore == null) return localMatch;
    try {
      DocumentSnapshot<Map<String, dynamic>>? document;
      if (householdId != null && householdId.isNotEmpty) {
        final candidate = await firestore
            .collection('households')
            .doc(householdId)
            .get();
        if (candidate.exists) document = candidate;
      }
      if (document == null) {
        final query = await firestore
            .collection('households')
            .where('member_ids', arrayContains: userId)
            .limit(1)
            .get();
        if (query.docs.isNotEmpty) document = query.docs.first;
      }
      final data = document?.data();
      if (document == null || data == null) return localMatch;
      final household = HouseholdModel.fromMap(data, document.id);
      await _saveLocalHousehold(household);
      return household;
    } on FirebaseException catch (error) {
      if (kDebugMode) {
        debugPrint('Household load using offline copy: ${error.code}');
      }
      return localMatch;
    }
  }

  Future<HouseholdModel> create({
    required String name,
    required String userId,
  }) async {
    final cleanName = name.trim();
    if (cleanName.isEmpty) throw 'Enter a household name.';
    final household = HouseholdModel(
      id: _uuid.v4(),
      name: cleanName,
      ownerId: userId,
      memberIds: [userId],
      inviteCode: _generateInviteCode(),
      createdAt: DateTime.now(),
    );

    final firestore = _firestore;
    if (firestore != null) {
      try {
        final batch = firestore.batch();
        batch.set(
          firestore.collection('households').doc(household.id),
          household.toMap(),
        );
        batch.set(
          firestore.collection('household_invites').doc(household.inviteCode),
          {
            'household_id': household.id,
            'owner_id': userId,
            'created_at': household.createdAt.toIso8601String(),
          },
        );
        batch.set(firestore.collection('users').doc(userId), {
          'household_id': household.id,
        }, SetOptions(merge: true));
        await batch.commit();
      } on FirebaseException catch (error) {
        if (kDebugMode) {
          debugPrint('Household created offline: ${error.code}');
        }
      }
    }
    await _saveLocalHousehold(household);
    return household;
  }

  Future<HouseholdModel> join({
    required String inviteCode,
    required String userId,
  }) async {
    final cleanCode = inviteCode.trim().toUpperCase();
    if (cleanCode.length != 6) throw 'Enter the 6-character invite code.';

    final local = await _loadLocalHouseholds();
    HouseholdModel? household;
    for (final candidate in local) {
      if (candidate.inviteCode.toUpperCase() == cleanCode) {
        household = candidate;
        break;
      }
    }

    final firestore = _firestore;
    if (firestore != null) {
      try {
        final invite = await firestore
            .collection('household_invites')
            .doc(cleanCode)
            .get();
        final householdId = invite.data()?['household_id'] as String?;
        if (householdId != null) {
          final reference = firestore.collection('households').doc(householdId);
          await reference.update({
            'member_ids': FieldValue.arrayUnion([userId]),
          });
          final document = await reference.get();
          final data = document.data();
          if (data == null) throw 'That household is no longer available.';
          household = HouseholdModel.fromMap(data, document.id);
          await firestore.collection('users').doc(userId).set({
            'household_id': household.id,
          }, SetOptions(merge: true));
        }
      } on FirebaseException catch (error) {
        if (household == null) {
          throw 'Could not check that invite code. Please check your connection.';
        }
        if (kDebugMode) {
          debugPrint('Household joined offline: ${error.code}');
        }
      }
    }

    if (household == null) throw 'No household matches that invite code.';
    final updated = HouseholdModel(
      id: household.id,
      name: household.name,
      ownerId: household.ownerId,
      memberIds: {...household.memberIds, userId}.toList(),
      inviteCode: household.inviteCode,
      createdAt: household.createdAt,
    );
    await _saveLocalHousehold(updated);
    return updated;
  }

  String _generateInviteCode() {
    final random = Random.secure();
    return List.generate(
      6,
      (_) => _codeCharacters[random.nextInt(_codeCharacters.length)],
    ).join();
  }
}
