import 'order_models.dart';
import 'orders_date_filter.dart';

/// Inclusive Pacific calendar dates, not UTC instants. Null bounds mean the
/// existing Upcoming default (tomorrow onward, no upper bound).
class UpcomingFilters {
  const UpcomingFilters({this.from, this.to, this.status});

  final DateTime? from, to;
  final OrderStatus? status;

  bool get isDefault => from == null && to == null && status == null;
  bool get isValid => from == null || to == null || !from!.isAfter(to!);

  bool matches(OrderSummary order) {
    final day = pacificDate(order.operationalAt);
    return (from == null || !day.isBefore(from!)) &&
        (to == null || !day.isAfter(to!)) &&
        (status == null || order.status == status);
  }
}
