import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pelines_admin_app/features/menu/models/menu_models.dart';

import 'catering_catalog_test.dart' as catalog;

void main() {
  for (final width in [320.0, 390.0, 1000.0]) {
    for (final lang in ['en', 'es']) {
      for (final available in [true, false]) {
        testWidgets(
          'Regular card $width $lang availability=$available large price 2x',
          (tester) async {
            const name =
                'A very long Regular product name that remains fully readable';
            final repo = catalog.Repo(kind: MenuKind.store);
            repo.products = [
              MenuProduct(
                id: 'edge',
                categoryId: 'c',
                name: name,
                slug: 'edge',
                priceCents: 99999999999999,
                isAvailable: available,
                sortOrder: 0,
                description: 'Regular description',
                subcategory: 'Regular subgroup',
                createdAt: DateTime(2026),
                updatedAt: DateTime(2026),
                modifierGroups: const [],
              ),
            ];
            await catalog.mount(
              tester,
              repo,
              width: width,
              scale: 2,
              lang: lang,
            );
            final card = find.byKey(const ValueKey('menu-product-edge'));
            Finder inside(Finder finder) =>
                find.descendant(of: card, matching: finder);
            final edit = inside(
              find.byTooltip(lang == 'en' ? 'Edit' : 'Editar'),
            );
            final photo = inside(find.byKey(const Key('menu-image-fallback')));
            expect(
              tester.getRect(photo).contains(tester.getCenter(edit)),
              true,
            );
            expect(tester.getSize(edit).height, greaterThanOrEqualTo(48));
            expect(inside(find.text(name)), findsOneWidget);
            expect(
              inside(find.text('Category c · Regular subgroup')),
              findsOneWidget,
            );
            expect(inside(find.text('Regular description')), findsOneWidget);
            final price = inside(
              find.byWidgetPredicate(
                (w) =>
                    w is Text &&
                    (w.data?.contains('999,999,999,999.99') ?? false),
              ),
            );
            expect(price, findsOneWidget);
            expect(tester.widget<Text>(price).maxLines, 1);
            final scale = find.ancestor(
              of: price,
              matching: find.byType(FittedBox),
            );
            expect(scale, findsOneWidget);
            expect(
              tester.getSize(scale).width,
              lessThan(tester.getSize(card).width),
            );
            final actions = inside(
              find.byKey(const ValueKey('regular-product-actions-edge')),
            );
            expect(
              find.descendant(of: actions, matching: find.byType(IconButton)),
              findsNWidgets(2),
            );
            expect(
              find.descendant(
                of: actions,
                matching: find.byIcon(Icons.edit_outlined),
              ),
              findsNothing,
            );
            final duplicate = inside(
              find.byTooltip(lang == 'en' ? 'Duplicate' : 'Duplicar'),
            );
            final deletion = inside(
              find.byTooltip(lang == 'en' ? 'Delete' : 'Eliminar'),
            );
            expect(
              tester.getTopLeft(duplicate).dy,
              tester.getTopLeft(deletion).dy,
            );
            expect(
              tester.getTopLeft(duplicate).dx,
              lessThan(tester.getTopLeft(deletion).dx),
            );
            final view = inside(
              find.widgetWithText(
                OutlinedButton,
                lang == 'en' ? 'View' : 'Ver',
              ),
            );
            expect(
              tester.getRect(view).top,
              greaterThan(tester.getRect(actions).bottom),
            );
            expect(
              tester.getSize(view).width,
              closeTo(tester.getSize(card).width - 34, 1),
            );
            expect(
              inside(
                find.text(
                  lang == 'en'
                      ? (available ? 'Available' : 'Unavailable')
                      : (available ? 'Disponible' : 'No disponible'),
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
}
