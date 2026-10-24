import 'package:pelines_admin_app/features/orders/presentation/upcoming_date_range.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> upcomingTap(WidgetTester tester, String key) async {
  final target = find.byKey(Key(key));
  await tester.ensureVisible(target);
  await tester.pumpAndSettle();
  await tester.tap(target);
  await tester.pumpAndSettle();
}

Future<void> upcomingType(WidgetTester tester, String type) async {
  await upcomingTap(tester, 'upcoming-sort');
  await upcomingTap(tester, 'upcoming-type-$type');
  await upcomingTap(tester, 'upcoming-sheet-apply');
}

Future<void> upcomingDate(
  WidgetTester tester,
  String bound,
  DateTime day,
) async {
  await upcomingTap(tester, 'upcoming-date-range');
  if (bound == 'to') {
    final toggle = tester.widget<SwitchListTile>(
      find.byKey(const Key('upcoming-range-no-end')),
    );
    if (toggle.value) {
      await upcomingTap(tester, 'upcoming-range-no-end');
    } else {
      final picker = tester.widget<UpcomingRangeCalendar>(
        find.byType(UpcomingRangeCalendar),
      );
      picker.onDateChanged(picker.from);
      await tester.pumpAndSettle();
    }
  } else {
    final toggle = tester.widget<SwitchListTile>(
      find.byKey(const Key('upcoming-range-no-end')),
    );
    if (!toggle.value) await upcomingTap(tester, 'upcoming-range-no-end');
  }
  tester
      .widget<UpcomingRangeCalendar>(find.byType(UpcomingRangeCalendar))
      .onDateChanged(day);
  await tester.pumpAndSettle();
  await upcomingTap(tester, 'upcoming-range-confirm');
  expect(find.byKey(const Key('upcoming-range-dialog')), findsNothing);
}

Future<void> upcomingDismiss(WidgetTester tester) async {
  await tester.binding.handlePopRoute();
  await tester.pumpAndSettle();
}
