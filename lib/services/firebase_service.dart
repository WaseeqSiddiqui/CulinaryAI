import 'package:flutter/foundation.dart';
import 'package:firebase_core/firebase_core.dart';
import '../firebase_options.dart';

class FirebaseService {
  static bool _isInitialized = false;
  static bool get isInitialized => _isInitialized;

  static Future<void> initialize() async {
    try {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
      _isInitialized = true;
      if (kDebugMode) {
        print('Firebase successfully initialized.');
      }
    } catch (e) {
      _isInitialized = false;
      if (kDebugMode) {
        print('Firebase initialization notice: $e');
        print('Running with resilient local authentication mode.');
      }
    }
  }
}
