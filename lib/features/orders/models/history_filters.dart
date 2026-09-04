import '../../../core/time/pelines_time.dart';
import 'order_models.dart';

enum HistoryDateFilter { allLoaded, today, last7Days, last30Days }

class HistoryFilters {
  const HistoryFilters({
    this.date = HistoryDateFilter.allLoaded,
    this.orderType,
    this.fulfillment,
    this.payment,
  });

  final HistoryDateFilter date;
  final OrderType? orderType;
  final FulfillmentType? fulfillment;
  final PaymentStatus? payment;

  bool get isClear =>
      date == HistoryDateFilter.allLoaded &&
      orderType == null &&
      fulfillment == null &&
      payment == null;

  HistoryFilters copyWith({
    HistoryDateFilter? date,
    OrderType? orderType,
    FulfillmentType? fulfillment,
    PaymentStatus? payment,
    bool clearOrderType = false,
    bool clearFulfillment = false,
    bool clearPayment = false,
  }) => HistoryFilters(
    date: date ?? this.date,
    orderType: clearOrderType ? null : orderType ?? this.orderType,
    fulfillment: clearFulfillment ? null : fulfillment ?? this.fulfillment,
    payment: clearPayment ? null : payment ?? this.payment,
  );
}

List<OrderSummary> filterHistoricalOrders(
  List<OrderSummary> loaded,
  HistoryFilters filters, {
  DateTime? now,
  DateTime Function(OrderSummary order)? timestamp,
}) {
  final DateTime reference = now ?? PelinesTime.now();
  return loaded
      .where((OrderSummary order) {
        final DateTime filterTime =
            timestamp?.call(order) ?? order.operationalAt;
        if (!_matchesDate(filterTime, filters.date, reference)) {
          return false;
        }
        return (filters.orderType == null ||
                order.orderType == filters.orderType) &&
            (filters.fulfillment == null ||
                order.fulfillmentType == filters.fulfillment) &&
            (filters.payment == null || order.paymentStatus == filters.payment);
      })
      .toList(growable: false);
}

bool _matchesDate(
  DateTime instant,
  HistoryDateFilter filter,
  DateTime reference,
) {
  if (filter == HistoryDateFilter.allLoaded) return true;
  final DateTime value = PelinesTime.inPacific(instant);
  final DateTime today = PelinesTime.inPacific(reference);
  final DateTime valueDay = DateTime.utc(value.year, value.month, value.day);
  final DateTime todayDay = DateTime.utc(today.year, today.month, today.day);
  final int age = todayDay.difference(valueDay).inDays;
  final int maximum = switch (filter) {
    HistoryDateFilter.today => 0,
    HistoryDateFilter.last7Days => 6,
    HistoryDateFilter.last30Days => 29,
    HistoryDateFilter.allLoaded => 0,
  };
  return age >= 0 && age <= maximum;
}
