import 'package:flutter/foundation.dart';

import '../models/user_model.dart';
import '../services/auth_service.dart';
import '../services/profile_service.dart';
import '../services/session_service.dart';

class AuthProvider extends ChangeNotifier {
  final AuthService _authService = AuthService();
  final ProfileService _profileService = ProfileService();
  final SessionService _sessionService = SessionService();

  UserModel? _currentUser;
  bool _isInitializing = true;
  bool _isLoading = false;
  bool _isProfileSaving = false;
  String? _errorMessage;

  UserModel? get currentUser => _currentUser;
  bool get isAuthenticated => _currentUser != null;
  bool get isInitializing => _isInitializing;
  bool get isLoading => _isLoading;
  bool get isProfileSaving => _isProfileSaving;
  String? get errorMessage => _errorMessage;

  AuthProvider() {
    _restoreSession();
  }

  Future<void> _restoreSession() async {
    try {
      final user = _authService.currentUser ?? await _sessionService.loadUser();
      if (user != null) {
        _currentUser = await _profileService.loadProfile(user);
        await _sessionService.saveUser(_currentUser!);
      }
    } catch (error) {
      if (kDebugMode) {
        debugPrint('Session restore skipped: $error');
      }
    } finally {
      _isInitializing = false;
      notifyListeners();
    }
  }

  void clearError() {
    _errorMessage = null;
    notifyListeners();
  }

  Future<bool> login(String email, String password) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final user = await _authService.signIn(email: email, password: password);
      _currentUser = await _profileService.loadProfile(user);
      await _sessionService.saveUser(_currentUser!);
      _isLoading = false;
      notifyListeners();
      return true;
    } catch (e) {
      _errorMessage = e.toString();
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  Future<bool> register(String email, String password, String name) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      _currentUser = await _authService.signUp(
        email: email,
        password: password,
        name: name,
      );
      await _profileService.ensureProfile(_currentUser!);
      await _sessionService.saveUser(_currentUser!);
      _isLoading = false;
      notifyListeners();
      return true;
    } catch (e) {
      _errorMessage = e.toString();
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  Future<bool> loginWithGoogle() async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final user = await _authService.signInWithGoogle();
      _currentUser = await _profileService.loadProfile(user);
      await _sessionService.saveUser(_currentUser!);
      _isLoading = false;
      notifyListeners();
      return true;
    } catch (e) {
      _errorMessage = e.toString();
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  Future<void> logout() async {
    _isLoading = true;
    notifyListeners();
    try {
      await _authService.signOut();
    } finally {
      await _sessionService.clear();
      _currentUser = null;
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<bool> updateProfile(UserModel updatedUser) async {
    if (_currentUser == null || updatedUser.id != _currentUser!.id) {
      _errorMessage = 'No signed-in profile is available to update.';
      notifyListeners();
      return false;
    }

    _isProfileSaving = true;
    _errorMessage = null;
    notifyListeners();

    try {
      await _profileService.saveProfile(updatedUser);
      await _authService.updateDisplayName(updatedUser.name);
      _currentUser = updatedUser;
      await _sessionService.saveUser(updatedUser);
      _isProfileSaving = false;
      notifyListeners();
      return true;
    } catch (e) {
      _errorMessage = e.toString();
      _isProfileSaving = false;
      notifyListeners();
      return false;
    }
  }
}
