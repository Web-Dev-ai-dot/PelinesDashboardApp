import '../../../core/time/pelines_time.dart';
import '../../orders/models/order_models.dart';
import '../data/analytics_repository.dart';
import '../models/analytics_date_range.dart';

/// Counts of received orders, using the existing Analytics eligibility cohort.
class AnalyticsOperationalKpis {
  AnalyticsOperationalKpis(AnalyticsDataset dataset, AnalyticsDateRange range) {
    for (final order in dataset.orders) {
      if (order.locationId != dataset.locationId ||
          !order.isEligible ||
          !range.contains(order.createdAt)) {
        continue;
      }
      final local = PelinesTime.inPacific(order.createdAt);
      hours[local.hour]++;
      weekdays[local.weekday - 1]++;
      if (order.status == OrderStatus.pending) waiting++;
      if (order.status == OrderStatus.ready) ready++;
    }
  }

  final hours = List<int>.filled(24, 0);
  final weekdays = List<int>.filled(7, 0);
  int waiting = 0;
  int ready = 0;

  static int maximum(List<int> counts) =>
      counts.fold(0, (highest, count) => count > highest ? count : highest);

  static List<int> leaders(List<int> counts) {
    final highest = maximum(counts);
    return highest == 0
        ? const []
        : [
            for (var i = 0; i < counts.length; i++)
              if (counts[i] == highest) i,
          ];
  }
}
