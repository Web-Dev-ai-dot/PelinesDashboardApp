import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pelines_admin_app/core/api/api_exception.dart';
import 'package:pelines_admin_app/features/menu/data/menu_repository.dart';
import 'package:pelines_admin_app/features/menu/models/menu_models.dart';
import 'package:pelines_admin_app/features/menu/presentation/category_form_screen.dart';

import 'catering_catalog_test.dart' as catalog;

class CreatingRepo extends catalog.Repo {
  CreatingRepo(MenuKind kind) : super(kind: kind);
  int writes = 0;
  bool reject = false;
  Completer<void>? hold;
  CategoryWriteInput? input;
  MenuCategory? created;
  @override
  Future<MenuCategory> createCategory(CategoryWriteInput value) async {
    writes++;
    input = value;
    await hold?.future;
    if (reject) {
      throw const ApiException(message: 'Duplicate category', statusCode: 409);
    }
    return created = MenuCategory(
      id: 'new',
      locationId: value.locationId,
      kind: value.kind,
      rawKind: value.kind.name,
      name: value.name,
      slug: 'new',
      sortOrder: value.sortOrder,
      isActive: value.isActive,
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
    );
  }

  @override
  Future<MenuCategory> getCategory(String id) async =>
      id == 'new' ? created! : await super.getCategory(id);
  @override
  Future<List<MenuCategory>> getCategories({
    required String locationSlug,
    required MenuKind kind,
  }) async => [
    ...await super.getCategories(locationSlug: locationSlug, kind: kind),
    ?created,
  ];
}

Finder get name => find.byKey(const ValueKey('category-name'));
Finder get order => find.byKey(const ValueKey('category-order'));
Finder get save => find.widgetWithText(FilledButton, 'Save');

Future<void> launch(
  WidgetTester tester,
  CreatingRepo repo, {
  double width = 390,
  double height = 844,
  double scale = 1,
  String lang = 'en',
}) async {
  await catalog.mount(tester, repo, width: width, scale: scale, lang: lang);
  tester.view.physicalSize = Size(width, height);
  await tester.pumpAndSettle();
  await catalog.openCategories(tester, lang: lang);
  final label = lang == 'en' ? 'New Category' : 'Nueva categoría';
  final button = find.widgetWithText(FilledButton, label);
  await Scrollable.ensureVisible(tester.element(button), alignment: .5);
  await tester.pumpAndSettle();
  await tester.tap(button);
  await tester.pumpAndSettle();
}

