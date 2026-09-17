import '../../orders/models/order_models.dart';
import 'analytics_date_range.dart';

class AnalyticsBreakdown {
  const AnalyticsBreakdown({required this.orders, required this.salesCents});
  final int orders;
  final int salesCents;
}

class ProductSales {
  const ProductSales({
    required this.key,
    required this.productId,
    required this.name,
    required this.quantity,
    required this.lineSalesCents,
  });
  final String key;
  final String? productId;
  final String name;
  final int quantity;

  /// Item totals before order-level discounts; not the Sales KPI.
  final int lineSalesCents;
}

class DailySales {
  const DailySales(this.date, this.salesCents);

  /// Pacific calendar date encoded as UTC (not an instant).
  final DateTime date;
  final int salesCents;
}

class AnalyticsPeriodResult {
  AnalyticsPeriodResult({
    required this.range,
    required this.salesCents,
    required this.orders,
    required this.salesOrderCount,
    required this.itemsSold,
    required this.completed,
    required this.cancelled,
    required this.inProgress,
    required this.unknownStatusOrders,
    required List<DailySales> dailySales,
    required List<ProductSales> products,
    required Map<OrderType, AnalyticsBreakdown> orderTypes,
    required Map<FulfillmentType, AnalyticsBreakdown> fulfillmentTypes,
  }) : dailySales = List.unmodifiable(dailySales),
       products = List.unmodifiable(products),
       orderTypes = Map.unmodifiable(orderTypes),
       fulfillmentTypes = Map.unmodifiable(fulfillmentTypes);
  final AnalyticsDateRange range;
  final int salesCents, orders, salesOrderCount, itemsSold;
  final int completed, cancelled, inProgress, unknownStatusOrders;
  final List<DailySales> dailySales;
  final List<ProductSales> products;
  final Map<OrderType, AnalyticsBreakdown> orderTypes;
  final Map<FulfillmentType, AnalyticsBreakdown> fulfillmentTypes;
  double? get averageOrderCents =>
      salesOrderCount == 0 ? null : salesCents / salesOrderCount;
  double? get cancellationRate => orders == 0 ? null : cancelled * 100 / orders;
}

class MetricComparison {
  const MetricComparison(this.current, this.previous);
  final num? current, previous;
  num? get difference =>
      current == null || previous == null ? null : current! - previous!;
  double? get percentChange => difference == null || previous == 0
      ? null
      : difference! * 100 / previous!;
}

/// Results describe supplied records only; completeness is not guaranteed.
class AnalyticsResult {
  const AnalyticsResult({
    required this.current,
    required this.previous,
    required this.loadedOrderCount,
  });
  final AnalyticsPeriodResult current, previous;

  /// Count before date/payment filtering, scoped to the requested location.
  final int loadedOrderCount;
  bool get mayBeTruncated => loadedOrderCount >= 2000;
  MetricComparison get sales =>
      MetricComparison(current.salesCents, previous.salesCents);
  MetricComparison get orders =>
      MetricComparison(current.orders, previous.orders);
  MetricComparison get averageOrder =>
      MetricComparison(current.averageOrderCents, previous.averageOrderCents);
  MetricComparison get itemsSold =>
      MetricComparison(current.itemsSold, previous.itemsSold);
  double? get cancellationRatePointChange =>
      current.cancellationRate == null || previous.cancellationRate == null
      ? null
      : current.cancellationRate! - previous.cancellationRate!;
}
