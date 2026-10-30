import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pelines_admin_app/core/api/api_exception.dart';
import 'package:pelines_admin_app/app/theme/pelines_tokens.dart';
import 'package:pelines_admin_app/features/locations/presentation/pelines_location_context.dart';
import 'package:pelines_admin_app/features/menu/data/menu_repository.dart';
import 'package:pelines_admin_app/features/menu/models/menu_models.dart';
import 'package:pelines_admin_app/features/menu/presentation/menu_screens.dart';
import 'package:pelines_admin_app/features/menu/presentation/product_form_screen.dart';
import 'package:pelines_admin_app/features/menu/presentation/category_form_screen.dart';

import 'catering_catalog_test.dart' as catalog;
import 'catering_reorganization_test.dart' show CreatingCateringRepo;

class CreationRepo extends CreatingCateringRepo {
  int attempts = 0;
  final queriedKinds = <MenuKind>[];
  @override
  Future<List<MenuCategory>> getCategories({
    required String locationSlug,
    required MenuKind kind,
  }) async {
    queriedKinds.add(kind);
    return super.getCategories(locationSlug: locationSlug, kind: kind);
  }

  @override
  Future<MenuProduct> createProduct(ProductWriteInput value) async {
    attempts++;
    await hold?.future;
    if (reject) {
      throw const ApiException(
        message: 'Catering creation rejected',
        statusCode: 400,
      );
    }
    return super.createProduct(value);
  }
}

Finder field(String id) => find.byKey(ValueKey('new-menu-item-$id'));
Finder get save => find.widgetWithText(FilledButton, 'Save');
Future<void> reveal(WidgetTester tester, Finder finder) async {
  await Scrollable.ensureVisible(tester.element(finder), alignment: .5);
  await tester.pumpAndSettle();
}

Future<void> enter(WidgetTester tester, String id, String value) async {
  await reveal(tester, field(id));
  await tester.enterText(field(id), value);
  await tester.pump();
}

Future<void> launch(
  WidgetTester tester,
  CreationRepo repo, {
  double width = 390,
  String lang = 'en',
  double scale = 1,
}) async {
  await catalog.mount(tester, repo, width: width, lang: lang, scale: scale);
  tester.view.physicalSize = Size(width, 720);
  await tester.pumpAndSettle();
  final newItem = find.widgetWithText(
    FilledButton,
    lang == 'en' ? 'New Item' : 'Nuevo producto',
  );
  await reveal(tester, newItem);
  await tester.tap(newItem);
  await tester.pumpAndSettle();
}

