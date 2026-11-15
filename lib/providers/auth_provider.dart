import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/user_model.dart';
import '../services/auth_service.dart';
import '../services/profile_service.dart';
import '../services/session_service.dart';

class AuthProvider extends ChangeNotifier {
  final AuthService _authService;
  final ProfileService _profileService;
  final SessionService _sessionService;
  late final Future<void> initialized;
  int _sessionVersion = 0;
  bool _disposed = false;

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

  AuthProvider({
    AuthService? authService,
    ProfileService? profileService,
    SessionService? sessionService,
  }) : _authService = authService ?? AuthService(),
       _profileService = profileService ?? ProfileService(),
       _sessionService = sessionService ?? SessionService() {
    initialized = _restoreSession();
  }

  Future<void> _restoreSession() async {
    final version = _sessionVersion;
    try {
      final cached = await _sessionService.loadUser();
      final nativeUser = await _authService.restoreUser();
      if (_disposed || version != _sessionVersion) return;
      // A cached profile is not a substitute for Firebase authentication.
      final user = nativeUser != null
          ? cached?.id == nativeUser.id
                ? cached!.copyWith(email: nativeUser.email)
                : nativeUser
          : !_authService.usesFirebase || cached?.id == 'demo_chef'
          ? cached
          : null;
      if (user != null) {
        _currentUser = user;
        await _sessionService.saveUser(user);
        unawaited(_refreshRestoredProfile(user, version));
      }
    } catch (error) {
      if (kDebugMode) {
        debugPrint('Session restore skipped: $error');
      }
    } finally {
      _isInitializing = false;
      if (!_disposed) notifyListeners();
    }
  }

  Future<UserModel> _loadProfileOrKeepUser(UserModel user) async {
    try {
      return await _profileService
          .loadProfile(user)
          .timeout(const Duration(seconds: 4));
    } catch (error) {
      if (kDebugMode) debugPrint('Using saved profile: $error');
      return user;
    }
  }

  Future<void> _refreshRestoredProfile(UserModel user, int version) async {
    final refreshed = await _loadProfileOrKeepUser(user);
    if (_disposed ||
        version != _sessionVersion ||
        _currentUser?.id != user.id) {
      return;
    }
    _currentUser = refreshed;
    // Refreshing a profile must not write an authenticated session after logout.
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  void clearError() {
    _errorMessage = null;
    notifyListeners();
  }

  Future<bool> login(String email, String password) async {
    _sessionVersion++;
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final user = await _authService.signIn(email: email, password: password);
      _currentUser = await _loadProfileOrKeepUser(user);
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
    _sessionVersion++;
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
    _sessionVersion++;
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final user = await _authService.signInWithGoogle();
      _currentUser = await _loadProfileOrKeepUser(user);
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

  Future<void> continueAsDemo() async {
    _sessionVersion++;
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    const demoUserId = 'demo_chef';
    _currentUser = UserModel(
      id: demoUserId,
      name: 'Alex',
      email: 'chef@culinary.ai',
      dietaryPreference: 'Balanced',
      location: 'Lahore, Pakistan',
      bio: 'Exploring smarter home cooking with CulinaryAI.',
    );
    await _sessionService.saveUser(_currentUser!);
    _isLoading = false;
    notifyListeners();
  }

  Future<void> logout() async {
    _sessionVersion++;
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
    _sessionVersion++;
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
