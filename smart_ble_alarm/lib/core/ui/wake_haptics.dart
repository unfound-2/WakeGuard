import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class WakeHaptics {
  const WakeHaptics._();

  static bool get _enabled =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

  static void lightImpact() {
    if (_enabled) HapticFeedback.lightImpact();
  }

  static void mediumImpact() {
    if (_enabled) HapticFeedback.mediumImpact();
  }

  static void heavyImpact() {
    if (_enabled) HapticFeedback.heavyImpact();
  }

  static void selectionClick() {
    if (_enabled) HapticFeedback.selectionClick();
  }
}
