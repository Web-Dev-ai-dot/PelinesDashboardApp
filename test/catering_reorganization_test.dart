import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:pelines_admin_app/app/theme/pelines_components.dart';
import 'package:pelines_admin_app/app/theme/pelines_tokens.dart';
import 'package:pelines_admin_app/features/menu/data/menu_repository.dart';
import 'package:pelines_admin_app/features/menu/models/menu_models.dart';
import 'package:pelines_admin_app/features/menu/presentation/menu_screens.dart';
import 'package:pelines_admin_app/features/menu/presentation/product_form_screen.dart';

import 'catering_catalog_test.dart' as catalog;
import 'catering_category_section_test.dart' show CategoriesRepo;

class CreatingCateringRepo extends CategoriesRepo {
  ProductWriteInput? saved;
  final productQueries = <String>[];
  @override
  Future<List<MenuProduct>> getProducts({
    required String locationSlug,
    required String categoryId,
  }) async {
    productQueries.add(categoryId);
    expectSync(categoryId, isNotEmpty);
    return [
      ...await super.getProducts(
        locationSlug: locationSlug,
        categoryId: categoryId,
      ),
      if (saved?.categoryId == categoryId) await getProduct('saved'),
    ];
  }

  @override
  Future<MenuProduct> createProduct(ProductWriteInput input) async {
    creates++;
    saved = input;
    return getProduct('saved');
  }

  @override
  Future<MenuProduct> getProduct(String id) async {
    final value = saved;
    if (value == null) return super.getProduct(id);
    return MenuProduct(
      id: id,
      categoryId: value.categoryId,
      name: value.name,
      slug: id,
      priceCents: value.priceCents,
      isAvailable: value.isAvailable,
      sortOrder: value.sortOrder,
      description: value.description,
      subcategory: value.subcategory,
      disclaimer: value.disclaimer,
      servesCount: value.servesCount,
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
      modifierGroups: const [],
    );
  }
}

Future<void> reveal(WidgetTester tester, Finder finder) async {
  await Scrollable.ensureVisible(tester.element(finder), alignment: .5);
  await tester.pumpAndSettle();
}

Finder field(String label) {
  final names = {'Name': 'name', 'Price (USD)': 'price'};
  final creation = find.byKey(ValueKey('new-menu-item-${names[label]}'));
  if (creation.evaluate().isNotEmpty) return creation;
  return find.byWidgetPredicate(
    (widget) => widget is TextField && widget.decoration?.labelText == label,
  );
}

