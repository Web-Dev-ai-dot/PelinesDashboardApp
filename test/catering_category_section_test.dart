import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pelines_admin_app/core/api/api_exception.dart';
import 'package:pelines_admin_app/features/locations/providers/locations_providers.dart';
import 'package:pelines_admin_app/features/menu/data/menu_repository.dart';
import 'package:pelines_admin_app/features/menu/models/menu_models.dart';
import 'package:pelines_admin_app/features/menu/providers/catering_actions.dart';

import 'analytics_providers_test.dart' show FakeLocation;
import 'catering_catalog_test.dart' as catalog;

MenuCategory makeCategory(String id, String name, int order, bool active) =>
    MenuCategory(
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
      subcategorySchedules: {
        'Buffet': {
          'enabled': true,
          'days': [0],
          'start': '11:00',
          'end': '15:00',
        },
      },
    );

class CategoriesRepo extends catalog.Repo {
  List<MenuCategory> rows = [
    makeCategory(
      'd',
      'Saved inactive category with a very long name that must remain fully readable',
      8,
      false,
    ),
    makeCategory('c', 'Real catering category', 2, true),
  ];
  int writes = 0;
  bool reject = false;
  Completer<void>? hold;
  CategoryWriteInput? submitted;
  @override
  Future<List<MenuCategory>> getCategories({
    required String locationSlug,
    required MenuKind kind,
  }) async => locationSlug == 'a' ? [...rows] : [];
  @override
  Future<MenuCategory> getCategory(String id) async =>
      rows.firstWhere((c) => c.id == id);
  @override
  Future<MenuCategory> updateCategory(
    String id,
    CategoryWriteInput input,
  ) async {
    writes++;
    submitted = input;
    await hold?.future;
    if (reject) {
      throw const ApiException(
        message: 'Category update rejected',
        statusCode: 403,
      );
    }
    final updated = makeCategory(
      id,
      input.name,
      input.sortOrder,
      input.isActive,
    );
    rows = [
      for (final row in rows)
        if (row.id == id) updated else row,
    ];
    return updated;
  }
}

class CategoriesDelete extends catalog.DeleteApi {
  CategoriesDelete(this.repo);
  final CategoriesRepo repo;
  bool reject = false;
  @override
  Future<void> delete(CateringEntity entity, String id) async {
    calls++;
    if (reject) throw const ApiException(message: 'Deletion rejected');
    repo.rows.removeWhere((c) => c.id == id);
  }
}

