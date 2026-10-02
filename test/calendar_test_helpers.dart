import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> calendarPeriod(
  WidgetTester tester,
  String label,
  int value,
) async {
  final field = find.byWidgetPredicate(
    (w) => w is DropdownButtonFormField<int> && w.decoration.labelText == label,
  );
  await tester.ensureVisible(field);
  await tester.pumpAndSettle();
  final dropdown = tester.widget<DropdownButton<int>>(
    find.descendant(of: field, matching: find.byType(DropdownButton<int>)),
  );
  dropdown.onChanged!(value);
  await tester.pumpAndSettle();
}
