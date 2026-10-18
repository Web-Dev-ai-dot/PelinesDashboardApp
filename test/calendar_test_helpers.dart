import 'package:flutter_test/flutter_test.dart';
import 'package:pelines_admin_app/features/orders/presentation/calendar_month_grid.dart';
import 'package:pelines_admin_app/features/orders/models/orders_date_filter.dart';

// Set up a distant period directly; dedicated arrow tests exercise navigation.
Future<void> calendarPeriod(
  WidgetTester tester,
  String label,
  int value,
) async {
  final grid = tester.widget<CalendarMonthGrid>(find.byType(CalendarMonthGrid));
  final date = grid.selectedDay;
  final year = label == 'Year' || label == 'A\u00f1o';
  grid.onDateChanged(
    dayInMonth(date, year ? value : date.year, year ? date.month : value),
  );
  await tester.pumpAndSettle();
}
