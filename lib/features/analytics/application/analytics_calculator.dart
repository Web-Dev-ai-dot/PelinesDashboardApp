import '../../../core/time/pelines_time.dart';
import '../../orders/models/order_models.dart';
import '../models/analytics_date_range.dart';
import '../models/analytics_order.dart';
import '../models/analytics_result.dart';

class AnalyticsCalculator {
  const AnalyticsCalculator();

  AnalyticsResult calculate(
    Iterable<AnalyticsOrder> orders, {
    required String locationId,
    required AnalyticsDateRange range,
  }) {
    final local = orders.where((o) => o.locationId == locationId).toList();
    return AnalyticsResult(
      current: _period(local, range),
      previous: _period(local, range.previous),
      loadedOrderCount: local.length,
    );
  }

  AnalyticsPeriodResult _period(
    List<AnalyticsOrder> source,
    AnalyticsDateRange range,
  ) {
    final eligible = source
        .where((o) => range.contains(o.createdAt) && o.isEligible)
        .toList();
    final sales = eligible.where((o) => o.isSale).toList();
    final products = <String, ProductSales>{};
    final daily = <DateTime, int>{for (final date in range.dates) date: 0};
    var total = 0;
    var items = 0;
    for (final order in sales) {
      total += order.totalCents;
      final local = PelinesTime.inPacific(order.createdAt);
      final date = DateTime.utc(local.year, local.month, local.day);
      daily[date] = daily[date]! + order.totalCents;
      for (final item in order.items) {
        items += item.quantity;
        final key = item.productId == null
            ? 'name:${item.productName}'
            : 'id:${item.productId}';
        final prior = products[key];
        // Stable label even if a product was renamed between orders.
        final name = prior == null || item.productName.compareTo(prior.name) < 0
            ? item.productName
            : prior.name;
        products[key] = ProductSales(
          key: key,
          productId: item.productId,
          name: name,
          quantity: (prior?.quantity ?? 0) + item.quantity,
          lineSalesCents: (prior?.lineSalesCents ?? 0) + item.lineTotalCents,
        );
      }
    }
    final ranked = products.values.toList()
      ..sort((a, b) {
        final quantity = b.quantity.compareTo(a.quantity);
        return quantity != 0 ? quantity : a.key.compareTo(b.key);
      });
    AnalyticsBreakdown breakdown(bool Function(AnalyticsOrder) matches) =>
        AnalyticsBreakdown(
          orders: eligible.where(matches).length,
          salesCents: sales
              .where(matches)
              .fold(0, (sum, o) => sum + o.totalCents),
        );
    return AnalyticsPeriodResult(
      range: range,
      salesCents: total,
      orders: eligible.length,
      salesOrderCount: sales.length,
      itemsSold: items,
      completed: eligible
          .where((o) => o.status == OrderStatus.delivered)
          .length,
      cancelled: eligible
          .where((o) => o.status == OrderStatus.cancelled)
          .length,
      inProgress: eligible
          .where(
            (o) => const {
              OrderStatus.pending,
              OrderStatus.confirmed,
              OrderStatus.preparing,
              OrderStatus.ready,
            }.contains(o.status),
          )
          .length,
      unknownStatusOrders: eligible
          .where((o) => o.status == OrderStatus.unknown)
          .length,
      dailySales: daily.entries.map((e) => DailySales(e.key, e.value)).toList(),
      products: ranked,
      orderTypes: {
        for (final type in OrderType.values)
          type: breakdown((o) => o.orderType == type),
      },
      fulfillmentTypes: {
        for (final type in FulfillmentType.values)
          type: breakdown((o) => o.fulfillmentType == type),
      },
    );
  }
}
