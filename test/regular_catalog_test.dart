import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pelines_admin_app/features/menu/data/menu_repository.dart';
import 'package:pelines_admin_app/features/menu/models/menu_models.dart';
import 'package:pelines_admin_app/features/menu/presentation/category_form_screen.dart';
import 'package:pelines_admin_app/features/menu/presentation/menu_screens.dart';

import 'catering_catalog_test.dart'
    show menuCatalogTests, mount, Repo, openCategories;

// Both menus exercise the same catalog, actions and editor contracts, with
// isolated kind-scoped datasets and the real Regular field differences.
void main() {
  menuCatalogTests(MenuKind.store);

  testWidgets('Regular category create and edit retain kind and IDs', (
    tester,
  ) async {
    final router = await mount(tester, Repo(kind: MenuKind.store));
    await openCategories(tester);
    await tester.tap(find.text('New Category'));
    await tester.pumpAndSettle();
    var form = tester.widget<CategoryFormScreen>(
      find.byType(CategoryFormScreen),
    );
    expect(form.kind, MenuKind.store);
    expect(form.categoryId, isNull);
    router.pop();
    await tester.pumpAndSettle();
    final edit = find.byKey(const ValueKey('category-edit-c'));
    await reveal(tester, edit);
    await tester.tap(edit);
    await tester.pumpAndSettle();
    form = tester.widget<CategoryFormScreen>(find.byType(CategoryFormScreen));
    expect(form.kind, MenuKind.store);
    expect(form.categoryId, 'c');
    expect(tester.takeException(), isNull);
  });

  testWidgets('Regular create then edit reconcile and open saved product', (
    tester,
  ) async {
    final repo = SavingRepo();
    final router = await mount(tester, repo);
    await tester.tap(find.text('New Item'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('store-edit-category-')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Category c').last);
    await tester.pumpAndSettle();
    Finder field(String label) {
      final names = {
        'Name': 'name',
        'Price': 'price',
        'Description': 'description',
        'Subcategory name': 'subcategory-name',
        'Disclaimer': 'disclaimer',
      };
      final creation = find.byKey(ValueKey('new-menu-item-${names[label]}'));
      if (creation.evaluate().isNotEmpty) return creation;
      return find.byWidgetPredicate(
        (w) => w is TextField && w.decoration?.labelText == label,
      );
    }

    expect(field('Serves'), findsNothing);
    await reveal(tester, field('Name'));
    await tester.enterText(field('Name'), 'Regular item');
    await reveal(tester, field('Price'));
    await tester.enterText(field('Price'), '12.50');
    await reveal(tester, field('Description'));
    await tester.enterText(field('Description'), 'Backend description');
    await reveal(tester, field('Subcategory name'));
    await tester.enterText(field('Subcategory name'), 'Lunch');
    await reveal(tester, field('Disclaimer'));
    await tester.enterText(field('Disclaimer'), 'Backend disclaimer');
    final create = find.widgetWithText(FilledButton, 'Save');
    await reveal(tester, create);
    await tester.tap(create);
    await tester.pumpAndSettle();
    expect(repo.creates, 1);
    expect(repo.saved!.servesCount, isNull);
    expect(repo.saved!.subcategory, 'Lunch');
    var detail = tester.widget<MenuProductDetailScreen>(
      find.byType(MenuProductDetailScreen),
    );
    expect(detail.kind, MenuKind.store);
    expect(detail.categoryId, 'c');
    expect(detail.productId, 'saved');
    expect(find.text('Product Detail'), findsOneWidget);
    expect(find.text('Serves'), findsNothing);

    router.push('/app/menu/store/categories/c/products/saved/edit');
    await tester.pumpAndSettle();
    expect(find.text('Change Image'), findsOneWidget);
    expect(find.text('Manage modifiers'), findsOneWidget);
    expect(field('Serves'), findsNothing);
    await tester.enterText(field('Name'), 'Regular edited');
    final select = find.byKey(const ValueKey('store-edit-category-c'));
    await reveal(tester, select);
    await tester.tap(select);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Category d').last);
    await tester.pumpAndSettle();
    final save = find.widgetWithText(FilledButton, 'Save');
    await reveal(tester, save);
    await tester.tap(save);
    await tester.pumpAndSettle();
    expect(repo.updates, 1);
    expect(repo.saved!.categoryId, 'd');
    expect(repo.saved!.disclaimer, 'Backend disclaimer');
    detail = tester.widget<MenuProductDetailScreen>(
      find.byType(MenuProductDetailScreen),
    );
    expect(detail.categoryId, 'd');
    expect(detail.productId, 'saved');
    expect(tester.takeException(), isNull);
  });
}

Future<void> reveal(WidgetTester tester, Finder target) async {
  await tester.ensureVisible(target);
  await tester.pumpAndSettle();
  for (var i = 0; i < 15 && target.hitTestable().evaluate().isEmpty; i++) {
    await tester.drag(find.byType(Scrollable).first, const Offset(0, -250));
    await tester.pumpAndSettle();
  }
  expect(target.hitTestable(), findsOneWidget);
}

class SavingRepo extends Repo {
  SavingRepo() : super(kind: MenuKind.store);
  ProductWriteInput? saved;
  int updates = 0;

  @override
  Future<MenuProduct> createProduct(ProductWriteInput input) async {
    creates++;
    saved = input;
    return getProduct('saved');
  }

  @override
  Future<MenuProduct> updateProduct(String id, ProductWriteInput input) async {
    updates++;
    saved = input;
    return getProduct(id);
  }

  @override
  Future<MenuProduct> getProduct(String id) async {
    if (saved == null) return super.getProduct(id);
    final input = saved!;
    return MenuProduct(
      id: id,
      categoryId: input.categoryId,
      name: input.name,
      slug: id,
      description: input.description,
      subcategory: input.subcategory,
      disclaimer: input.disclaimer,
      servesCount: input.servesCount,
      priceCents: input.priceCents,
      isAvailable: input.isAvailable,
      sortOrder: input.sortOrder,
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
      modifierGroups: const [],
    );
  }
}
