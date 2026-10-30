import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pelines_admin_app/core/api/api_exception.dart';
import 'package:pelines_admin_app/features/menu/data/menu_repository.dart';
import 'package:pelines_admin_app/features/menu/models/menu_models.dart';
import 'package:pelines_admin_app/features/menu/presentation/product_form_screen.dart';
import 'package:pelines_admin_app/features/menu/presentation/menu_screens.dart';

import 'catering_catalog_test.dart' as catalog;
import 'regular_catalog_test.dart' show SavingRepo;

class NewItemRepo extends SavingRepo {
  int attempts = 0;
  bool reject = false;
  bool longLabels = false;
  @override
  Future<List<MenuCategory>> getCategories({
    required String locationSlug,
    required MenuKind kind,
  }) async {
    final categories = await super.getCategories(
      locationSlug: locationSlug,
      kind: kind,
    );
    if (!longLabels) return categories;
    return [
      for (final c in categories)
        MenuCategory(
          id: c.id,
          locationId: c.locationId,
          name: 'A long category name that remains readable in the expanded selector',
          slug: c.slug,
          sortOrder: c.sortOrder,
          isActive: c.isActive,
          kind: c.kind,
          rawKind: c.rawKind,
          createdAt: c.createdAt,
          updatedAt: c.updatedAt,
        ),
    ];
  }

  Completer<void>? hold;
  @override
  Future<MenuProduct> createProduct(ProductWriteInput input) async {
    attempts++;
    await hold?.future;
    if (reject) {
      throw const ApiException(message: 'Creation rejected', statusCode: 400);
    }
    return super.createProduct(input);
  }

  @override
  Future<List<MenuProduct>> getProducts({
    required String locationSlug,
    required String categoryId,
  }) async => [
    if (categoryId == 'c') catalog.product('p', 'c'),
    if (categoryId == 'd')
      MenuProduct(
        id: 'dessert',
        categoryId: 'd',
        name: 'Dessert',
        slug: 'dessert',
        priceCents: 300,
        isAvailable: true,
        sortOrder: 0,
        createdAt: DateTime(2026),
        updatedAt: DateTime(2026),
        subcategory: 'Desserts',
        modifierGroups: const [],
      ),
    if (saved != null && saved!.categoryId == categoryId)
      await getProduct('saved'),
  ];
}

Finder field(String id) => find.byKey(ValueKey('new-menu-item-$id'));
Finder get save => find.widgetWithText(FilledButton, 'Save');
Future<void> reveal(WidgetTester tester, Finder target) async {
  await Scrollable.ensureVisible(tester.element(target), alignment: .5);
  await tester.pumpAndSettle();
}

Future<void> launch(
  WidgetTester tester,
  NewItemRepo repo, {
  double width = 390,
  double height = 844,
  double scale = 1,
  String lang = 'en',
}) async {
  await catalog.mount(tester, repo, width: width, scale: scale, lang: lang);
  tester.view.physicalSize = Size(width, height);
  await tester.pumpAndSettle();
  final button = find.widgetWithText(
    FilledButton,
    lang == 'en' ? 'New Item' : 'Nuevo producto',
  );
  await reveal(tester, button);
  await tester.tap(button);
  await tester.pumpAndSettle();
  final selector = find.byKey(const ValueKey('store-edit-category-'));
  await reveal(tester, selector);
  await tester.tap(selector);
  await tester.pumpAndSettle();
  await tester.tap(
    repo.longLabels
        ? find.byType(DropdownMenuItem<String>).first
        : find.text('Category c').last,
  );
  await tester.pumpAndSettle();
}

Future<void> enter(WidgetTester tester, String id, String text) async {
  await reveal(tester, field(id));
  await tester.enterText(field(id), text);
  await tester.pump();
}

