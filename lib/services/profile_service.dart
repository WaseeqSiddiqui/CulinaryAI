import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/user_model.dart';
import 'firebase_service.dart';

class ProfileService {
  final FirebaseFirestore? _firestore = FirebaseService.isInitialized
      ? FirebaseFirestore.instance
      : null;

  CollectionReference<Map<String, dynamic>>? get _users =>
      _firestore?.collection('users');

  String _profileKey(String userId) => 'culinary_profile_$userId';
  String _dirtyKey(String userId) => 'culinary_profile_dirty_$userId';

  Future<UserModel> _loadLocalProfile(UserModel baseUser) async {
    final preferences = await SharedPreferences.getInstance();
    final encoded = preferences.getString(_profileKey(baseUser.id));
    if (encoded == null) return baseUser;

    try {
      final data = jsonDecode(encoded) as Map<String, dynamic>;
      return _mergeWithBase(UserModel.fromMap(data, baseUser.id), baseUser);
    } catch (_) {
      return baseUser;
    }
  }

  Future<void> _saveLocalProfile(UserModel user, {required bool dirty}) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(_profileKey(user.id), jsonEncode(user.toMap()));
    await preferences.setBool(_dirtyKey(user.id), dirty);
  }

  UserModel _mergeWithBase(UserModel stored, UserModel baseUser) {
    return stored.copyWith(
      name: stored.name.trim().isEmpty ? baseUser.name : stored.name,
      email: stored.email.trim().isEmpty ? baseUser.email : stored.email,
      photoUrl: stored.photoUrl ?? baseUser.photoUrl,
    );
  }

  Future<UserModel> loadProfile(UserModel baseUser) async {
    final localUser = await _loadLocalProfile(baseUser);
    final preferences = await SharedPreferences.getInstance();
    final hasPendingLocalChanges =
        preferences.getBool(_dirtyKey(baseUser.id)) ?? false;
    final users = _users;
    if (users == null) return localUser;

    if (hasPendingLocalChanges) {
      await _syncToFirestore(localUser);
      return localUser;
    }

    try {
      final snapshot = await users.doc(baseUser.id).get();
      final data = snapshot.data();
      if (data == null) {
        await ensureProfile(localUser);
        return localUser;
      }

      final stored = UserModel.fromMap(data, baseUser.id);
      final merged = _mergeWithBase(stored, baseUser);
      await _saveLocalProfile(merged, dirty: false);
      return merged;
    } on FirebaseException catch (error) {
      if (kDebugMode) {
        debugPrint('Profile load skipped: ${error.code}');
      }
      return localUser;
    }
  }

  Future<void> ensureProfile(UserModel user) async {
    await _saveLocalProfile(user, dirty: true);
    await _syncToFirestore(user);
  }

  Future<void> _syncToFirestore(UserModel user) async {
    final users = _users;
    if (users == null) return;
    try {
      await users.doc(user.id).set({
        ...user.toMap(),
        'updated_at': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      await _saveLocalProfile(user, dirty: false);
    } on FirebaseException catch (error) {
      if (kDebugMode) {
        debugPrint('Profile creation skipped: ${error.code}');
      }
    }
  }

  Future<void> saveProfile(UserModel user) async {
    try {
      await _saveLocalProfile(user, dirty: true);
      await _syncToFirestore(user);
    } catch (_) {
      throw 'Could not save your profile. Please try again.';
    }
  }
}
