import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pelines_admin_app/features/menu/data/menu_repository.dart';
import 'package:pelines_admin_app/features/menu/models/menu_models.dart';

import 'catering_catalog_test.dart' as h;

class EditorRepo extends h.Repo {
  ProductWriteInput? saved;
  bool reject = false;
  int writes = 0;
  @override
  Future<MenuProduct> updateProduct(String id, ProductWriteInput input) async {
    writes++;
    if (reject) throw Exception('simulated failure');
    saved = input;
    return getProduct(id);
  }

  @override
  Future<MenuProduct> getProduct(String id) async {
    final input = saved;
    if (input == null) return super.getProduct(id);
    return MenuProduct(
      id: id,
      categoryId: input.categoryId,
      name: input.name,
      slug: id,
      modifierGroups: groups,
      priceCents: input.priceCents,
      isAvailable: input.isAvailable,
      sortOrder: input.sortOrder,
      description: input.description,
      disclaimer: input.disclaimer,
      subcategory: input.subcategory,
      servesCount: input.servesCount,
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
    );
  }
}

Finder field(String label) => find.byWidgetPredicate(
  (w) => w is TextField && w.decoration?.labelText == label,
);

Future<void> reveal(WidgetTester tester, Finder target) async {
  await tester.ensureVisible(target);
  await tester.pumpAndSettle();
  for (var i = 0; i < 20 && target.hitTestable().evaluate().isEmpty; i++) {
    await tester.drag(find.byType(ListView).first, const Offset(0, -250));
    await tester.pumpAndSettle();
  }
  expect(target.hitTestable(), findsOneWidget);
}

void main() {
  for (final lang in ['en', 'es']) {
    testWidgets(
      'editor preloads fields counters and honest photo controls $lang',
      (tester) async {
        final repo = EditorRepo();
        final router = await h.mount(
          tester,
          repo,
          lang: lang,
          width: 320,
          scale: 2,
        );
        router.go('/app/menu/catering/categories/c/products/p/edit');
        await tester.pumpAndSettle();
        expect(
          find.text(lang == 'en' ? 'Edit item' : 'Editar producto'),
          findsOneWidget,
        );
        final name = field(lang == 'en' ? 'Name' : 'Nombre');
        expect(tester.widget<TextField>(name).controller!.text, 'Meal p');
        expect(tester.widget<TextField>(name).decoration!.counterText, '6/120');
        final subcategory = find.byKey(
          const ValueKey('catering-subcategory-c-Buffet'),
        );
        final selector = tester.widget<DropdownButtonFormField<String>>(
          subcategory,
        );
        expect(selector.initialValue, 'Buffet');
        expect(
          tester
              .widget<DropdownButton<String>>(
                find.descendant(
                  of: subcategory,
                  matching: find.byType(DropdownButton<String>),
                ),
              )
              .items!
              .map((i) => i.value),
          ['', 'Buffet'],
        );
        final description = field(
          lang == 'en' ? 'Description (Optional)' : 'Descripción (opcional)',
        );
        expect(
          tester.widget<TextField>(description).controller!.text,
          'Backend description',
        );
        expect(
          tester.widget<TextField>(description).decoration!.counterText,
          '19',
        );
        final recommendations = find.textContaining('WebP');
        final removalNotice = find.text(
          lang == 'en'
              ? 'Image removal is currently unavailable.'
              : 'La eliminación de imágenes no está disponible actualmente.',
        );
        expect(
          tester.getRect(removalNotice).top,
          greaterThan(tester.getRect(recommendations).bottom),
        );
        expect(
          find.widgetWithText(
            OutlinedButton,
            lang == 'en' ? 'Change image' : 'Cambiar imagen',
          ),
          findsOneWidget,
        );
        final portionsHelp = find.text(
          lang == 'en'
              ? 'Number of people this catering item is intended to serve.'
              : 'Número de personas para las que está pensado este producto de catering.',
        );
        final sort = field(lang == 'en' ? 'Sort order' : 'Orden');
        expect(
          tester.getRect(sort).top,
          greaterThan(tester.getRect(portionsHelp).bottom),
        );
        final remove = find.widgetWithText(
          TextButton,
          lang == 'en' ? 'Remove image' : 'Quitar imagen',
        );
        expect(tester.widget<TextButton>(remove).onPressed, isNull);
        expect(find.byType(CheckboxListTile), findsOneWidget);
        expect(
          tester.widget<CheckboxListTile>(find.byType(CheckboxListTile)).value,
          isTrue,
        );
        await reveal(tester, description);
        await tester.enterText(description, 'Draft description');
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        FocusManager.instance.primaryFocus?.unfocus();
        final close = find.byWidgetPredicate(
          (w) =>
              w is IconButton &&
              w.tooltip == (lang == 'en' ? 'Close' : 'Cerrar'),
        );
        await tester.tap(close);
        await tester.pumpAndSettle();
        expect(find.byType(AlertDialog), findsOneWidget);
        expect(repo.writes, 0);
        await tester.tap(find.text(lang == 'en' ? 'Stay' : 'Permanecer'));
        await tester.pumpAndSettle();
        expect(
          tester.widget<TextField>(description).controller!.text,
          'Draft description',
        );
        expect(tester.takeException(), isNull);
      },
    );
  }

  for (final reject in [false, true]) {
    testWidgets(
      'existing save flow preserves fields and reports failure $reject',
      (tester) async {
        final repo = EditorRepo()..reject = reject;
        final router = await h.mount(tester, repo);
        router.go('/app/menu/catering/categories/c/products/p/edit');
        await tester.pumpAndSettle();
        await reveal(tester, field('Name'));
        await tester.enterText(field('Name'), 'Changed meal');
        await tester.pumpAndSettle();
        final save = find.widgetWithText(FilledButton, 'Save');
        await reveal(tester, save);
        await tester.tap(save);
        await tester.pumpAndSettle();
        expect(repo.writes, 1);
        if (reject) {
          expect(find.text('The product could not be saved.'), findsOneWidget);
          expect(
            tester.widget<TextField>(field('Name')).controller!.text,
            'Changed meal',
          );
        } else {
          expect(repo.saved!.name, 'Changed meal');
          expect(repo.saved!.priceCents, 1250);
          expect(repo.saved!.servesCount, 12);
          expect(repo.saved!.subcategory, 'Buffet');
          expect(repo.saved!.disclaimer, 'Backend disclaimer');
        }
        expect(tester.takeException(), isNull);
      },
    );
  }
  for (final (width, scale) in [(390.0, 1.0), (320.0, 2.0)]) {
    testWidgets('footer and spacing respond to width $width scale $scale', (
      tester,
    ) async {
      final router = await h.mount(
        tester,
        EditorRepo(),
        width: width,
        scale: scale,
      );
      router.go('/app/menu/catering/categories/c/products/p/edit');
      await tester.pumpAndSettle();
      final cancel = find.widgetWithText(OutlinedButton, 'Cancel');
      final save = find.widgetWithText(FilledButton, 'Save');
      final cancelRect = tester.getRect(cancel),
          saveRect = tester.getRect(save);
      if (scale == 1) {
        expect(cancelRect.top, saveRect.top);
        expect(saveRect.left, greaterThan(cancelRect.right));
      } else {
        expect(saveRect.top, greaterThan(cancelRect.bottom));
      }
      final help = find.text(
        'Number of people this catering item is intended to serve.',
      );
      expect(
        tester.getRect(field('Sort order')).top,
        greaterThan(tester.getRect(help).bottom),
      );
      expect(tester.takeException(), isNull);
    });
  }
}