void main() {
  testWidgets(
    'Store opens sheet with external labels, real limits and no fake image or addon writes',
    (tester) async {
      final repo = NewItemRepo();
      await launch(tester, repo);
      expect(find.byType(BottomSheet), findsOneWidget);
      expect(find.text('New menu item'), findsOneWidget);
      expect(
        tester.widget<TextField>(field('name')).decoration!.labelText,
        isNull,
      );
      expect(
        tester.widget<TextField>(field('name')).decoration!.hintText,
        'e.g. Chicken Quesadilla',
      );
      expect(tester.widget<TextField>(field('name')).maxLength, 120);
      expect(tester.widget<TextField>(field('description')).maxLength, isNull);
      expect(
        tester.widget<TextField>(field('description')).decoration!.counterText,
        '0',
      );
      expect(tester.widget<TextField>(field('disclaimer')).maxLength, 300);
      expect(
        tester
            .widget<CheckboxListTile>(
              find.widgetWithText(CheckboxListTile, 'Active'),
            )
            .value,
        isTrue,
      );
      expect(find.text('No image yet'), findsOneWidget);
      expect(
        tester
            .widget<OutlinedButton>(
              find.widgetWithText(OutlinedButton, 'Upload image'),
            )
            .onPressed,
        isNull,
      );
      expect(
        tester
            .widget<OutlinedButton>(
              find.widgetWithText(OutlinedButton, 'Add add-on group'),
            )
            .onPressed,
        isNull,
      );
      expect(
        find.text('Save the item to add its photo and modifiers.'),
        findsOneWidget,
      );
      expect(find.text('Reuse add-ons from another item'), findsNothing);
      expect(repo.attempts, 0);
      expect(repo.imagePatches, 0);
    },
  );

  testWidgets(
    'long category labels fit selected field and expanded menu at 2x',
    (tester) async {
      await launch(
        tester,
        NewItemRepo()..longLabels = true,
        width: 320,
        scale: 2,
      );
      final dropdown = find.byKey(const ValueKey('store-edit-category-c'));
      await reveal(tester, dropdown);
      expect(tester.takeException(), isNull);
      await tester.tap(dropdown);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(
        find.text(
          'A long category name that remains readable in the expanded selector',
        ),
        findsWidgets,
      );
    },
  );

  testWidgets('existing price and name validation preserved', (tester) async {
    final repo = NewItemRepo();
    await launch(tester, repo);
    expect(tester.widget<FilledButton>(save).onPressed, isNull);
    await enter(tester, 'name', 'Real item');
    for (final invalid in ['', '-1', '1,50', '12.345']) {
      await enter(tester, 'price', invalid);
      expect(tester.widget<FilledButton>(save).onPressed, isNull);
    }
    await enter(tester, 'price', '12.50');
    expect(tester.widget<FilledButton>(save).onPressed, isNotNull);
    await enter(tester, 'name', '   ');
    expect(tester.widget<FilledButton>(save).onPressed, isNull);
    tester.widget<TextField>(field('name')).controller!.text = 'x' * 121;
    await tester.pump();
    expect(tester.widget<FilledButton>(save).onPressed, isNull);
    expect(repo.attempts, 0);
  });

  testWidgets(
    'category and subcategory use scoped data and None can clear selection',
    (tester) async {
      await launch(tester, NewItemRepo());
      var dropdown = find.byKey(const ValueKey('store-subcategory-c-'));
      await reveal(tester, dropdown);
      await tester.tap(dropdown);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Buffet').last);
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextField>(field('subcategory-name')).controller!.text,
        'Buffet',
      );
      dropdown = find.byKey(const ValueKey('store-subcategory-c-Buffet'));
      await reveal(tester, dropdown);
      await tester.tap(dropdown);
      await tester.pumpAndSettle();
      await tester.tap(find.text('None').last);
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextField>(field('subcategory-name')).controller!.text,
        isEmpty,
      );
      final category = find.byKey(const ValueKey('store-edit-category-c'));
      await reveal(tester, category);
      await tester.tap(category);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Category d').last);
      await tester.pumpAndSettle();
      dropdown = find.byKey(const ValueKey('store-subcategory-d-'));
      await reveal(tester, dropdown);
      await tester.tap(dropdown);
      await tester.pumpAndSettle();
      expect(find.text('Desserts').last, findsOneWidget);
      await tester.tap(find.text('Desserts').last);
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextField>(field('subcategory-name')).controller!.text,
        'Desserts',
      );
    },
  );

  testWidgets('save persists supported fields and keeps existing detail flow', (
    tester,
  ) async {
    final repo = NewItemRepo();
    await launch(tester, repo);
    await enter(tester, 'name', 'New meal');
    await enter(tester, 'price', '15.25');
    await enter(tester, 'description', 'Description from administrator');
    await enter(tester, 'disclaimer', 'Existing disclaimer field');
    await enter(tester, 'subcategory-name', 'Custom label');
    final active = find.widgetWithText(CheckboxListTile, 'Active');
    await reveal(tester, active);
    await tester.tap(active);
    await tester.pump();
    await tester.tap(save);
    await tester.pumpAndSettle();
    expect(repo.attempts, 1);
    expect(repo.saved!.priceCents, 1525);
    expect(repo.saved!.isAvailable, isFalse);
    expect(repo.saved!.sortOrder, 0);
    expect(repo.saved!.servesCount, isNull);
    expect(repo.saved!.subcategory, 'Custom label');
    expect(repo.saved!.description, 'Description from administrator');
    expect(repo.saved!.disclaimer, 'Existing disclaimer field');
    expect(find.byType(ProductFormScreen), findsNothing);
    expect(find.byType(BottomSheet), findsNothing);
    expect(
      tester
          .widget<MenuProductDetailScreen>(find.byType(MenuProductDetailScreen))
          .kind,
      MenuKind.store,
    );
    expect(find.text('Change Image'), findsOneWidget);
  });

  testWidgets(
    'server error retains draft and duplicate submits are blocked during retry',
    (tester) async {
      final repo = NewItemRepo()..reject = true;
      await launch(tester, repo);
      await enter(tester, 'name', 'Preserved meal');
      await enter(tester, 'price', '9.99');
      await tester.tap(save);
      await tester.pumpAndSettle();
      expect(find.text('Creation rejected').hitTestable(), findsOneWidget);
      expect(
        tester.widget<TextField>(field('name')).controller!.text,
        'Preserved meal',
      );
      repo.reject = false;
      repo.hold = Completer<void>();
      final callback = tester.widget<FilledButton>(save).onPressed!;
      callback();
      callback();
      await tester.pump();
      await tester.pump();
      expect(repo.attempts, 2);
      expect(tester.widget<TextField>(field('name')).enabled, isFalse);
      repo.hold!.complete();
      await tester.pumpAndSettle();
      expect(repo.attempts, 2);
      expect(find.byType(ProductFormScreen), findsNothing);
    },
  );

  for (final close in [false, true]) {
    testWidgets('Cancel or X without writes close=$close', (tester) async {
      final repo = NewItemRepo();
      await launch(tester, repo);
      await tester.tap(
        close
            ? find.byTooltip('Close')
            : find.widgetWithText(OutlinedButton, 'Cancel'),
      );
      await tester.pumpAndSettle();
      expect(repo.attempts, 0);
      expect(find.byType(ProductFormScreen), findsNothing);
    });
  }

  testWidgets('Back protects dirty values and discard does not persist', (
    tester,
  ) async {
    final repo = NewItemRepo();
    await launch(tester, repo);
    await enter(tester, 'name', 'Draft meal');
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('Discard unsaved changes?'), findsOneWidget);
    await tester.tap(find.text('Stay'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<TextField>(field('name')).controller!.text,
      'Draft meal',
    );
    expect(repo.attempts, 0);
  });

  for (final width in [320.0, 390.0, 900.0]) {
    for (final lang in ['en', 'es']) {
      testWidgets('New menu item responsive $width $lang 2x keyboard', (
        tester,
      ) async {
        await launch(
          tester,
          NewItemRepo(),
          width: width,
          height: 720,
          scale: 2,
          lang: lang,
        );
        expect(tester.takeException(), isNull);
        expect(
          find.descendant(
            of: find.byType(ProductFormScreen),
            matching: find.text(
              lang == 'en' ? 'New menu item' : 'Nuevo producto',
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
        expect(tester.getRect(action).bottom, lessThanOrEqualTo(460));
        await reveal(tester, field('disclaimer'));
        expect(tester.takeException(), isNull);
        expect(
          tester.getRect(field('disclaimer')).right,
          lessThanOrEqualTo(width),
        );
      });
    }
  }
}
