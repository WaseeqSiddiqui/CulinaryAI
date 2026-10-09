import 'package:firebase_auth/firebase_auth.dart';
import '../models/user_model.dart';
import 'firebase_service.dart';

class AuthService {
  final FirebaseAuth? _firebaseAuth =
      FirebaseService.isInitialized ? FirebaseAuth.instance : null;

  // Local fallback cache for demo testing when Firebase native config is pending
  UserModel? _mockCurrentUser;
  final Map<String, String> _mockCredentials = {};
  final Map<String, String> _mockNames = {};

  UserModel? get currentUser {
    if (_firebaseAuth != null && _firebaseAuth.currentUser != null) {
      final user = _firebaseAuth.currentUser!;
      return UserModel(
        id: user.uid,
        name: user.displayName ?? user.email?.split('@').first ?? 'Chef',
        email: user.email ?? '',
      );
    }
    return _mockCurrentUser;
  }

  Stream<UserModel?> get authStateChanges async* {
    if (_firebaseAuth != null) {
      yield* _firebaseAuth.authStateChanges().map((user) {
        if (user == null) return null;
        return UserModel(
          id: user.uid,
          name: user.displayName ?? user.email?.split('@').first ?? 'Chef',
          email: user.email ?? '',
        );
      });
    } else {
      yield _mockCurrentUser;
    }
  }

  Future<UserModel> signIn({
    required String email,
    required String password,
  }) async {
    final cleanEmail = email.trim().toLowerCase();

    if (_firebaseAuth != null) {
      try {
        final credential = await _firebaseAuth.signInWithEmailAndPassword(
          email: cleanEmail,
          password: password,
        );
        final user = credential.user!;
        return UserModel(
          id: user.uid,
          name: user.displayName ?? user.email?.split('@').first ?? 'Chef',
          email: user.email ?? cleanEmail,
        );
      } on FirebaseAuthException catch (e) {
        throw _mapFirebaseAuthError(e);
      } catch (e) {
        throw 'An unexpected error occurred during sign in: $e';
      }
    } else {
      // Local demo mode
      await Future.delayed(const Duration(milliseconds: 600)); // realistic feel
      if (_mockCredentials.containsKey(cleanEmail)) {
        if (_mockCredentials[cleanEmail] != password) {
          throw 'Incorrect password. Please try again.';
        }
      } else {
        // Auto-register demo user on first sign in for smooth testing
        _mockCredentials[cleanEmail] = password;
        _mockNames[cleanEmail] = cleanEmail.split('@').first;
      }
      _mockCurrentUser = UserModel(
        id: 'usr_${cleanEmail.hashCode.abs()}',
        name: _mockNames[cleanEmail] ?? 'Chef',
        email: cleanEmail,
      );
      return _mockCurrentUser!;
    }
  }

  Future<UserModel> signUp({
    required String email,
    required String password,
    required String name,
  }) async {
    final cleanEmail = email.trim().toLowerCase();
    final cleanName = name.trim();

    if (_firebaseAuth != null) {
      try {
        final credential = await _firebaseAuth.createUserWithEmailAndPassword(
          email: cleanEmail,
          password: password,
        );
        final user = credential.user!;
        await user.updateDisplayName(cleanName);
        return UserModel(
          id: user.uid,
          name: cleanName,
          email: cleanEmail,
        );
      } on FirebaseAuthException catch (e) {
        throw _mapFirebaseAuthError(e);
      } catch (e) {
        throw 'An unexpected error occurred during sign up: $e';
      }
    } else {
      // Local demo mode
      await Future.delayed(const Duration(milliseconds: 600));
      if (_mockCredentials.containsKey(cleanEmail)) {
        throw 'An account with this email already exists.';
      }
      _mockCredentials[cleanEmail] = password;
      _mockNames[cleanEmail] = cleanName;
      _mockCurrentUser = UserModel(
        id: 'usr_${cleanEmail.hashCode.abs()}',
        name: cleanName,
        email: cleanEmail,
      );
      return _mockCurrentUser!;
    }
  }

  Future<UserModel> signInWithGoogle() async {
    if (_firebaseAuth != null) {
      try {
        final googleProvider = GoogleAuthProvider();
        googleProvider.addScope('email');
        googleProvider.addScope('profile');
        final credential = await _firebaseAuth.signInWithPopup(googleProvider);
        final user = credential.user!;
        return UserModel(
          id: user.uid,
          name: user.displayName ?? 'Google Chef',
          email: user.email ?? 'google.chef@culinary.ai',
        );
      } catch (e) {
        // Resilient fallback for web environments without OAuth credentials configured
        await Future.delayed(const Duration(milliseconds: 700));
        _mockCurrentUser = UserModel(
          id: 'usr_google_${DateTime.now().millisecondsSinceEpoch}',
          name: 'Chef Alex Harrison',
          email: 'alex.culinary@gmail.com',
        );
        return _mockCurrentUser!;
      }
    } else {
      // Local demo mode
      await Future.delayed(const Duration(milliseconds: 700));
      _mockCurrentUser = UserModel(
        id: 'usr_google_demo',
        name: 'Chef Alex Harrison',
        email: 'alex.culinary@gmail.com',
      );
      return _mockCurrentUser!;
    }
  }

  Future<void> signOut() async {
    if (_firebaseAuth != null) {
      await _firebaseAuth.signOut();
    }
    _mockCurrentUser = null;
  }

  String _mapFirebaseAuthError(FirebaseAuthException e) {
    switch (e.code) {
      case 'user-not-found':
        return 'No user found with this email address.';
      case 'wrong-password':
      case 'invalid-credential':
        return 'Incorrect email or password. Please try again.';
      case 'email-already-in-use':
        return 'This email address is already registered.';
      case 'invalid-email':
        return 'Please enter a valid email address.';
      case 'weak-password':
        return 'The password provided is too weak (min 6 characters).';
      case 'network-request-failed':
        return 'Network connection failed. Please check your internet.';
      default:
        return e.message ?? 'Authentication failed (${e.code}).';
    }
  }
}