Finder get section => find.byKey(const ValueKey('catering-categories-section'));
Finder row(String id) => find.byKey(ValueKey('catering-category-row-a-$id'));
Finder active(String id) => find.byKey(ValueKey('category-active-$id'));
Finder edit(String id) => find.byKey(ValueKey('category-edit-$id'));
Future<void> show(WidgetTester tester, Finder target) async {
  await Scrollable.ensureVisible(tester.element(target), alignment: 0.5);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'section is last, uses all real categories sorted by display order and survives filters',
    (tester) async {
      final repo = CategoriesRepo();
      await catalog.mount(tester, repo);
      expect(
        tester.getTopLeft(section).dy,
        greaterThan(tester.getBottomLeft(find.text('Meal b')).dy),
      );
      expect(
        tester.getTopLeft(row('c')).dy,
        lessThan(tester.getTopLeft(row('d')).dy),
      );
      expect(
        find.descendant(of: row('c'), matching: find.text('Display order: 2')),
        findsOneWidget,
      );
      expect(tester.widget<Checkbox>(active('c')).value, isTrue);
      expect(tester.widget<Checkbox>(active('d')).value, isFalse);
      await show(tester, find.byKey(const ValueKey('catering-category-c')));
      await tester.tap(find.byKey(const ValueKey('catering-category-c')));
      await tester.pumpAndSettle();
      expect(row('d'), findsOneWidget);
      await show(tester, find.byKey(const ValueKey('catering-search')));
      await tester.enterText(
        find.descendant(
          of: find.byKey(const ValueKey('catering-search')),
          matching: find.byType(TextField),
        ),
        'no such product',
      );
      await tester.pumpAndSettle();
      expect(row('c'), findsOneWidget);
      expect(row('d'), findsOneWidget);
    },
  );

  testWidgets(
    'toggle persists, refreshes catalog and prevents concurrent writes without optimistic state',
    (tester) async {
      final repo = CategoriesRepo()..hold = Completer<void>();
      await catalog.mount(tester, repo);
      await show(tester, active('c'));
      await tester.tap(active('c'));
      await tester.pump();
      await tester.pump();
      expect(repo.writes, 1);
      expect(repo.submitted!.isActive, isFalse);
      expect(repo.submitted!.name, 'Real catering category');
      expect(repo.submitted!.sortOrder, 2);
      expect(
        repo.submitted!.toUpdateJson().containsKey('subcategorySchedulesJson'),
        isFalse,
      );
      expect(tester.widget<Checkbox>(active('c')).value, isTrue);
      expect(tester.widget<Checkbox>(active('c')).onChanged, isNull);
      expect(tester.widget<IconButton>(edit('c')).onPressed, isNull);
      expect(
        tester
            .widget<IconButton>(
              find.descendant(
                of: row('c'),
                matching: find.byKey(const ValueKey('catering-delete-c')),
              ),
            )
            .onPressed,
        isNull,
      );
      await tester.tap(active('c'));
      await tester.pump();
      expect(repo.writes, 1);
      repo.hold!.complete();
      await tester.pumpAndSettle();
      expect(tester.widget<Checkbox>(active('c')).value, isFalse);
      expect(
        find.descendant(of: row('c'), matching: find.text('Inactive')),
        findsOneWidget,
      );
      expect(
        repo.rows
            .firstWhere((r) => r.id == 'c')
            .subcategorySchedules!['Buffet']['start'],
        '11:00',
      );
    },
  );

  testWidgets(
    'rejected toggle retains previous persisted state and permits retry',
    (tester) async {
      final repo = CategoriesRepo()..reject = true;
      await catalog.mount(tester, repo);
      await show(tester, active('d'));
      await tester.tap(active('d'));
      await tester.pumpAndSettle();
      expect(tester.widget<Checkbox>(active('d')).value, isFalse);
      expect(find.text('Category update rejected'), findsOneWidget);
      repo.reject = false;
      await tester.tap(active('d'));
      await tester.pumpAndSettle();
      expect(tester.widget<Checkbox>(active('d')).value, isTrue);
      expect(repo.writes, 2);
    },
  );

  testWidgets('Edit reuses T13 modal, saves order and refreshes sorted list', (
    tester,
  ) async {
    final repo = CategoriesRepo();
    await catalog.mount(tester, repo);
    await show(tester, edit('d'));
    await tester.tap(edit('d'));
    await tester.pumpAndSettle();
    expect(find.byType(Dialog), findsOneWidget);
    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('category-order')))
          .controller!
          .text,
      '8',
    );
    await tester.enterText(find.byKey(const ValueKey('category-order')), '1');
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();
    expect(find.byType(Dialog), findsNothing);
    expect(repo.writes, 1);
    expect(
      tester.getTopLeft(row('d')).dy,
      lessThan(tester.getTopLeft(row('c')).dy),
    );
  });

  for (final reject in [false, true]) {
    testWidgets('Delete confirms and refreshes; rejection=$reject', (
      tester,
    ) async {
      final repo = CategoriesRepo();
      final api = CategoriesDelete(repo)..reject = reject;
      await catalog.mount(tester, repo, deletion: api);
      final del = find.descendant(
        of: row('c'),
        matching: find.byTooltip('Delete'),
      );
      await show(tester, del);
      await tester.tap(del);
      await tester.pumpAndSettle();
      expect(api.calls, 0);
      await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
      await tester.pumpAndSettle();
      expect(api.calls, 0);
      await tester.tap(del);
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
      await tester.pumpAndSettle();
      expect(api.calls, 1);
      expect(row('c'), reject ? findsOneWidget : findsNothing);
      if (reject) {
        expect(find.text('ApiException: Deletion rejected'), findsOneWidget);
      }
    });
  }

  testWidgets('empty categories and switching location never show stale rows', (
    tester,
  ) async {
    final repo = CategoriesRepo();
    await catalog.mount(tester, repo);
    final container = ProviderScope.containerOf(tester.element(section));
    (container.read(currentLocationProvider.notifier) as FakeLocation)
        .setLocation('b');
    await tester.pumpAndSettle();
    expect(row('c'), findsNothing);
    expect(find.text('No categories yet.'), findsOneWidget);
    expect(repo.writes, 0);
  });

  for (final width in [320.0, 800.0, 1440.0]) {
    for (final lang in ['en', 'es']) {
      for (final scale in [1.0, 2.0]) {
        testWidgets('categories responsive $width $lang $scale', (
          tester,
        ) async {
          final repo = CategoriesRepo();
          await catalog.mount(
            tester,
            repo,
            width: width,
            lang: lang,
            scale: scale,
          );
          await show(tester, row('d'));
          expect(tester.takeException(), isNull);
          expect(
            find.descendant(
              of: section,
              matching: find.text(lang == 'en' ? 'Categories' : 'Categorías'),
            ),
            findsOneWidget,
          );
          expect(
            find.descendant(
              of: row('d'),
              matching: find.text(repo.rows.first.name),
            ),
            findsOneWidget,
          );
          final rect = tester.getRect(row('d'));
          expect(rect.left, greaterThanOrEqualTo(0));
          expect(rect.right, lessThanOrEqualTo(width));
          expect(tester.getSize(edit('d')).height, greaterThanOrEqualTo(48));
          if (width == 1440 && scale == 1) {
            expect(
              find.descendant(of: section, matching: find.text('CATEGORY')),
              lang == 'en' ? findsOneWidget : findsNothing,
            );
          }
        });
      }
    }
  }
}
