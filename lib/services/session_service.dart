import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/user_model.dart';

class SessionService {
  static const _sessionKey = 'culinary_authenticated_user';

  Future<UserModel?> loadUser() async {
    final preferences = await SharedPreferences.getInstance();
    final encoded = preferences.getString(_sessionKey);
    if (encoded == null) return null;

    try {
      final data = jsonDecode(encoded) as Map<String, dynamic>;
      final id = data['id'] as String?;
      if (id == null || id.isEmpty) return null;
      return UserModel.fromMap(data, id);
    } catch (_) {
      await preferences.remove(_sessionKey);
      return null;
    }
  }

  Future<void> saveUser(UserModel user) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(_sessionKey, jsonEncode(user.toMap()));
  }

  Future<void> clear() async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.remove(_sessionKey);
  }
}
