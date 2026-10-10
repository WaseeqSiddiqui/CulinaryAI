import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../models/user_model.dart';
import 'firebase_service.dart';

class AuthService {
  static final GoogleSignIn _googleSignIn = GoogleSignIn.instance;
  static Future<void>? _googleSignInInitialization;

  final FirebaseAuth? _firebaseAuth = FirebaseService.isInitialized
      ? FirebaseAuth.instance
      : null;

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
        photoUrl: user.photoURL,
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
          photoUrl: user.photoURL,
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
          photoUrl: user.photoURL,
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
        return UserModel(id: user.uid, name: cleanName, email: cleanEmail);
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
    if (_firebaseAuth == null) {
      throw 'Google sign-in is unavailable because Firebase could not be initialized.';
    }

    try {
      UserCredential credential;

      if (kIsWeb) {
        final googleProvider = GoogleAuthProvider();
        googleProvider.addScope('email');
        googleProvider.addScope('profile');
        credential = await _firebaseAuth.signInWithPopup(googleProvider);
      } else {
        _googleSignInInitialization ??= _googleSignIn.initialize();
        await _googleSignInInitialization;

        if (!_googleSignIn.supportsAuthenticate()) {
          throw 'Google sign-in is not supported on this platform.';
        }

        final googleUser = await _googleSignIn.authenticate();
        final idToken = googleUser.authentication.idToken;
        if (idToken == null) {
          throw 'Google did not return a valid sign-in token. Please try again.';
        }

        final googleCredential = GoogleAuthProvider.credential(
          idToken: idToken,
        );
        credential = await _firebaseAuth.signInWithCredential(googleCredential);
      }

      final user = credential.user;
      if (user == null) {
        throw 'Google sign-in completed without returning a user.';
      }
      return UserModel(
        id: user.uid,
        name: user.displayName ?? user.email?.split('@').first ?? 'Chef',
        email: user.email ?? '',
        photoUrl: user.photoURL,
      );
    } on GoogleSignInException catch (e) {
      throw _mapGoogleSignInError(e);
    } on FirebaseAuthException catch (e) {
      throw _mapFirebaseAuthError(e);
    } catch (e) {
      if (e is String) rethrow;
      throw 'Google sign-in failed. Please try again.';
    }
  }

  Future<void> signOut() async {
    if (_firebaseAuth != null) {
      await _firebaseAuth.signOut();
    }
    if (!kIsWeb && _googleSignInInitialization != null) {
      await _googleSignInInitialization;
      await _googleSignIn.signOut();
    }
    _mockCurrentUser = null;
  }

  Future<void> updateDisplayName(String name) async {
    final cleanName = name.trim();
    final currentUser = _firebaseAuth?.currentUser;
    if (currentUser != null) {
      try {
        await currentUser.updateDisplayName(cleanName);
      } on FirebaseAuthException catch (error) {
        if (kDebugMode) {
          debugPrint('Firebase display name sync skipped: ${error.code}');
        }
      }
    }
    if (_mockCurrentUser != null) {
      _mockCurrentUser = _mockCurrentUser!.copyWith(name: cleanName);
    }
  }

  String _mapGoogleSignInError(GoogleSignInException e) {
    switch (e.code) {
      case GoogleSignInExceptionCode.canceled:
        return 'Google sign-in was cancelled.';
      case GoogleSignInExceptionCode.interrupted:
        return 'Google sign-in was interrupted. Please try again.';
      case GoogleSignInExceptionCode.clientConfigurationError:
      case GoogleSignInExceptionCode.providerConfigurationError:
        return 'Google sign-in is not configured correctly for this app.';
      case GoogleSignInExceptionCode.uiUnavailable:
        return 'Google sign-in is currently unavailable on this device.';
      default:
        return e.description ?? 'Google sign-in failed. Please try again.';
    }
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
