import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pelines_admin_app/core/api/api_exception.dart';
import 'package:pelines_admin_app/features/menu/data/menu_repository.dart';
import 'package:pelines_admin_app/features/menu/models/menu_models.dart';

import 'catering_catalog_test.dart' as catalog;

class CategoryRepo extends catalog.Repo {
  int writes = 0;
  bool reject = false;
  String name = 'Category c';
  int order = 3;
  bool active = true;
  final schedules = <String, dynamic>{
    'Buffet': {
      'enabled': true,
      'days': [0, 4],
      'start': '11:00',
      'end': '15:00',
    },
    'A long saved subcategory name for a responsive schedule row': {
      'enabled': false,
      'days': [],
      'start': '',
      'end': '',
    },
  };
  @override
  Future<MenuCategory> getCategory(String id) async => MenuCategory(
    id: id,
    locationId: 'a',
    name: name,
    slug: id,
    sortOrder: order,
    isActive: active,
    kind: MenuKind.catering,
    rawKind: 'catering',
    createdAt: DateTime(2026),
    updatedAt: DateTime(2026),
    subcategorySchedules: schedules,
  );
  @override
  Future<MenuCategory> updateCategory(
    String id,
    CategoryWriteInput input,
  ) async {
    writes++;
    expect(
      input.toUpdateJson().containsKey('subcategorySchedulesJson'),
      isFalse,
    );
    if (reject) throw const ApiException(message: 'Rejected');
    name = input.name;
    order = input.sortOrder;
    active = input.isActive;
    return getCategory(id);
  }
}

Future<void> open(
  WidgetTester tester,
  CategoryRepo repo, {
  double width = 390,
  double scale = 1,
  String lang = 'en',
}) async {
  await catalog.mount(tester, repo, width: width, scale: scale, lang: lang);
  await catalog.openCategories(tester, lang: lang);
  final edit = find.byKey(const ValueKey('category-edit-c'));
  await Scrollable.ensureVisible(tester.element(edit), alignment: 0.5);
  await tester.pumpAndSettle();
  await tester.tap(edit);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('modal preloads fields and real read-only schedules', (
    tester,
  ) async {
    final repo = CategoryRepo();
    await open(tester, repo);
    expect(find.byType(Dialog), findsOneWidget);
    expect(find.byType(ModalBarrier), findsWidgets);
    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('category-name')))
          .controller!
          .text,
      'Category c',
    );
    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('category-order')))
          .controller!
          .text,
      '3',
    );
    expect(
      tester
          .widget<CheckboxListTile>(
            find.widgetWithText(CheckboxListTile, 'Active'),
          )
          .value,
      isTrue,
    );
    expect(
      find.descendant(of: find.byType(Dialog), matching: find.text('Buffet')),
      findsOneWidget,
    );
    expect(find.text('Mon, Fri · 11:00 – 15:00'), findsOneWidget);
    final rows = tester
        .widgetList<CheckboxListTile>(
          find.widgetWithText(CheckboxListTile, 'Always visible'),
        )
        .toList();
    expect(rows.map((r) => r.value), containsAll([true, false]));
    expect(rows.every((r) => r.onChanged == null), isTrue);
    await tester.tap(find.widgetWithText(OutlinedButton, 'Cancel'));
    await tester.pumpAndSettle();
    expect(find.byType(Dialog), findsNothing);
    expect(repo.writes, 0);
  });

  testWidgets('X protects dirty draft and discard does not write', (
    tester,
  ) async {
    final repo = CategoryRepo();
    await open(tester, repo);
    await tester.enterText(
      find.byKey(const ValueKey('category-name')),
      'Changed',
    );
    await tester.tap(find.byTooltip('Close'));
    await tester.pumpAndSettle();
    expect(find.text('Discard unsaved changes?'), findsOneWidget);
    await tester.tap(find.text('Discard'));
    await tester.pumpAndSettle();
    expect(find.byType(Dialog), findsNothing);
    expect(repo.writes, 0);
  });

  testWidgets('save updates category without changing schedules', (
    tester,
  ) async {
    final repo = CategoryRepo();
    await open(tester, repo);
    await tester.enterText(
      find.byKey(const ValueKey('category-name')),
      'Changed',
    );
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();
    expect(repo.name, 'Changed');
    expect(repo.writes, 1);
    expect(repo.schedules['Buffet']['start'], '11:00');
    expect(find.byType(Dialog), findsNothing);
  });

  testWidgets(
    'invalid order disables save and server rejection remains visible',
    (tester) async {
      final repo = CategoryRepo()..reject = true;
      await open(tester, repo);
      await tester.enterText(
        find.byKey(const ValueKey('category-order')),
        '-1',
      );
      expect(
        tester
            .widget<FilledButton>(find.widgetWithText(FilledButton, 'Save'))
            .onPressed,
        isNull,
      );
      await tester.enterText(find.byKey(const ValueKey('category-order')), '4');
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();
      expect(find.byType(Dialog), findsOneWidget);
      expect(find.text('Rejected'), findsOneWidget);
    },
  );

  for (final width in [320.0, 390.0, 900.0]) {
    for (final lang in ['en', 'es']) {
      testWidgets('responsive modal $width $lang large text and keyboard', (
        tester,
      ) async {
        await open(tester, CategoryRepo(), width: width, scale: 2, lang: lang);
        expect(tester.takeException(), isNull);
        tester.view.viewInsets = const FakeViewPadding(bottom: 280);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(
          find.byTooltip(lang == 'en' ? 'Close' : 'Cerrar'),
          findsOneWidget,
        );
        expect(
          tester
              .getRect(find.byKey(const ValueKey('category-modal-content')))
              .width,
          lessThanOrEqualTo(640),
        );
        tester.view.resetViewInsets();
      });
    }
  }
}
