import '../../../core/time/pelines_time.dart';
import 'order_models.dart';

enum OrdersDateFilter {
  today('Today'),
  tomorrow('Tomorrow'),
  upcoming('Upcoming'),
  allDates('All dates'),
  chooseDate('Choose date…');

  const OrdersDateFilter(this.label);
  final String label;
}

// Date-only UTC values are calendar coordinates, not instants. Advancing one
// calendar day here remains correct across Pacific's 23- and 25-hour days.
DateTime pacificDate(DateTime instant) {
  final value = PelinesTime.inPacific(instant);
  return DateTime.utc(value.year, value.month, value.day);
}

List<OrderSummary> filterOrdersByDate(
  List<OrderSummary> orders,
  OrdersDateFilter filter, {
  DateTime? chosenDate,
  DateTime? now,
}) {
  final today = pacificDate(now ?? PelinesTime.now());
  final tomorrow = DateTime.utc(today.year, today.month, today.day + 1);
  final chosen = chosenDate == null
      ? null
      : DateTime.utc(chosenDate.year, chosenDate.month, chosenDate.day);
  return orders.where((order) {
    final day = pacificDate(order.operationalAt);
    return switch (filter) {
      OrdersDateFilter.today => day == today,
      OrdersDateFilter.tomorrow => day == tomorrow,
      OrdersDateFilter.upcoming => !day.isBefore(tomorrow),
      OrdersDateFilter.allDates => true,
      OrdersDateFilter.chooseDate => day == chosen,
    };
  }).toList();
}

DateTime dayInMonth(DateTime selectedDay, int year, int month) {
  final lastDay = DateTime(year, month + 1, 0).day;
  return DateTime(year, month, selectedDay.day.clamp(1, lastDay));
}
