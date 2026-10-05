import 'dart:convert';
import 'dart:typed_data';

import '../../../core/time/pelines_time.dart';
import '../../orders/models/order_models.dart';
import '../data/analytics_repository.dart';
import '../models/analytics_result.dart';
import 'analytics_operational_kpis.dart';
import 'analytics_visualization_data.dart';

enum AnalyticsReport { revenue, operational }

class AnalyticsCsv {
  const AnalyticsCsv(this.filename, this.bytes);
  final String filename;
  final Uint8List bytes;
}

/// Serializes existing results, never recalculates revenue or cohorts.
AnalyticsCsv buildAnalyticsCsv({
  required AnalyticsReport report,
  required AnalyticsDataset dataset,
  required AnalyticsResult result,
  required String locationId,
  required String locationName,
  required String locationSlug,
}) {
  if (dataset.locationId != locationId ||
      dataset.orders.any((o) => o.locationId != locationId) ||
      !analyticsRangeIsCovered(dataset, result.current.range)) {
    throw StateError('Export unavailable: location or coverage mismatch.');
  }
  final period = result.current;
  final comparison = analyticsComparisonIsCovered(dataset, result);
  String date(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  String money(num? cents) =>
      cents == null ? '' : (cents / 100).toStringAsFixed(2);
  final rows = <List<Object?>>[
    ['Section', 'Metric', 'Value', 'Unit'],
    ['Context', 'Location', locationName, ''],
    ['Context', 'Location ID', locationId, ''],
    ['Context', 'Period start', date(period.range.startDate), 'date'],
    ['Context', 'Period end', date(period.range.endDate), 'date'],
    ['Context', 'Timezone', PelinesTime.zoneName, ''],
    ['Context', 'Coverage', 'Selected period covered by loaded history', ''],
    ['Context', 'Loaded orders', dataset.loadedCount, 'orders'],
    [
      'Context',
      'Dataset possibly truncated',
      dataset.possiblyTruncated,
      'boolean',
    ],
    [
      'Context',
      'Period in progress',
      period.range.contains(PelinesTime.now()),
      'boolean',
    ],
    ['Context', 'Comparison covered', comparison, 'boolean'],
    ['Context', 'Unavailable values', 'Empty means unavailable, not zero', ''],
  ];
  void metric(
    String name,
    Object? value,
    String unit, {
    String section = 'Current',
  }) => rows.add([section, name, value, unit]);
  metric('Order count', period.orders, 'orders');
  metric(
    'Regular orders',
    period.orderTypes[OrderType.online]!.orders,
    'orders',
  );
  metric(
    'Catering orders',
    period.orderTypes[OrderType.catering]!.orders,
    'orders',
  );
  if (report == AnalyticsReport.revenue) {
    metric('Total revenue', money(period.salesCents), 'USD');
    metric(
      'Regular revenue',
      money(period.orderTypes[OrderType.online]!.salesCents),
      'USD',
    );
    metric(
      'Catering revenue',
      money(period.orderTypes[OrderType.catering]!.salesCents),
      'USD',
    );
    metric('Average order value', money(period.averageOrderCents), 'USD');
    metric('Items sold', period.itemsSold, 'items');
    metric(
      'Period start',
      comparison ? date(result.previous.range.startDate) : '',
      'date',
      section: 'Previous',
    );
    metric(
      'Period end',
      comparison ? date(result.previous.range.endDate) : '',
      'date',
      section: 'Previous',
    );
    metric(
      'Total revenue',
      comparison ? money(result.previous.salesCents) : '',
      'USD',
      section: 'Previous',
    );
    metric(
      'Order count',
      comparison ? result.previous.orders : '',
      'orders',
      section: 'Previous',
    );
    metric(
      'Average order value',
      comparison ? money(result.previous.averageOrderCents) : '',
      'USD',
      section: 'Previous',
    );
    metric(
      'Items sold',
      comparison ? result.previous.itemsSold : '',
      'items',
      section: 'Previous',
    );
    for (final (rank, product) in period.products.take(5).indexed) {
      final section = 'Product ${rank + 1}';
      metric('Name', product.name, '', section: section);
      metric('Quantity sold', product.quantity, 'items', section: section);
      metric(
        'Line sales before order discounts',
        money(product.lineSalesCents),
        'USD',
        section: section,
      );
    }
  } else {
    final operational = AnalyticsOperationalKpis(dataset, period.range);
    metric('Waiting', operational.waiting, 'orders');
    metric('Ready', operational.ready, 'orders');
    metric('Completed', period.completed, 'orders');
    metric('Cancelled', period.cancelled, 'orders');
    metric('In progress', period.inProgress, 'orders');
    metric('Unknown status', period.unknownStatusOrders, 'orders');
    metric(
      'Cancellation rate',
      period.cancellationRate?.toStringAsFixed(2) ?? '',
      'percent',
    );
    metric(
      'Peak Hour',
      AnalyticsOperationalKpis.leaders(operational.hours)
          .map(
            (h) =>
                '${h.toString().padLeft(2, '0')}:00–${((h + 1) % 24).toString().padLeft(2, '0')}:00',
          )
          .join('; '),
      'Pacific hour',
    );
    metric(
      'Peak Hour orders per tied group',
      operational.hours.any((n) => n > 0)
          ? AnalyticsOperationalKpis.maximum(operational.hours)
          : '',
      'orders',
    );
    const days = [
      'Monday',
      'Tuesday',
      'Wednesday',
      'Thursday',
      'Friday',
      'Saturday',
      'Sunday',
    ];
    metric(
      'Busiest Day',
      AnalyticsOperationalKpis.leaders(operational.weekdays)
          .map((i) => days[i])
          .join('; '),
      'Pacific weekday',
    );
    metric(
      'Busiest Day orders per tied group',
      operational.weekdays.any((n) => n > 0)
          ? AnalyticsOperationalKpis.maximum(operational.weekdays)
          : '',
      'orders',
    );
    for (final entry in period.fulfillmentTypes.entries) {
      metric('${entry.key.name} orders', entry.value.orders, 'orders');
    }
  }
  String escape(Object? value) {
    var text = value?.toString() ?? '';
    // Neutralize spreadsheet formulas in text fields (including product names).
    if (value is String &&
        RegExp(r'^[=+@\-\t\r]').hasMatch(text) &&
        num.tryParse(text) == null) {
      text = "'$text";
    }
    return RegExp('[",\r\n]').hasMatch(text)
        ? '"${text.replaceAll('"', '""')}"'
        : text;
  }

  var slug = locationSlug
      .replaceAll(RegExp(r'[^a-zA-Z0-9_-]+'), '-')
      .replaceAll(RegExp(r'^-+|-+$'), '');
  if (slug.isEmpty) slug = 'location';
  if (slug.length > 80) slug = slug.substring(0, 80);
  final stamp =
      '${date(period.range.startDate).replaceAll('-', '')}-${date(period.range.endDate).replaceAll('-', '')}';
  return AnalyticsCsv(
    'pelines-${report.name}-$slug-$stamp.csv',
    Uint8List.fromList(
      utf8.encode(
        '\uFEFF${rows.map((r) => r.map(escape).join(',')).join('\r\n')}\r\n',
      ),
    ),
  );
}
