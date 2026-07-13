import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:smart_ble_alarm/firebase_options.dart';

class AppFirebase {
  const AppFirebase._();

  static Future<bool>? _initialization;

  static bool get isReady => Firebase.apps.isNotEmpty;

  static Future<bool> ensureInitialized() async {
    if (Firebase.apps.isNotEmpty) return true;
    final existing = _initialization;
    if (existing != null) return existing;

    final initialization = _initialize();
    _initialization = initialization;
    return initialization;
  }

  static Future<bool> _initialize() async {
    if (Firebase.apps.isNotEmpty) return true;
    try {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
      return true;
    } on UnsupportedError catch (error) {
      debugPrint('Firebase is unavailable on this platform: ${error.message}');
      _initialization = null;
      return false;
    } catch (error, stackTrace) {
      debugPrint('Firebase failed to initialize: $error\n$stackTrace');
      _initialization = null;
      return false;
    }
  }
}
