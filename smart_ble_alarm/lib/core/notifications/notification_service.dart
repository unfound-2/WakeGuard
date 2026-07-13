import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;
import 'package:smart_ble_alarm/core/observability/crash_reporting_service.dart';
import 'package:smart_ble_alarm/domain/entities/alarm.dart';

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
  bool _initializing = false;
  List<Alarm>? _pendingAlarms;
  bool? _notificationsAuthorized;

  /// Whether the Android notifications permission was granted at [init] time
  /// (`true`/`false`), or `null` if not yet requested or not applicable (e.g.
  /// iOS, where permissions are handled by the Darwin init settings). Exposed
  /// so the UI can later reflect a denied state; not used for scheduling gating.
  bool? get notificationsAuthorized => _notificationsAuthorized;

  static const String _channelId = 'wakeguard_backup_alarms';
  static const String _channelName = 'Backup alarms';
  static const String _channelDescription =
      'Backup alarms in case the WakeGuard clock is unreachable.';
  static const int _eveningReminderId = 900001;
  static const String _eveningReminderChannelId = 'wakeguard_evening_reminder';
  static const String _eveningReminderChannelName = 'Evening reminder';
  static const String _eveningReminderChannelDescription =
      'A nightly check-in to set tomorrow\'s alarm.';

  /// Initialise the plugin, resolve the device timezone, and request the
  /// notification/exact-alarm permissions. Safe to call once at startup.
  Future<void> init() async {
    if (_ready || _initializing) return;
    _initializing = true;
    try {
      tzdata.initializeTimeZones();
      try {
        final info = await FlutterTimezone.getLocalTimezone();
        tz.setLocalLocation(tz.getLocation(info.identifier));
      } catch (_) {
        // The IANA lookup failed. Don't leave tz.local at its UTC default:
        // every backup alarm would then be scheduled at UTC wall-clock, which
        // is hours off for most users.
        _setFallbackLocalLocation();
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
      // Capture the grant result so the UI can later reflect a denied state.
      // `null` (iOS / no Android impl) leaves _notificationsAuthorized unset.
      final notificationsGranted = await androidImpl
          ?.requestNotificationsPermission();
      if (notificationsGranted != null) {
        _notificationsAuthorized = notificationsGranted;
      }
      await androidImpl?.requestExactAlarmsPermission();

      _ready = true;
      final queuedAlarms = _pendingAlarms;
      _pendingAlarms = null;
      if (queuedAlarms != null) {
        await syncAlarms(queuedAlarms);
      } else {
        await _syncEveningReminderFromPrefs();
      }
    } catch (error, stackTrace) {
      // The backup layer failing must never break launch — swallow the error
      // (the BLE path and local save remain the source of truth) but surface it
      // in Crashlytics so an init/permission failure isn't invisible.
      debugPrint('NotificationService.init failed: $error\n$stackTrace');
      await CrashReportingService.recordError(
        error,
        stackTrace,
        reason: 'NotificationService init failed',
      );
    } finally {
      _initializing = false;
    }
  }

  /// Best-effort local timezone for when the IANA lookup fails. Whole-hour UTC
  /// offsets map to an embedded fixed `Etc/GMT` zone; fractional (30/45-min)
  /// offsets — India +5:30, Nepal +5:45, Newfoundland −3:30, parts of
  /// Australia — build a fixed-offset zone that honours the exact minute
  /// offset so backup alarms don't fire hours off.
  void _setFallbackLocalLocation() {
    try {
      final offset = DateTime.now().timeZoneOffset;
      if (offset.inMinutes % 60 == 0) {
        final hours = offset.inHours;
        final name = hours == 0
            ? 'Etc/UTC'
            : 'Etc/GMT${hours > 0 ? '-' : '+'}${hours.abs()}';
        tz.setLocalLocation(tz.getLocation(name));
      } else {
        // No named Etc/GMT zone exists for fractional offsets, so construct a
        // single-zone fixed-offset location honouring the full Duration. A
        // location with no transitions resolves to its only zone for every
        // instant. tz.TimeZone.offset is "east of UTC", matching
        // DateTime.timeZoneOffset's sign directly — no POSIX inversion here,
        // unlike the Etc/GMT names above (whose embedded offset still ends up
        // east-of-UTC once resolved).
        final abs = offset.abs();
        final name =
            'WG/UTC${offset.isNegative ? '-' : '+'}'
            '${abs.inHours.toString().padLeft(2, '0')}:'
            '${(abs.inMinutes % 60).toString().padLeft(2, '0')}';
        final fixedZone = tz.TimeZone(offset, isDst: false, abbreviation: name);
        tz.setLocalLocation(
          tz.Location(name, const <int>[], const <int>[], <tz.TimeZone>[
            fixedZone,
          ]),
        );
      }
    } catch (_) {
      // Leave tz.local at UTC.
    }
  }

  /// Cancel the previous backup set and schedule fresh notifications for the
  /// current enabled alarms. Safe (and intended) to call on every alarm change;
  /// queues the latest alarm state until [init] has completed.
  Future<void> syncAlarms(List<Alarm> alarms) async {
    if (!_ready) {
      _pendingAlarms = List<Alarm>.unmodifiable(alarms);
      return;
    }
    try {
      // The user can turn the backup layer off in Settings; honour that here
      // (the single choke point every scheduling path goes through).
      final prefs = await SharedPreferences.getInstance();
      if (!(prefs.getBool('backupNotificationsEnabled') ?? true)) {
        await _plugin.cancelAll();
        await _syncEveningReminderFromPrefs();
        return;
      }
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
      await _syncEveningReminderFromPrefs();
    } catch (e, s) {
      // Never let a scheduling failure crash an alarm edit — the BLE path and
      // local save are the source of truth; the notification is a backup.
      debugPrint('NotificationService.syncAlarms failed: $e\n$s');
    }
  }

  /// Remove all scheduled backup notifications (e.g. on a full local reset).
  Future<void> cancelAll() async {
    if (!_ready) {
      _pendingAlarms = const <Alarm>[];
      return;
    }
    try {
      await _plugin.cancelAll();
    } catch (_) {}
  }

  Future<void> syncEveningReminder({bool? enabled}) async {
    if (!_ready) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final shouldSchedule =
          enabled ?? prefs.getBool('eveningReminderEnabled') ?? false;
      await _plugin.cancel(id: _eveningReminderId);
      if (!shouldSchedule) return;

      const details = NotificationDetails(
        android: AndroidNotificationDetails(
          _eveningReminderChannelId,
          _eveningReminderChannelName,
          channelDescription: _eveningReminderChannelDescription,
          importance: Importance.defaultImportance,
          priority: Priority.defaultPriority,
          category: AndroidNotificationCategory.reminder,
          playSound: true,
        ),
        iOS: DarwinNotificationDetails(
          presentAlert: true,
          presentSound: true,
          interruptionLevel: InterruptionLevel.active,
        ),
      );

      await _plugin.zonedSchedule(
        id: _eveningReminderId,
        title: 'WakeGuard check-in',
        body: 'Set tomorrow\'s alarm and make sure your clock is ready.',
        scheduledDate: _nextTimeOfDay(hour: 21, minute: 0),
        notificationDetails: details,
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        matchDateTimeComponents: DateTimeComponents.time,
      );
    } catch (e, s) {
      debugPrint('NotificationService.syncEveningReminder failed: $e\n$s');
    }
  }

  Future<void> _syncEveningReminderFromPrefs() => syncEveningReminder();

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

  tz.TZDateTime _nextTimeOfDay({required int hour, required int minute}) {
    final now = tz.TZDateTime.now(tz.local);
    var scheduled = tz.TZDateTime(
      tz.local,
      now.year,
      now.month,
      now.day,
      hour,
      minute,
    );
    if (!scheduled.isAfter(now)) {
      scheduled = scheduled.add(const Duration(days: 1));
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
