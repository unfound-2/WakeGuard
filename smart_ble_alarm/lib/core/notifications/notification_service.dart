import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;
import '../../domain/entities/alarm.dart';

/// Phone-scheduled *backup* alarms.
///
/// The physical clock rings autonomously, but with on-demand BLE the phone is
/// usually disconnected when an alarm fires — so if the clock is unplugged,
/// dead, or out of range, nothing would wake the user. To close that gap we
/// schedule a local notification mirroring every enabled alarm. It can't run
/// the scan/QR dismissal (that's the clock's job); it just makes noise so a
/// silent hardware failure doesn't become a missed alarm.
class NotificationService {
  NotificationService([FlutterLocalNotificationsPlugin? plugin])
    : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  final FlutterLocalNotificationsPlugin _plugin;
  bool _ready = false;

  static const String _channelId = 'wakeguard_backup_alarms';
  static const String _channelName = 'Backup alarms';
  static const String _channelDescription =
      'Backup alarms in case the WakeGuard clock is unreachable.';

  /// Initialise the plugin, resolve the device timezone, and request the
  /// notification/exact-alarm permissions. Safe to call once at startup.
  Future<void> init() async {
    tzdata.initializeTimeZones();
    try {
      final info = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(info.identifier));
    } catch (_) {
      // Fall back to the default location (UTC). Alarms still schedule; the
      // wall-clock time is only correct once the real zone is resolved, so we
      // deliberately don't hard-fail startup on this.
    }

    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const darwin = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: false,
      requestSoundPermission: true,
    );
    await _plugin.initialize(
      settings: const InitializationSettings(android: android, iOS: darwin),
    );

    await _plugin
        .resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin
        >()
        ?.requestPermissions(alert: true, badge: false, sound: true);
    final androidImpl = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    await androidImpl?.requestNotificationsPermission();
    await androidImpl?.requestExactAlarmsPermission();

    _ready = true;
  }

  /// Cancel the previous backup set and schedule fresh notifications for the
  /// current enabled alarms. Safe (and intended) to call on every alarm change;
  /// no-op until [init] has completed.
  Future<void> syncAlarms(List<Alarm> alarms) async {
    if (!_ready) return;
    try {
      await _plugin.cancelAll();
      for (final alarm in alarms) {
        if (!alarm.isActive) continue;
        final weekdays = _activeWeekdays(alarm);
        if (weekdays.isEmpty) {
          // Active but no weekday selected → a one-shot at the next occurrence.
          await _schedule(
            id: _notificationId(alarm.id, 0),
            alarm: alarm,
            when: _nextInstance(alarm.hour, alarm.minute),
            weekly: false,
          );
        } else {
          for (final weekday in weekdays) {
            await _schedule(
              id: _notificationId(alarm.id, weekday),
              alarm: alarm,
              when: _nextInstance(alarm.hour, alarm.minute, weekday: weekday),
              weekly: true,
            );
          }
        }
      }
    } catch (e, s) {
      // Never let a scheduling failure crash an alarm edit — the BLE path and
      // local save are the source of truth; the notification is a backup.
      debugPrint('NotificationService.syncAlarms failed: $e\n$s');
    }
  }

  /// Remove all scheduled backup notifications (e.g. on a full local reset).
  Future<void> cancelAll() async {
    if (!_ready) return;
    try {
      await _plugin.cancelAll();
    } catch (_) {}
  }

  /// The alarm's active days as DateTime weekdays (Mon=1 … Sun=7). The dayMask
  /// numbers days 0=Sun … 6=Sat, so Mon–Sat map straight through and Sun wraps
  /// to 7.
  List<int> _activeWeekdays(Alarm alarm) {
    final result = <int>[];
    for (var dayIndex = 0; dayIndex < 7; dayIndex++) {
      if (alarm.isDayActive(dayIndex)) {
        result.add(dayIndex == 0 ? DateTime.sunday : dayIndex);
      }
    }
    return result;
  }

  /// A distinct notification id per (alarm, weekday) so a repeating alarm's
  /// days don't overwrite each other. weekday is 1–7 (or 0 for a one-shot);
  /// alarm ids are hardware-bounded to 1–255.
  int _notificationId(int alarmId, int weekday) => alarmId * 10 + weekday;

  tz.TZDateTime _nextInstance(int hour, int minute, {int? weekday}) {
    final now = tz.TZDateTime.now(tz.local);
    var scheduled = tz.TZDateTime(
      tz.local,
      now.year,
      now.month,
      now.day,
      hour,
      minute,
    );
    if (weekday != null) {
      while (scheduled.weekday != weekday) {
        scheduled = scheduled.add(const Duration(days: 1));
      }
    }
    // Roll forward past a time that already passed today: +1 day for a one-shot,
    // +7 to stay on the chosen weekday for a repeating alarm.
    while (!scheduled.isAfter(now)) {
      scheduled = scheduled.add(Duration(days: weekday == null ? 1 : 7));
    }
    return scheduled;
  }

  Future<void> _schedule({
    required int id,
    required Alarm alarm,
    required tz.TZDateTime when,
    required bool weekly,
  }) {
    const details = NotificationDetails(
      android: AndroidNotificationDetails(
        _channelId,
        _channelName,
        channelDescription: _channelDescription,
        importance: Importance.max,
        priority: Priority.high,
        category: AndroidNotificationCategory.alarm,
        fullScreenIntent: true,
        playSound: true,
      ),
      iOS: DarwinNotificationDetails(
        presentAlert: true,
        presentSound: true,
        interruptionLevel: InterruptionLevel.timeSensitive,
      ),
    );

    return _plugin.zonedSchedule(
      id: id,
      title: alarm.displayName,
      body: 'Backup alarm — your WakeGuard clock may be unreachable.',
      scheduledDate: when,
      notificationDetails: details,
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      matchDateTimeComponents: weekly
          ? DateTimeComponents.dayOfWeekAndTime
          : null,
    );
  }
}
