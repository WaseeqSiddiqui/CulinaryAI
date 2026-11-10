import 'package:flutter/foundation.dart';

import '../models/household_model.dart';
import '../models/user_model.dart';
import '../services/household_service.dart';

class HouseholdProvider extends ChangeNotifier {
  final HouseholdService _service = HouseholdService();

  HouseholdModel? _household;
  String? _userId;
  bool _isLoading = false;
  String? _errorMessage;

  HouseholdModel? get household => _household;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  String? get userId => _userId;
  bool get isOwner => _household?.ownerId == _userId;
  String get currentRole {
    final userId = _userId;
    if (userId == null) return 'member';
    return _household?.memberRoles[userId] ??
        (_household?.ownerId == userId ? 'owner' : 'member');
  }

  String? get pantryScopeId =>
      _userId == null ? null : (_household?.id ?? 'personal_$_userId');

  void bindUser(UserModel? user) {
    if (_userId == user?.id) return;
    _userId = user?.id;
    _household = null;
    if (user == null) {
      _isLoading = false;
      return;
    }
    Future.microtask(() => _load(user));
  }

  Future<void> _load(UserModel user) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();
    try {
      _household = await _service.loadForUser(
        user.id,
        householdId: user.householdId,
      );
    } catch (error) {
      _errorMessage = error.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<bool> create(String name) async {
    final userId = _userId;
    if (userId == null) return false;
    return _run(() => _service.create(name: name, userId: userId));
  }

  Future<bool> join(String inviteCode) async {
    final userId = _userId;
    if (userId == null) return false;
    return _run(() => _service.join(inviteCode: inviteCode, userId: userId));
  }

  Future<bool> rename(String name) async {
    final household = _household;
    final userId = _userId;
    if (household == null || userId == null) return false;
    return _run(
      () => _service.rename(household: household, actorId: userId, name: name),
    );
  }

  Future<bool> regenerateInvite() async {
    final household = _household;
    final userId = _userId;
    if (household == null || userId == null) return false;
    return _run(
      () => _service.regenerateInvite(household: household, actorId: userId),
    );
  }

  Future<bool> setMemberRole(String memberId, String role) async {
    final household = _household;
    final userId = _userId;
    if (household == null || userId == null) return false;
    return _run(
      () => _service.setMemberRole(
        household: household,
        actorId: userId,
        memberId: memberId,
        role: role,
      ),
    );
  }

  Future<bool> removeMember(String memberId) async {
    final household = _household;
    final userId = _userId;
    if (household == null || userId == null) return false;
    return _run(
      () => _service.removeMember(
        household: household,
        actorId: userId,
        memberId: memberId,
      ),
    );
  }

  Future<bool> _run(Future<HouseholdModel> Function() action) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();
    try {
      _household = await action();
      _isLoading = false;
      notifyListeners();
      return true;
    } catch (error) {
      _errorMessage = error.toString();
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }
}
