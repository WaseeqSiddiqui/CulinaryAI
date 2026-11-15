import 'dart:async';

import 'package:culinary_ai/models/user_model.dart';
import 'package:culinary_ai/providers/auth_provider.dart';
import 'package:culinary_ai/services/auth_service.dart';
import 'package:culinary_ai/services/profile_service.dart';
import 'package:culinary_ai/services/session_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Auth extends AuthService {
  _Auth({this.native = false, this.user, this.restoration});
  final bool native;
  UserModel? user;
  final Completer<UserModel?>? restoration;
  @override
  bool get usesFirebase => native;
  @override
  Future<UserModel?> restoreUser() async => restoration?.future ?? user;
  @override
  Future<UserModel> signIn({
    required String email,
    required String password,
  }) async => user = UserModel(id: 'signed-in', name: 'Sam', email: email);
  @override
  Future<void> signOut() async => user = null;
}

class _Profiles extends ProfileService {
  _Profiles(this.load);
  final Future<UserModel> Function(UserModel) load;
  @override
  Future<UserModel> loadProfile(UserModel user) => load(user);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final saved = UserModel(id: 'saved', name: 'Sam', email: 'sam@example.com');
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test(
    'a saved sign-in restores even when profile refresh is unavailable',
    () async {
      await SessionService().saveUser(saved);
      final provider = AuthProvider(
        authService: _Auth(),
        profileService: _Profiles((_) async => throw StateError('offline')),
      );
      addTearDown(provider.dispose);
      await provider.initialized;
      expect(provider.isInitializing, isFalse);
      expect(provider.currentUser?.id, saved.id);
    },
  );

  test('startup does not wait for a slow cloud profile', () async {
    await SessionService().saveUser(saved);
    final profile = Completer<UserModel>();
    final provider = AuthProvider(
      authService: _Auth(),
      profileService: _Profiles((_) => profile.future),
    );
    addTearDown(provider.dispose);
    await provider.initialized;
    expect(provider.currentUser?.id, saved.id);
    expect(provider.isInitializing, isFalse);
    profile.complete(saved);
    await Future<void>.delayed(Duration.zero);
  });

  test(
    'cached identity cannot replace a signed-out Firebase session',
    () async {
      await SessionService().saveUser(saved);
      final provider = AuthProvider(authService: _Auth(native: true));
      addTearDown(provider.dispose);
      await provider.initialized;
      expect(provider.isAuthenticated, isFalse);
    },
  );

  test(
    'native restored user takes precedence over another cached account',
    () async {
      await SessionService().saveUser(saved);
      final native = UserModel(
        id: 'native',
        name: 'Chef',
        email: 'chef@example.com',
      );
      final provider = AuthProvider(
        authService: _Auth(native: true, user: native),
        profileService: _Profiles((user) async => user),
      );
      addTearDown(provider.dispose);
      await provider.initialized;
      expect(provider.currentUser?.id, native.id);
      expect((await SessionService().loadUser())?.id, native.id);
    },
  );

  test(
    'profile failure after successful login still persists that login',
    () async {
      final provider = AuthProvider(
        authService: _Auth(),
        profileService: _Profiles((_) async => throw StateError('offline')),
      );
      addTearDown(provider.dispose);
      await provider.initialized;
      expect(await provider.login('sam@example.com', 'test-only'), isTrue);
      final restarted = AuthProvider(
        authService: _Auth(),
        profileService: _Profiles((user) async => user),
      );
      addTearDown(restarted.dispose);
      await restarted.initialized;
      expect(restarted.currentUser?.id, 'signed-in');
    },
  );

  test('a late profile refresh cannot restore a logged-out account', () async {
    await SessionService().saveUser(saved);
    final profile = Completer<UserModel>();
    final provider = AuthProvider(
      authService: _Auth(),
      profileService: _Profiles((_) => profile.future),
    );
    addTearDown(provider.dispose);
    await provider.initialized;
    await provider.logout();
    profile.complete(saved);
    await Future<void>.delayed(Duration.zero);
    expect(provider.isAuthenticated, isFalse);
    expect(await SessionService().loadUser(), isNull);
  });

  test(
    'logout during native restore cannot bring the old session back',
    () async {
      await SessionService().saveUser(saved);
      final restoration = Completer<UserModel?>();
      final provider = AuthProvider(
        authService: _Auth(native: true, restoration: restoration),
      );
      addTearDown(provider.dispose);
      await provider.logout();
      restoration.complete(saved);
      await provider.initialized;
      expect(provider.isAuthenticated, isFalse);
      expect(await SessionService().loadUser(), isNull);
    },
  );
}
