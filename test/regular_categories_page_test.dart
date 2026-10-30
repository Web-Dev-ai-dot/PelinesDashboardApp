import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pelines_admin_app/features/menu/models/menu_models.dart';
import 'package:pelines_admin_app/features/menu/presentation/menu_screens.dart';

import 'catering_catalog_test.dart' as catalog;
import 'catering_category_section_test.dart'
    show CategoriesRepo, CategoriesDelete;

Future<void> reveal(WidgetTester tester, Finder finder) async {
  await Scrollable.ensureVisible(tester.element(finder), alignment: .5);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'Regular categories persist toggle and order using store context',
    (tester) async {
      final repo = CategoriesRepo(kind: MenuKind.store);
      await catalog.mount(tester, repo);
      await catalog.openCategories(tester);
      expect(find.byType(RegularCategoriesScreen), findsOneWidget);
      final active = find.byKey(const ValueKey('category-active-c'));
      await reveal(tester, active);
      await tester.tap(active);
      await tester.pumpAndSettle();
      expect(repo.submitted!.kind, MenuKind.store);
      expect(repo.submitted!.isActive, false);
      expect(tester.widget<Checkbox>(active).value, false);
      await tester.tap(find.byKey(const ValueKey('category-edit-c')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const ValueKey('category-order')), '0');
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();
      expect(repo.submitted!.sortOrder, 0);
      expect(repo.submitted!.kind, MenuKind.store);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'Regular rejected toggle retains value and delete requires confirmation',
    (tester) async {
      final repo = CategoriesRepo(kind: MenuKind.store)..reject = true;
      final deletion = CategoriesDelete(repo);
      await catalog.mount(tester, repo, deletion: deletion);
      await catalog.openCategories(tester);
      final active = find.byKey(const ValueKey('category-active-c'));
      await reveal(tester, active);
      await tester.tap(active);
      await tester.pumpAndSettle();
      expect(tester.widget<Checkbox>(active).value, true);
      expect(find.text('Category update rejected'), findsOneWidget);
      final del = find.byKey(const ValueKey('catering-delete-c'));
      await reveal(tester, del);
      await tester.tap(del);
      await tester.pumpAndSettle();
      expect(deletion.calls, 0);
      await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
      await tester.pumpAndSettle();
      expect(deletion.calls, 0);
      await tester.tap(del);
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
      await tester.pumpAndSettle();
      expect(deletion.calls, 1);
      expect(repo.rows.any((row) => row.id == 'c'), false);
    },
  );
  for (final width in [320.0, 1000.0]) {
    for (final lang in ['en', 'es']) {
      testWidgets(
        'Regular Categories layout $width $lang, return preserves search',
        (tester) async {
          final router = await catalog.mount(
            tester,
            CategoriesRepo(kind: MenuKind.store),
            width: width,
            scale: 2,
            lang: lang,
          );
          await tester.enterText(find.byType(TextField).first, 'Meal');
          await tester.pumpAndSettle();
          await catalog.openCategories(tester, lang: lang);
          expect(
            find.byKey(const ValueKey('regular-new-category')),
            findsOneWidget,
          );
          expect(find.byType(RegularCategoriesScreen), findsOneWidget);
          expect(tester.takeException(), isNull);
          await tester.tap(find.byIcon(Icons.arrow_back));
          await tester.pumpAndSettle();
          expect(
            router.routeInformationProvider.value.uri.path,
            '/app/menu/store',
          );
          expect(
            tester
                .widget<EditableText>(find.byType(EditableText).first)
                .controller
                .text,
            'Meal',
          );
        },
      );
    }
  }
}