Future<void> chooseCategory(WidgetTester tester) async {
  final selector = find.byKey(const ValueKey('catering-edit-category-'));
  await reveal(tester, selector);
  await tester.tap(selector);
  await tester.pumpAndSettle();
  await tester.tap(find.text('Real catering category').last);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'Catering shares creation presentation but starts without category and keeps Portions For',
    (tester) async {
      final repo = CreationRepo();
      await launch(tester, repo);
      expect(find.byType(SimpleDialog), findsNothing);
      expect(find.byType(BottomSheet), findsOneWidget);
      expect(find.text('New menu item'), findsOneWidget);
      expect(
        tester.widget<TextField>(field('name')).decoration!.labelText,
        isNull,
      );
      expect(tester.widget<TextField>(field('name')).maxLength, 120);
      expect(
        tester.widget<TextField>(field('serves')).controller!.text,
        isEmpty,
      );
      expect(
        tester
            .widget<DropdownButtonFormField<String>>(
              find.byKey(const ValueKey('catering-edit-category-')),
            )
            .initialValue,
        isNull,
      );
      expect(repo.productQueries, isNot(contains('')));
      expect(repo.queriedKinds.every((k) => k == MenuKind.catering), isTrue);
      expect(tester.widget<FilledButton>(save).onPressed, isNull);
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
      expect(repo.creates, 0);
    },
  );

  testWidgets(
    'Catering validates portions and persists all its supported fields',
    (tester) async {
      final repo = CreationRepo();
      await launch(tester, repo);
      await chooseCategory(tester);
      await enter(tester, 'name', 'Catering meal');
      await enter(tester, 'price', '22.10');
      for (final invalid in ['0', '-1', '1.5']) {
        await enter(tester, 'serves', invalid);
        expect(tester.widget<FilledButton>(save).onPressed, isNull);
      }
      await enter(tester, 'serves', '12');
      await enter(tester, 'description', 'Catering description');
      await enter(tester, 'disclaimer', 'Catering disclaimer');
      await enter(tester, 'subcategory-name', 'Custom catering label');
      final active = find.widgetWithText(CheckboxListTile, 'Active');
      await reveal(tester, active);
      await tester.tap(active);
      await tester.pump();
      await tester.tap(save);
      await tester.pumpAndSettle();
      expect(repo.creates, 1);
      expect(repo.saved!.categoryId, 'c');
      expect(repo.saved!.servesCount, 12);
      expect(repo.saved!.priceCents, 2210);
      expect(repo.saved!.isAvailable, isFalse);
      expect(repo.saved!.sortOrder, 0);
      expect(repo.saved!.description, 'Catering description');
      expect(repo.saved!.disclaimer, 'Catering disclaimer');
      expect(repo.saved!.subcategory, 'Custom catering label');
      expect(
        tester
            .widget<MenuProductDetailScreen>(
              find.byType(MenuProductDetailScreen),
            )
            .kind,
        MenuKind.catering,
      );
      expect(find.byType(BottomSheet), findsNothing);
    },
  );

  testWidgets(
    'Catering server rejection retains draft and guards duplicate retries',
    (tester) async {
      final repo = CreationRepo()..reject = true;
      await launch(tester, repo);
      await chooseCategory(tester);
      await enter(tester, 'name', 'Catering draft');
      await enter(tester, 'price', '20.00');
      await enter(tester, 'serves', '8');
      await tester.tap(save);
      await tester.pumpAndSettle();
      expect(
        find.text('Catering creation rejected').hitTestable(),
        findsOneWidget,
      );
      expect(tester.widget<TextField>(field('serves')).controller!.text, '8');
      repo.reject = false;
      final callback = tester.widget<FilledButton>(save).onPressed!;
      callback();
      callback();
      await tester.pumpAndSettle();
      expect(repo.attempts, 2);
      expect(repo.creates, 1);
      expect(find.byType(ProductFormScreen), findsNothing);
    },
  );

  testWidgets('Catering Cancel protects draft and never writes', (
    tester,
  ) async {
    final repo = CreationRepo();
    await launch(tester, repo);
    await enter(tester, 'name', 'Draft');
    await tester.tap(find.widgetWithText(OutlinedButton, 'Cancel'));
    await tester.pumpAndSettle();
    expect(find.text('Discard unsaved changes?'), findsOneWidget);
    await tester.tap(find.text('Discard'));
    await tester.pumpAndSettle();
    expect(repo.creates, 0);
    expect(find.byType(ProductFormScreen), findsNothing);
  });

  for (final width in [320.0, 390.0, 900.0]) {
    for (final lang in ['en', 'es']) {
      testWidgets(
        'Catering create and Categories action $width $lang 2x keyboard',
        (tester) async {
          final repo = CreationRepo();
          await launch(tester, repo, width: width, lang: lang, scale: 2);
          expect(tester.takeException(), isNull);
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
          await reveal(tester, field('serves'));
          expect(tester.takeException(), isNull);
          final action = find.widgetWithText(
            FilledButton,
            lang == 'en' ? 'Save' : 'Guardar',
          );
          expect(tester.getRect(action).bottom, lessThanOrEqualTo(460));
          tester.view.resetViewInsets();
          await tester.pumpAndSettle();
          await tester.tap(find.byTooltip(lang == 'en' ? 'Close' : 'Cerrar'));
          await tester.pumpAndSettle();
          await catalog.openCategories(tester, lang: lang);
          final create = find.byKey(const ValueKey('catering-new-category'));
          final section = find.byKey(
            const ValueKey('catering-categories-section'),
          );
          expect(
            find.byTooltip(lang == 'en' ? 'New Category' : 'Nueva categoría'),
            findsNothing,
          );
          expect(tester.getRect(create).left, tester.getRect(section).left);
          expect(
            tester.getRect(create).top,
            greaterThanOrEqualTo(
              tester.getRect(find.byType(PelinesLocationContext)).bottom,
            ),
          );
          expect(
            tester.getRect(create).bottom,
            lessThan(tester.getRect(section).top),
          );
          final button = find.descendant(
            of: create,
            matching: find.byType(FilledButton),
          );
          expect(
            tester
                .widget<FilledButton>(button)
                .style!
                .backgroundColor!
                .resolve({}),
            PelinesColors.brandPrimary,
          );
          await reveal(tester, button);
          await tester.tap(button);
          await tester.pumpAndSettle();
          expect(
            find.descendant(
              of: find.byType(CategoryFormScreen),
              matching: find.text(
                lang == 'en' ? 'New category' : 'Nueva categoría',
              ),
            ),
            findsOneWidget,
          );
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
}
