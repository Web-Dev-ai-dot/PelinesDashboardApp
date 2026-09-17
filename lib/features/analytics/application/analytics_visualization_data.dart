import 'package:timezone/timezone.dart' as tz;

import '../../../core/time/pelines_time.dart';
import '../data/analytics_repository.dart';
import '../models/analytics_date_range.dart';
import '../models/analytics_result.dart';

class SalesPoint {
  const SalesPoint(this.start, this.salesCents);

  /// Actual Pacific instant; repeated fall-back hours have distinct offsets.
  final tz.TZDateTime start;

  /// Null means unknown coverage or a future bucket, never an artificial zero.
  final int? salesCents;
}

tz.TZDateTime _midnight(DateTime date) {
  PelinesTime.initialize();
  return tz.TZDateTime(
    tz.getLocation(PelinesTime.zoneName),
    date.year,
    date.month,
    date.day,
  );
}

bool analyticsRangeIsCovered(
  AnalyticsDataset dataset,
  AnalyticsDateRange range,
) {
  if (!dataset.possiblyTruncated) return true;
  final oldest = dataset.oldestLoadedCreatedAt;
  return oldest != null && _midnight(range.startDate).isAfter(oldest);
}

bool analyticsComparisonIsCovered(
  AnalyticsDataset dataset,
  AnalyticsResult result,
) =>
    analyticsRangeIsCovered(dataset, result.current.range) &&
    analyticsRangeIsCovered(dataset, result.previous.range);

List<SalesPoint> analyticsSalesSeries(
  AnalyticsDataset dataset,
  AnalyticsPeriodResult period, {
  DateTime? now,
}) {
  final instant = now ?? PelinesTime.now();
  final hourly = period.range.preset == AnalyticsDatePreset.today;
  final start = _midnight(period.range.startDate);
  final endDate = period.range.endDate;
  final end = _midnight(
    DateTime.utc(endDate.year, endDate.month, endDate.day + 1),
  );
  final oldest = dataset.oldestLoadedCreatedAt;
  bool covered(DateTime bucket) =>
      !bucket.isAfter(instant) &&
      (!dataset.possiblyTruncated || oldest != null && bucket.isAfter(oldest));
  if (!hourly) {
    return List.unmodifiable(
      period.dailySales.map((day) {
        final date = _midnight(day.date);
        return SalesPoint(date, covered(date) ? day.salesCents : null);
      }),
    );
  }
  // Iterate elapsed hours only AFTER establishing calendar-day boundaries.
  // A DST day therefore has 23 or 25 buckets, including both repeated hours.
  final totals = List<int>.filled(end.difference(start).inHours, 0);
  for (final order in dataset.orders) {
    if (order.locationId == dataset.locationId &&
        order.isSale &&
        period.range.contains(order.createdAt)) {
      totals[order.createdAt.difference(start).inHours] += order.totalCents;
    }
  }
  return List.unmodifiable(
    List.generate(totals.length, (i) {
      final hour = tz.TZDateTime.from(
        start.add(Duration(hours: i)),
        start.location,
      );
      return SalesPoint(hour, covered(hour) ? totals[i] : null);
    }),
  );
}
