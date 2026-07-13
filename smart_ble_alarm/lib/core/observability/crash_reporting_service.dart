import 'dart:async';

import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';
import 'package:smart_ble_alarm/core/firebase/app_firebase.dart';

class CrashReportingService {
  CrashReportingService._();

  static FirebaseCrashlytics? _crashlytics;

  static FirebaseCrashlytics? get _client {
    if (!AppFirebase.isReady) return null;
    return _crashlytics ??= FirebaseCrashlytics.instance;
  }

  static Future<void> initialize() async {
    final crashlytics = _client;
    if (crashlytics == null) return;
    FlutterError.onError = (details) {
      FlutterError.presentError(details);
      unawaited(crashlytics.recordFlutterFatalError(details));
    };
    PlatformDispatcher.instance.onError = (error, stackTrace) {
      unawaited(recordError(error, stackTrace, fatal: true));
      return true;
    };
  }

  static Future<void> setUserId(String? userId) async {
    final crashlytics = _client;
    if (crashlytics == null) return;
    try {
      await crashlytics.setUserIdentifier(userId ?? '');
    } catch (error, stackTrace) {
      debugPrint('Crashlytics setUserId failed: $error\n$stackTrace');
    }
  }

  static Future<void> recordError(
    Object error,
    StackTrace stackTrace, {
    bool fatal = false,
    String? reason,
  }) async {
    final crashlytics = _client;
    if (crashlytics == null) {
      debugPrint('Recorded local error: $error\n$stackTrace');
      return;
    }
    try {
      await crashlytics.recordError(
        error,
        stackTrace,
        fatal: fatal,
        reason: reason,
      );
    } catch (innerError, innerStackTrace) {
      debugPrint(
        'Crashlytics recordError failed: $innerError\n$innerStackTrace',
      );
    }
  }

  static Future<void> log(String message) async {
    final crashlytics = _client;
    if (crashlytics == null) return;
    try {
      await crashlytics.log(message);
    } catch (_) {}
  }
}
