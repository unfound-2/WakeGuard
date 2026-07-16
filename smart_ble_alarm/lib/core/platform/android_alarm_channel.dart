import 'dart:io';

import 'package:flutter/services.dart';

/// Thin Dart wrapper over the native `wakeguard/alarm` MethodChannel implemented
/// in Android's MainActivity. Every call is Android-only and best-effort/
/// try-caught — on iOS (or if the platform impl is missing, e.g. tests) each
/// method is a silent no-op so the shared ring path can never crash.
///
/// The native side owns three responsibilities the Flutter layer can't do
/// itself:
///  * [playSystemAlarm]/[stopSystemAlarm] — loop the *user's system-selected*
///    alarm sound (RingtoneManager TYPE_ALARM) on the alarm audio stream. Used
///    when no hardware clock is connected, so an offline phone rings with the
///    same tone the OS clock app would use.
///  * [armLockScreen]/[disarmLockScreen] — show the alarm over the keyguard,
///    turn the screen on, and keep it awake while ringing.
///  * [openDialer]/[openMessages] — the two shortcuts offered on the full-screen
///    alarm so a call/text is still reachable without dismissing.
class AndroidAlarmChannel {
  const AndroidAlarmChannel._();

  static const MethodChannel _channel = MethodChannel('wakeguard/alarm');

  /// Start looping the system-selected alarm sound (alarm stream, at the
  /// system's alarm volume). Idempotent on the native side — a second call
  /// while already playing restarts cleanly.
  static Future<void> playSystemAlarm() => _invoke('playSystemAlarm');

  /// Stop and release the system alarm sound.
  static Future<void> stopSystemAlarm() => _invoke('stopSystemAlarm');

  /// Show the current activity over the lock screen, turn the screen on, and
  /// hold it awake. Called when the full-screen alarm appears.
  static Future<void> armLockScreen() => _invoke('armLockScreen');

  /// Release the keep-awake flag once the alarm is dismissed.
  static Future<void> disarmLockScreen() => _invoke('disarmLockScreen');

  /// Open the phone dialer (ACTION_DIAL — no call is placed).
  static Future<void> openDialer() => _invoke('openDialer');

  /// Open the default messaging app.
  static Future<void> openMessages() => _invoke('openMessages');

  /// Whether the app currently holds the "Display over other apps"
  /// (SYSTEM_ALERT_WINDOW) permission. When granted, the full-screen alarm can
  /// reliably appear over the lock screen and other apps even on OEM builds that
  /// otherwise suppress full-screen-intent alarms. Returns `true` on non-Android
  /// platforms (no such restriction) and `false` if the query fails.
  static Future<bool> canDrawOverlays() async {
    if (!Platform.isAndroid) return true;
    try {
      return await _channel.invokeMethod<bool>('canDrawOverlays') ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Deep-link to the system "Display over other apps" screen for this app so
  /// the user can grant the permission. The grant itself happens in system
  /// Settings; callers should re-check [canDrawOverlays] once the app resumes.
  static Future<void> requestOverlayPermission() =>
      _invoke('requestOverlayPermission');

  static Future<void> _invoke(String method) async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod<void>(method);
    } catch (_) {
      // Best-effort: the visual alarm + haptics stand on their own.
    }
  }
}
