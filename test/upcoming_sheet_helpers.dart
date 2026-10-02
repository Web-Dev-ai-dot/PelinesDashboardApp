import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';

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
  await upcomingTap(tester, 'upcoming-$bound');
  await tester.tap(find.byIcon(Icons.edit_outlined));
  await tester.pumpAndSettle();
  await tester.enterText(
    find.byType(TextField).last,
    DateFormat.yMd().format(day),
  );
  await tester.tap(find.text('OK'));
  await tester.pumpAndSettle();
  expect(find.byType(DatePickerDialog), findsNothing);
}

Future<void> upcomingDismiss(WidgetTester tester) async {
  await tester.binding.handlePopRoute();
  await tester.pumpAndSettle();
}
