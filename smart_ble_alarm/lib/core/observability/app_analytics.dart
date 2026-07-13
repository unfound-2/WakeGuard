import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:flutter/foundation.dart';
import 'package:smart_ble_alarm/core/firebase/app_firebase.dart';

class AppAnalytics {
  AppAnalytics._();

  static final AppAnalytics instance = AppAnalytics._();

  FirebaseAnalytics? _analytics;

  FirebaseAnalytics? get _client {
    if (!AppFirebase.isReady) return null;
    return _analytics ??= FirebaseAnalytics.instance;
  }

  Future<void> setUserId(String? userId) async {
    final analytics = _client;
    if (analytics == null) return;
    try {
      await analytics.setUserId(id: userId);
    } catch (error, stackTrace) {
      debugPrint('Analytics setUserId failed: $error\n$stackTrace');
    }
  }

  Future<void> onboardingStepViewed({
    required int index,
    required String step,
  }) {
    return logEvent(
      'onboarding_step_viewed',
      parameters: {'step_index': index, 'step': step},
    );
  }

  Future<void> onboardingSkipped({required int index, required String step}) {
    return logEvent(
      'onboarding_skipped',
      parameters: {'step_index': index, 'step': step},
    );
  }

  Future<void> onboardingCompleted() {
    return logEvent('onboarding_completed');
  }

  Future<void> alarmSyncFailed({required String source, String? reason}) {
    return logEvent(
      'alarm_sync_failed',
      parameters: {'source': source, 'reason': ?reason},
    );
  }

  Future<void> logEvent(String name, {Map<String, Object>? parameters}) async {
    final analytics = _client;
    if (analytics == null) return;
    try {
      await analytics.logEvent(name: name, parameters: parameters);
    } catch (error, stackTrace) {
      debugPrint('Analytics event failed: $name $error\n$stackTrace');
    }
  }
}