void main() {
  testWidgets(
    'Categories is a separate page, plus opens existing form, Back preserves filters',
    (tester) async {
      final router = await catalog.mount(tester, catalog.Repo());
      await tester.enterText(find.byType(TextField).first, 'Meal 2');
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('catering-categories-section')),
        findsNothing,
      );
      await catalog.openCategories(tester);
      expect(find.byType(CateringCategoriesScreen), findsOneWidget);
      expect(
        GoRouterState.of(tester.element(find.byType(CateringCategoriesScreen)))
            .uri
            .path,
        '/app/menu/catering/categories',
      );
      await tester.tap(find.widgetWithText(FilledButton, 'New Category'));
      await tester.pumpAndSettle();
      expect(find.byType(BottomSheet), findsOneWidget);
      expect(find.text('New category'), findsOneWidget);
      await tester.tap(find.widgetWithText(OutlinedButton, 'Cancel'));
      await tester.pumpAndSettle();
      expect(find.byType(CateringCategoriesScreen), findsOneWidget);
      await tester.tap(find.byTooltip('Back'));
      await tester.pumpAndSettle();
      expect(
        router.routeInformationProvider.value.uri.path,
        '/app/menu/catering',
      );
      expect(
        tester
            .widget<EditableText>(find.byType(EditableText).first)
            .controller
            .text,
        'Meal 2',
      );
      expect(find.byKey(const ValueKey('menu-product-2')), findsOneWidget);
      expect(find.byKey(const ValueKey('menu-product-10')), findsNothing);
      router.go('/app/menu/catering/categories');
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Back'));
      await tester.pumpAndSettle();
      expect(
        router.routeInformationProvider.value.uri.path,
        '/app/menu/catering',
      );
      expect(find.byType(CateringCategoriesScreen), findsNothing);
    },
  );

  testWidgets(
    'New Item opens directly, requires category and saves through existing Catering flow',
    (tester) async {
      final repo = CreatingCateringRepo();
      await catalog.mount(tester, repo);
      await tester.tap(find.widgetWithText(FilledButton, 'New Item'));
      await tester.pumpAndSettle();
      expect(find.byType(SimpleDialog), findsNothing);
      expect(find.byType(ProductFormScreen), findsOneWidget);
      expect(find.text('Select a category'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('catering-edit-category-')),
        findsOneWidget,
      );
      expect(repo.productQueries, isNot(contains('')));
      await tester.enterText(field('Name'), 'Catering meal');
      await reveal(tester, field('Price (USD)'));
      await tester.enterText(field('Price (USD)'), '24.50');
      await tester.pump();
      final save = find.widgetWithText(FilledButton, 'Save');
      expect(tester.widget<FilledButton>(save).onPressed, isNull);
      final selector = find.byKey(const ValueKey('catering-edit-category-'));
      await reveal(tester, selector);
      await tester.tap(selector);
      await tester.pumpAndSettle();
      await tester.tap(find.text(repo.rows.first.name).last);
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('catering-edit-category-d')),
        findsOneWidget,
      );
      await reveal(tester, save);
      expect(tester.widget<FilledButton>(save).onPressed, isNotNull);
      await tester.tap(save);
      await tester.pumpAndSettle();
      expect(repo.creates, 1);
      expect(repo.saved!.categoryId, 'd');
      expect(repo.saved!.priceCents, 2450);
      expect(find.byType(MenuProductDetailScreen), findsOneWidget);
      expect(
        tester
            .widget<MenuProductDetailScreen>(
              find.byType(MenuProductDetailScreen),
            )
            .categoryId,
        'd',
      );
    },
  );

  testWidgets(
    'empty category list still opens direct form without arbitrary category or invalid product reads',
    (tester) async {
      final repo = CreatingCateringRepo()..rows.clear();
      await catalog.mount(tester, repo);
      await tester.tap(find.widgetWithText(FilledButton, 'New Item'));
      await tester.pumpAndSettle();
      expect(find.byType(SimpleDialog), findsNothing);
      expect(
        find.byKey(const ValueKey('catering-edit-category-')),
        findsOneWidget,
      );
      expect(find.text('Select a category before saving.'), findsOneWidget);
      expect(repo.productQueries, isEmpty);
      expect(repo.creates, 0);
      expect(
        tester
            .widget<FilledButton>(find.widgetWithText(FilledButton, 'Save'))
            .onPressed,
        isNull,
      );
    },
  );

  testWidgets(
    'category administration loads without depending on product requests',
    (tester) async {
      final repo = catalog.Repo()..fail = true;
      final router = await catalog.mount(tester, repo);
      router.go('/app/menu/catering/categories');
      await tester.pumpAndSettle();
      expect(find.byType(CateringCategoriesScreen), findsOneWidget);
      expect(
        find.byKey(const ValueKey('catering-category-row-a-c')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );

  for (final lang in ['en', 'es']) {
    for (final width in [320.0, 800.0]) {
      testWidgets('Catering actions and headings $width $lang 2x', (
        tester,
      ) async {
        await catalog.mount(
          tester,
          catalog.Repo(),
          width: width,
          lang: lang,
          scale: 2,
        );
        final categories = find.widgetWithText(
          FilledButton,
          lang == 'en' ? 'Categories' : 'Categorías',
        );
        final newItem = find.widgetWithText(
          FilledButton,
          lang == 'en' ? 'New Item' : 'Nuevo producto',
        );
        expect(categories, findsOneWidget);
        expect(newItem, findsOneWidget);
        final control = find.ancestor(
          of: categories,
          matching: find.byType(PelinesButton),
        );
        expect(control, findsOneWidget);
        final header = find.byKey(const ValueKey('catering-category-header-c'));
        expect(
          find.descendant(of: header, matching: find.byType(TextButton)),
          findsNothing,
        );
        expect(
          find.descendant(
            of: header,
            matching: find.byType(CateringDeleteButton),
          ),
          findsNothing,
        );
        final title = tester.widget<Text>(
          find.descendant(of: header, matching: find.text('Category c')),
        );
        expect(title.style!.color, PelinesColors.brandPrimary);
        expect(title.style!.fontSize, greaterThan(18));
        expect(title.style!.fontWeight, FontWeight.w600);
        await reveal(tester, newItem);
        await tester.tap(newItem);
        await tester.pumpAndSettle();
        expect(find.byType(SimpleDialog), findsNothing);
        expect(tester.takeException(), isNull);
      });
    }
  }
}
