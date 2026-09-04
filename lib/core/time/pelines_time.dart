import 'package:intl/intl.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

abstract final class PelinesTime {
  static const String zoneName = 'America/Los_Angeles';
  static late final tz.Location _location;
  static bool _initialized = false;

  static void initialize() {
    if (_initialized) return;
    tz_data.initializeTimeZones();
    _location = tz.getLocation(zoneName);
    _initialized = true;
  }

  static tz.TZDateTime inPacific(DateTime instant) {
    _ensureInitialized();
    return tz.TZDateTime.from(instant.toUtc(), _location);
  }

  static tz.TZDateTime now() {
    _ensureInitialized();
    return tz.TZDateTime.now(_location);
  }

  static bool isToday(DateTime instant, {DateTime? now}) {
    final tz.TZDateTime value = inPacific(instant);
    final tz.TZDateTime today = now == null
        ? PelinesTime.now()
        : inPacific(now);
    return value.year == today.year &&
        value.month == today.month &&
        value.day == today.day;
  }

  static String formatTime(DateTime instant) =>
      DateFormat('h:mm a').format(inPacific(instant));

  static String formatDateTime(DateTime instant) =>
      DateFormat('MMM d, yyyy · h:mm a').format(inPacific(instant));

  static void _ensureInitialized() {
    if (!_initialized) initialize();
  }
}
