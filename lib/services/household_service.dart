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
    final preferences = await SharedPreferences.getInstance();
    final selectedId = preferences.getString(
      'culinary_selected_household_$userId',
    );
    final preferredId = selectedId ?? householdId;
    final local = await _loadLocalHouseholds();
    HouseholdModel? localMatch;
    for (final household in local) {
      if (household.id == preferredId) {
        localMatch = household;
        break;
      }
    }
    if (localMatch == null) {
      for (final household in local) {
        if (household.memberIds.contains(userId)) {
          localMatch = household;
          break;
        }
      }
    }

    final firestore = _firestore;
    if (firestore == null) return localMatch;
    try {
      DocumentSnapshot<Map<String, dynamic>>? document;
      if (preferredId != null && preferredId.isNotEmpty) {
        final candidate = await firestore
            .collection('households')
            .doc(preferredId)
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

  Future<List<HouseholdModel>> loadAllForUser(String userId) async {
    final byId = <String, HouseholdModel>{
      for (final household in await _loadLocalHouseholds())
        if (household.memberIds.contains(userId)) household.id: household,
    };
    final firestore = _firestore;
    if (firestore != null) {
      try {
        final query = await firestore
            .collection('households')
            .where('member_ids', arrayContains: userId)
            .get();
        for (final document in query.docs) {
          final household = HouseholdModel.fromMap(document.data(), document.id);
          byId[household.id] = household;
          await _saveLocalHousehold(household);
        }
      } on FirebaseException catch (error) {
        if (kDebugMode) {
          debugPrint('Household list using offline copy: ${error.code}');
        }
      }
    }
    return byId.values.toList()
      ..sort((left, right) => left.name.compareTo(right.name));
  }

  Future<void> select({
    required String householdId,
    required String userId,
  }) async {
    final households = await loadAllForUser(userId);
    if (!households.any((household) => household.id == householdId)) {
      throw 'You are not a member of that household.';
    }
    await _rememberSelection(userId, householdId);
    final firestore = _firestore;
    if (firestore != null) {
      try {
        await firestore.collection('users').doc(userId).set({
          'household_id': householdId,
        }, SetOptions(merge: true));
      } on FirebaseException catch (error) {
        throw 'Could not switch households (${error.code}).';
      }
    }
  }

  Future<HouseholdModel> create({
    required String name,
    required String userId,
  }) async {
    final cleanName = name.trim();
    if (cleanName.isEmpty) throw 'Enter a household name.';
    final now = DateTime.now();
    final inviteExpiresAt = now.add(const Duration(days: 7));
    final household = HouseholdModel(
      id: _uuid.v4(),
      name: cleanName,
      ownerId: userId,
      memberIds: [userId],
      memberRoles: {userId: 'owner'},
      inviteCode: _generateInviteCode(),
      inviteExpiresAt: inviteExpiresAt,
      createdAt: now,
      updatedAt: now,
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
            'created_at': Timestamp.fromDate(household.createdAt),
            'expires_at': Timestamp.fromDate(inviteExpiresAt),
          },
        );
        batch.set(firestore.collection('users').doc(userId), {
          'household_id': household.id,
        }, SetOptions(merge: true));
        await batch.commit();
      } on FirebaseException catch (error) {
        throw 'Could not create the shared household (${error.code}). Try again online.';
      }
    }
    await _saveLocalHousehold(household);
    await _rememberSelection(userId, household.id);
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
        final inviteData = invite.data();
        final householdId = inviteData?['household_id'] as String?;
        final expiresAt = _date(inviteData?['expires_at']);
        if (expiresAt == null || !expiresAt.isAfter(DateTime.now())) {
          throw 'That invite code has expired. Ask the owner for a new one.';
        }
        if (householdId != null) {
          final reference = firestore.collection('households').doc(householdId);
          await firestore.runTransaction((transaction) async {
            final snapshot = await transaction.get(reference);
            final data = snapshot.data();
            if (data == null) throw 'That household is no longer available.';
            final members = List<String>.from(data['member_ids'] ?? const []);
            final roles = Map<String, String>.from(
              data['member_roles'] ?? const {},
            );
            final ownerId = data['owner_id']?.toString() ?? '';
            if (ownerId.isNotEmpty) roles[ownerId] = 'owner';
            for (final memberId in members) {
              roles.putIfAbsent(memberId, () => 'member');
            }
            if (!members.contains(userId)) members.add(userId);
            roles[userId] = roles[userId] ?? 'member';
            transaction.update(reference, {
              'member_ids': members,
              'member_roles': roles,
              'updated_at': DateTime.now().toIso8601String(),
            });
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
        throw 'Could not securely validate that invite (${error.code}). Check your connection.';
      }
    }

    if (household == null) throw 'No household matches that invite code.';
    if (firestore == null &&
        (household.inviteExpiresAt == null ||
            !household.inviteExpiresAt!.isAfter(DateTime.now()))) {
      throw 'That invite code has expired. Ask the owner for a new one.';
    }
    final roles = Map<String, String>.from(household.memberRoles);
    roles[userId] = roles[userId] ?? 'member';
    final updated = HouseholdModel(
      id: household.id,
      name: household.name,
      ownerId: household.ownerId,
      memberIds: {...household.memberIds, userId}.toList(),
      memberRoles: roles,
      inviteCode: household.inviteCode,
      inviteExpiresAt: household.inviteExpiresAt,
      createdAt: household.createdAt,
      updatedAt: DateTime.now(),
    );
    await _saveLocalHousehold(updated);
    await _rememberSelection(userId, updated.id);
    return updated;
  }

  Future<HouseholdModel> rename({
    required HouseholdModel household,
    required String actorId,
    required String name,
  }) async {
    _requireAdmin(household, actorId);
    final cleanName = name.trim();
    if (cleanName.isEmpty) throw 'Enter a household name.';
    final updated = household.copyWith(
      name: cleanName,
      updatedAt: DateTime.now(),
    );
    await _writeHousehold(updated);
    return updated;
  }

  Future<HouseholdModel> regenerateInvite({
    required HouseholdModel household,
    required String actorId,
  }) async {
    _requireAdmin(household, actorId);
    final code = _generateInviteCode();
    final expiresAt = DateTime.now().add(const Duration(days: 7));
    final updated = household.copyWith(
      inviteCode: code,
      inviteExpiresAt: expiresAt,
      updatedAt: DateTime.now(),
    );
    final firestore = _firestore;
    if (firestore != null) {
      final batch = firestore.batch();
      batch.set(
        firestore.collection('households').doc(updated.id),
        updated.toMap(),
      );
      batch.set(firestore.collection('household_invites').doc(code), {
        'household_id': updated.id,
        'owner_id': household.ownerId,
        'created_at': Timestamp.fromDate(DateTime.now()),
        'expires_at': Timestamp.fromDate(expiresAt),
      });
      if (household.inviteCode.isNotEmpty && household.inviteCode != code) {
        batch.delete(
          firestore.collection('household_invites').doc(household.inviteCode),
        );
      }
      try {
        await batch.commit();
      } on FirebaseException catch (error) {
        throw 'Could not refresh the invite (${error.code}).';
      }
    }
    await _saveLocalHousehold(updated);
    return updated;
  }

  Future<HouseholdModel> setMemberRole({
    required HouseholdModel household,
    required String actorId,
    required String memberId,
    required String role,
  }) async {
    if (household.ownerId != actorId) {
      throw 'Only the household owner can change roles.';
    }
    if (memberId == household.ownerId) {
      throw 'The owner role cannot be changed.';
    }
    if (!household.memberIds.contains(memberId)) throw 'Member not found.';
    if (!const {'admin', 'member'}.contains(role)) throw 'Invalid role.';
    final roles = Map<String, String>.from(household.memberRoles)
      ..[memberId] = role;
    final updated = household.copyWith(
      memberRoles: roles,
      updatedAt: DateTime.now(),
    );
    await _writeHousehold(updated);
    return updated;
  }

  Future<HouseholdModel> removeMember({
    required HouseholdModel household,
    required String actorId,
    required String memberId,
  }) async {
    _requireAdmin(household, actorId);
    if (memberId == household.ownerId) throw 'The owner cannot be removed.';
    final members = [...household.memberIds]..remove(memberId);
    final roles = Map<String, String>.from(household.memberRoles)
      ..remove(memberId);
    final updated = household.copyWith(
      memberIds: members,
      memberRoles: roles,
      updatedAt: DateTime.now(),
    );
    await _writeHousehold(updated);
    final firestore = _firestore;
    if (firestore != null) {
      await firestore.collection('users').doc(memberId).set({
        'household_id': null,
      }, SetOptions(merge: true));
    }
    return updated;
  }

  Future<void> _writeHousehold(HouseholdModel household) async {
    final firestore = _firestore;
    if (firestore != null) {
      try {
        await firestore
            .collection('households')
            .doc(household.id)
            .set(household.toMap());
      } on FirebaseException catch (error) {
        throw 'Could not update the household (${error.code}).';
      }
    }
    await _saveLocalHousehold(household);
  }

  Future<void> _rememberSelection(String userId, String householdId) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(
      'culinary_selected_household_$userId',
      householdId,
    );
  }

  void _requireAdmin(HouseholdModel household, String actorId) {
    final role =
        household.memberRoles[actorId] ??
        (household.ownerId == actorId ? 'owner' : 'member');
    if (role != 'owner' && role != 'admin') {
      throw 'Owner or admin permission is required.';
    }
  }

  DateTime? _date(Object? value) {
    if (value is String) return DateTime.tryParse(value);
    if (value != null) {
      try {
        return (value as dynamic).toDate() as DateTime;
      } catch (_) {}
    }
    return null;
  }

  String _generateInviteCode() {
    final random = Random.secure();
    return List.generate(
      6,
      (_) => _codeCharacters[random.nextInt(_codeCharacters.length)],
    ).join();
  }
}
