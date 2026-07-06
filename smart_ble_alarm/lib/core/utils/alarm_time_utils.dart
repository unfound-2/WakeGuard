import '../../domain/entities/alarm.dart';

class AlarmTimeUtils {
  const AlarmTimeUtils._();

  static String formatTime(int hour, int minute, {required bool is24Hour}) {
    final m = minute.toString().padLeft(2, '0');
    if (is24Hour) {
      return '${hour.toString().padLeft(2, '0')}:$m';
    }

    var h = hour % 12;
    if (h == 0) h = 12;
    final period = hour >= 12 ? 'PM' : 'AM';
    return '${h.toString().padLeft(2, '0')}:$m $period';
  }

  static String formatDays(int dayMask) {
    if ((dayMask & 0x7F) == 0) return 'One-time';

    const orderedDays = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];
    const bits = [1, 2, 3, 4, 5, 6, 0];
    final selected = <String>[];

    for (var i = 0; i < bits.length; i++) {
      if ((dayMask & (1 << bits[i])) != 0) {
        selected.add(orderedDays[i]);
      }
    }

    return selected.join(' ');
  }

  static DateTime? nextOccurrence(Alarm alarm, {DateTime? from}) {
    if (!alarm.isActive) return null;

    final now = from ?? DateTime.now();
    final repeatMask = alarm.dayMask & 0x7F;

    for (var dayOffset = 0; dayOffset <= 7; dayOffset++) {
      final candidateDate = DateTime(
        now.year,
        now.month,
        now.day,
      ).add(Duration(days: dayOffset));
      final candidate = DateTime(
        candidateDate.year,
        candidateDate.month,
        candidateDate.day,
        alarm.hour,
        alarm.minute,
      );

      if (!candidate.isAfter(now)) continue;

      if (repeatMask == 0) {
        return candidate;
      }

      final dayBit = candidate.weekday == DateTime.sunday
          ? 0
          : candidate.weekday;
      if ((repeatMask & (1 << dayBit)) != 0) {
        return candidate;
      }
    }

    return null;
  }

  static String formatNextOccurrence(DateTime occurrence, DateTime now) {
    final today = DateTime(now.year, now.month, now.day);
    final date = DateTime(occurrence.year, occurrence.month, occurrence.day);
    final days = date.difference(today).inDays;

    if (days == 0) return 'Today';
    if (days == 1) return 'Tomorrow';

    const weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return weekdays[occurrence.weekday - 1];
  }

  /// Formats a past timestamp (e.g. the last successful clock sync) as
  /// "Today 3:42 PM", "Yesterday 09:10", or "Jun 30, 3:42 PM", honouring the
  /// app's 24-hour preference.
  static String formatSyncTimestamp(
    DateTime when, {
    required bool is24Hour,
    DateTime? now,
  }) {
    final reference = now ?? DateTime.now();
    final time = formatTime(when.hour, when.minute, is24Hour: is24Hour);
    final today = DateTime(reference.year, reference.month, reference.day);
    final day = DateTime(when.year, when.month, when.day);
    final days = today.difference(day).inDays;

    if (days == 0) return 'Today $time';
    if (days == 1) return 'Yesterday $time';

    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${months[when.month - 1]} ${when.day}, $time';
  }
}
