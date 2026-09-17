import '../../../core/time/pelines_time.dart';

enum AnalyticsDatePreset { today, last7Days, last30Days, last90Days }

/// UTC values here encode calendar dates, not instants or 24-hour Pacific days.
class AnalyticsDateRange {
  AnalyticsDateRange.custom(DateTime from, DateTime through)
    : this._(from, through, null);

  AnalyticsDateRange._(DateTime from, DateTime through, this.preset)
    : startDate = DateTime.utc(from.year, from.month, from.day),
      endDate = DateTime.utc(through.year, through.month, through.day) {
    if (endDate.isBefore(startDate)) {
      throw ArgumentError('End date must not precede start date.');
    }
  }

  factory AnalyticsDateRange.preset(
    AnalyticsDatePreset preset, {
    DateTime? now,
  }) {
    final today = PelinesTime.inPacific(now ?? PelinesTime.now());
    final days = switch (preset) {
      AnalyticsDatePreset.today => 1,
      AnalyticsDatePreset.last7Days => 7,
      AnalyticsDatePreset.last30Days => 30,
      AnalyticsDatePreset.last90Days => 90,
    };
    return AnalyticsDateRange._(
      DateTime.utc(today.year, today.month, today.day - days + 1),
      today,
      preset,
    );
  }

  final DateTime startDate;
  final DateTime endDate;
  final AnalyticsDatePreset? preset;
  int get dayCount => endDate.difference(startDate).inDays + 1;
  AnalyticsDateRange get previous => AnalyticsDateRange.custom(
    DateTime.utc(startDate.year, startDate.month, startDate.day - dayCount),
    DateTime.utc(startDate.year, startDate.month, startDate.day - 1),
  );

  bool contains(DateTime instant) {
    final local = PelinesTime.inPacific(instant);
    final date = DateTime.utc(local.year, local.month, local.day);
    return !date.isBefore(startDate) && !date.isAfter(endDate);
  }

  Iterable<DateTime> get dates sync* {
    for (var i = 0; i < dayCount; i++) {
      yield DateTime.utc(startDate.year, startDate.month, startDate.day + i);
    }
  }
}