void main() {
  for (final kind in [MenuKind.store, MenuKind.catering]) {
    testWidgets('new $kind defaults and validation reuse current contract', (
      tester,
    ) async {
      final repo = CreatingRepo(kind);
      await launch(tester, repo);
      expect(find.byType(BottomSheet), findsOneWidget);
      expect(find.byType(Dialog), findsNothing);
      expect(find.text('New category'), findsOneWidget);
      expect(tester.widget<TextField>(name).controller!.text, isEmpty);
      expect(
        tester.widget<TextField>(name).decoration!.hintText,
        'e.g. Salads',
      );
      expect(tester.widget<TextField>(order).controller!.text, '0');
      expect(
        tester.widget<TextField>(order).keyboardType,
        TextInputType.number,
      );
      expect(
        tester
            .widget<CheckboxListTile>(
              find.widgetWithText(CheckboxListTile, 'Active'),
            )
            .value,
        isTrue,
      );
      expect(find.text('SUBCATEGORY VISIBILITY SCHEDULE'), findsNothing);
      expect(tester.widget<FilledButton>(save).onPressed, isNull);
      await tester.enterText(name, 'Salads');
      for (final invalid in ['-1', '1.5', '']) {
        await tester.enterText(order, invalid);
        await tester.pump();
        expect(tester.widget<FilledButton>(save).onPressed, isNull);
      }
      await tester.enterText(order, '4');
      tester.widget<TextField>(name).controller!.text = 'a' * 81;
      await tester.pump();
      expect(tester.widget<FilledButton>(save).onPressed, isNull);
      expect(repo.writes, 0);
    });

    testWidgets(
      'new $kind persists name order Active and refreshes original catalog',
      (tester) async {
        final repo = CreatingRepo(kind);
        await launch(tester, repo);
        await tester.enterText(name, 'New real category');
        await tester.enterText(order, '5');
        await tester.ensureVisible(
          find.widgetWithText(CheckboxListTile, 'Active'),
        );
        await tester.tap(find.widgetWithText(CheckboxListTile, 'Active'));
        await tester.pump();
        await tester.tap(save);
        await tester.pumpAndSettle();
        expect(repo.writes, 1);
        expect(repo.input!.kind, kind);
        expect(repo.input!.locationId, 'a');
        expect(repo.input!.sortOrder, 5);
        expect(repo.input!.isActive, isFalse);
        expect(find.byType(CategoryFormScreen), findsNothing);
        expect(find.text('New real category'), findsWidgets);
      },
    );
  }

  for (final close in [false, true]) {
    testWidgets('cancel or X without writes; close=$close', (tester) async {
      final repo = CreatingRepo(MenuKind.catering);
      await launch(tester, repo);
      await tester.tap(
        close
            ? find.byTooltip('Close')
            : find.widgetWithText(OutlinedButton, 'Cancel'),
      );
      await tester.pumpAndSettle();
      expect(find.byType(CategoryFormScreen), findsNothing);
      expect(repo.writes, 0);
    });
  }

  testWidgets('system Back protects draft and discard never creates category', (
    tester,
  ) async {
    final repo = CreatingRepo(MenuKind.store);
    await launch(tester, repo);
    await tester.enterText(name, 'Draft');
    await tester.pump();
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('Discard unsaved changes?'), findsOneWidget);
    await tester.tap(find.text('Stay'));
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(name).controller!.text, 'Draft');
    await tester.tap(find.byTooltip('Close'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Discard'));
    await tester.pumpAndSettle();
    expect(find.byType(CategoryFormScreen), findsNothing);
    expect(repo.writes, 0);
  });

  testWidgets(
    'failure retains draft; retry succeeds without duplicate submissions',
    (tester) async {
      final repo = CreatingRepo(MenuKind.catering)..reject = true;
      await launch(tester, repo);
      await tester.enterText(name, 'Preserved category');
      await tester.enterText(order, '6');
      await tester.pump();
      await tester.tap(save);
      await tester.pumpAndSettle();
      expect(find.text('Duplicate category'), findsOneWidget);
      expect(
        tester.widget<TextField>(name).controller!.text,
        'Preserved category',
      );
      expect(tester.widget<TextField>(order).controller!.text, '6');
      repo.reject = false;
      repo.hold = Completer<void>();
      final callback = tester.widget<FilledButton>(save).onPressed!;
      callback();
      callback();
      await tester.pump();
      await tester.pump();
      expect(repo.writes, 2);
      expect(
        tester
            .widget<IconButton>(
              find.byWidgetPredicate(
                (widget) => widget is IconButton && widget.tooltip == 'Close',
              ),
            )
            .onPressed,
        isNull,
      );
      expect(tester.widget<TextField>(name).enabled, isFalse);
      repo.hold!.complete();
      await tester.pumpAndSettle();
      expect(find.byType(CategoryFormScreen), findsNothing);
      expect(repo.writes, 2);
    },
  );

  for (final width in [320.0, 390.0, 900.0]) {
    for (final lang in ['en', 'es']) {
      testWidgets('responsive new category $width $lang 2x keyboard', (
        tester,
      ) async {
        await launch(
          tester,
          CreatingRepo(MenuKind.catering),
          width: width,
          height: 680,
          scale: 2,
          lang: lang,
        );
        expect(tester.takeException(), isNull);
        expect(
          find.descendant(
            of: find.byType(CategoryFormScreen),
            matching: find.text(
              lang == 'en' ? 'New category' : 'Nueva categoría',
            ),
          ),
          findsOneWidget,
        );
        expect(
          find.byType(BottomSheet),
          width < 600 ? findsOneWidget : findsNothing,
        );
        expect(
          find.byType(Dialog),
          width >= 600 ? findsOneWidget : findsNothing,
        );
        tester.view.viewInsets = const FakeViewPadding(bottom: 260);
        addTearDown(tester.view.resetViewInsets);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        final action = find.widgetWithText(
          FilledButton,
          lang == 'en' ? 'Save' : 'Guardar',
        );
        expect(tester.getRect(action).bottom, lessThanOrEqualTo(420));
        expect(tester.getRect(action).left, greaterThanOrEqualTo(0));
        expect(tester.getRect(action).right, lessThanOrEqualTo(width));
      });
    }
  }
}
