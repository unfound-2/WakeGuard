import 'dart:async';

import 'package:audioplayers/audioplayers.dart';

import 'package:smart_ble_alarm/core/audio/alarm_sound.dart';
import 'package:smart_ble_alarm/domain/entities/alarm.dart';

/// Loops the runtime-synthesized alarm tone at an alarm's configured volume,
/// ramping up over its gradual-wake window when set. Shared by the two in-app
/// ring paths — the Dedicated Clock face and the "Ring on this phone" engine —
/// so their loudness, iOS silent-switch behaviour, and fade-in can never drift.
///
/// Every call is best-effort/try-caught: a missing audio platform impl (widget
/// tests, desktop) must never crash the ring — the visual overlay and haptics
/// stand on their own.
class AlarmTonePlayer {
  AudioPlayer? _player;
  Timer? _volumeRamp; // drives the gradual-wake fade-in

  /// Start (or restart) looping the tone for [alarm]. Safe to call repeatedly;
  /// the lazily-created player is reused so re-arming after a snooze doesn't leak.
  Future<void> play(Alarm alarm) async {
    try {
      final player = _player ??= AudioPlayer();
      await player.setReleaseMode(ReleaseMode.loop);
      // Ring through the iOS silent switch and route to the alarm stream on
      // Android. Guarded independently — an unsupported option must not stop the
      // tone from playing at all.
      try {
        await player.setAudioContext(
          AudioContext(
            iOS: AudioContextIOS(
              category: AVAudioSessionCategory.playback,
              options: const {AVAudioSessionOptions.duckOthers},
            ),
            android: const AudioContextAndroid(
              isSpeakerphoneOn: false,
              stayAwake: true,
              contentType: AndroidContentType.sonification,
              usageType: AndroidUsageType.alarm,
              audioFocus: AndroidAudioFocus.gain,
            ),
          ),
        );
      } catch (_) {}
      final target = (alarm.volumePercent.clamp(1, 100)) / 100.0;
      if (alarm.gradualWakeSeconds > 0) {
        final start = (target * 0.15).clamp(0.05, target);
        await player.setVolume(start);
        _rampVolume(start, target, alarm.gradualWakeSeconds);
      } else {
        _volumeRamp?.cancel();
        await player.setVolume(target);
      }
      await player.play(BytesSource(buildAlarmToneWav()));
    } catch (_) {
      // Audio unavailable (e.g. tests/desktop) — the visual ring + haptics stand.
    }
  }

  void _rampVolume(double start, double target, int seconds) {
    _volumeRamp?.cancel();
    const stepMs = 500;
    final steps = (seconds * 1000 / stepMs).ceil().clamp(1, 600);
    var step = 0;
    _volumeRamp = Timer.periodic(const Duration(milliseconds: stepMs), (t) async {
      step++;
      final frac = (step / steps).clamp(0.0, 1.0);
      try {
        await _player?.setVolume(start + (target - start) * frac);
      } catch (_) {}
      if (frac >= 1.0) t.cancel();
    });
  }

  /// Stop the tone but keep the player alive for a later [play] (e.g. snooze).
  Future<void> stop() async {
    _volumeRamp?.cancel();
    try {
      await _player?.stop();
    } catch (_) {}
  }

  /// Release the underlying player. Call from the owner's dispose().
  void dispose() {
    _volumeRamp?.cancel();
    try {
      _player?.dispose();
    } catch (_) {}
    _player = null;
  }
}
