import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pelines_admin_app/app/theme/pelines_tokens.dart';
import 'package:pelines_admin_app/app/theme/pelines_components.dart';
import 'package:pelines_admin_app/features/menu/data/menu_repository.dart';
import 'package:pelines_admin_app/features/menu/models/menu_models.dart';
import 'package:pelines_admin_app/features/menu/providers/catering_actions.dart';
import 'package:pelines_admin_app/features/menu/presentation/modifier_form_screen.dart';

import 'catering_catalog_test.dart' as h;
import 'catering_item_editor_layout_test.dart' as e;

class InlineRepo extends e.EditorRepo {
  InlineRepo() {
    groups = [
      group('g', 'Sides', [option('o', 'Rice')]),
    ];
  }
  bool rejectOption = false;
  Completer<void>? holdGroup;
  int groupWrites = 0, optionWrites = 0;
  MenuModifierOption option(
    String id,
    String name, {
    int price = 200,
    String groupId = 'g',
  }) => MenuModifierOption(
    id: id,
    groupId: groupId,
    name: name,
    priceDeltaCents: price,
    isDefault: false,
    sortOrder: 0,
  );
  MenuModifierGroup group(
    String id,
    String name,
    List<MenuModifierOption> options, {
    bool required = false,
    int min = 0,
    int max = 1,
    int sort = 0,
  }) => MenuModifierGroup(
    id: id,
    productId: 'p',
    name: name,
    sortOrder: sort,
    isRequired: required,
    minSelect: min,
    maxSelect: max,
    options: options,
  );
  @override
  Future<MenuModifierGroup> updateModifierGroup(
    String id,
    ModifierGroupWriteInput input,
  ) async {
    groupWrites++;
    await holdGroup?.future;
    final old = groups.firstWhere((g) => g.id == id);
    final result = group(
      id,
      input.name,
      old.options,
      required: input.isRequired,
      min: input.minSelect,
      max: input.maxSelect,
      sort: input.sortOrder,
    );
    groups = [for (final g in groups) g.id == id ? result : g];
    return result;
  }

  @override
  Future<MenuModifierGroup> createModifierGroup(
    String id,
    ModifierGroupWriteInput input,
  ) async {
    groupWrites++;
    final result = group(
      'new-g',
      input.name,
      [],
      required: input.isRequired,
      min: input.minSelect,
      max: input.maxSelect,
      sort: input.sortOrder,
    );
    groups = [...groups, result];
    return result;
  }

  Future<MenuModifierOption> writeOption(
    String groupId,
    String id,
    ModifierOptionWriteInput input,
  ) async {
    optionWrites++;
    if (rejectOption) throw Exception('simulated option failure');
    final result = MenuModifierOption(
      id: id,
      groupId: groupId,
      name: input.name,
      priceDeltaCents: input.priceDeltaCents,
      isDefault: input.isDefault,
      sortOrder: input.sortOrder,
    );
    groups = [
      for (final g in groups)
        g.id != groupId
            ? g
            : group(
                g.id,
                g.name,
                [...g.options.where((o) => o.id != id), result],
                required: g.isRequired!,
                min: g.minSelect!,
                max: g.maxSelect!,
                sort: g.sortOrder,
              ),
    ];
    return result;
  }

  @override
  Future<MenuModifierOption> updateModifierOption(
    String id,
    ModifierOptionWriteInput input,
  ) => writeOption('g', id, input);
  @override
  Future<MenuModifierOption> createModifierOption(
    String groupId,
    ModifierOptionWriteInput input,
  ) => writeOption(groupId, 'new-o', input);
}

class InlineDelete extends h.DeleteApi {
  InlineDelete(this.repo);
  final InlineRepo repo;
  @override
  Future<void> delete(CateringEntity entity, String id) async {
    calls++;
    if (entity == CateringEntity.group) {
      repo.groups = repo.groups.where((g) => g.id != id).toList();
    } else {
      repo.groups = [
        for (final g in repo.groups)
          repo.group(
            g.id,
            g.name,
            g.options.where((o) => o.id != id).toList(),
            required: g.isRequired!,
            min: g.minSelect!,
            max: g.maxSelect!,
            sort: g.sortOrder,
          ),
      ];
    }
  }
}

Finder inside(Finder parent, Finder child) =>
    find.descendant(of: parent, matching: child);
Finder groupEditor() => find.byType(ModifierGroupForm).first;
Finder optionEditor() => find.byType(ModifierOptionForm).first;
Finder nameIn(Finder editor) => inside(editor, e.field('Name'));
Future<void> edit(WidgetTester tester, Finder target, String value) async {
  await e.reveal(tester, target);
  await tester.enterText(target, value);
  await tester.pumpAndSettle();
}

Future<void> tap(WidgetTester tester, Finder target) async {
  await e.reveal(tester, target);
  await tester.tap(target);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'inline saves are independent, retain product and other drafts, and handle partial failure',
    (tester) async {
      final repo = InlineRepo();
      final router = await h.mount(tester, repo);
      router.go('/app/menu/catering/categories/c/products/p/edit');
      await tester.pumpAndSettle();
      await edit(tester, e.field('Name').first, 'Product draft');
      await edit(tester, nameIn(groupEditor()), 'Saved sides');
      await tap(tester, inside(groupEditor(), find.byType(CheckboxListTile)));
      await edit(tester, nameIn(optionEditor()), 'Option draft');
      await tap(
        tester,
        inside(groupEditor(), find.widgetWithText(FilledButton, 'Save Group')),
      );
      expect(repo.groupWrites, 1);
      expect(repo.writes, 0);
      expect(repo.groups.single.name, 'Saved sides');
      expect(repo.groups.single.isRequired, isTrue);
      expect(repo.groups.single.minSelect, 1);
      expect(
        tester.widget<TextField>(e.field('Name').first).controller!.text,
        'Product draft',
      );
      expect(
        tester.widget<TextField>(nameIn(optionEditor())).controller!.text,
        'Option draft',
      );
      repo.rejectOption = true;
      await tap(
        tester,
        inside(
          optionEditor(),
          find.widgetWithText(FilledButton, 'Save Option'),
        ),
      );
      expect(repo.groups.single.options.single.name, 'Rice');
      expect(repo.groups.single.name, 'Saved sides');
      expect(find.text('The modifier could not be saved.'), findsWidgets);
      expect(
        tester.widget<TextField>(nameIn(optionEditor())).controller!.text,
        'Option draft',
      );
      expect(
        tester
            .widget<FilledButton>(find.widgetWithText(FilledButton, 'Save'))
            .onPressed,
        isNull,
      );
      repo.rejectOption = false;
      await tap(
        tester,
        inside(
          optionEditor(),
          find.widgetWithText(FilledButton, 'Save Option'),
        ),
      );
      expect(repo.groups.single.options.single.name, 'Option draft');
      expect(
        tester.widget<TextField>(e.field('Name').first).controller!.text,
        'Product draft',
      );
      expect(
        tester
            .widget<FilledButton>(find.widgetWithText(FilledButton, 'Save'))
            .onPressed,
        isNotNull,
      );
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'inline creates options and groups and deletes only after confirmation',
    (tester) async {
      final repo = InlineRepo();
      final deletion = InlineDelete(repo);
      final router = await h.mount(tester, repo, deletion: deletion);
      router.go('/app/menu/catering/categories/c/products/p/edit');
      await tester.pumpAndSettle();
      await tap(tester, find.widgetWithText(OutlinedButton, 'Add option'));
      final newOption = find.byType(ModifierOptionForm).last;
      await edit(tester, nameIn(newOption), 'Salsa');
      await edit(tester, inside(newOption, e.field('Price')), '3.50');
      await tap(
        tester,
        inside(newOption, find.widgetWithText(FilledButton, 'Create Option')),
      );
      expect(repo.groups.single.options.last.priceDeltaCents, 350);
      await tap(
        tester,
        find.widgetWithText(OutlinedButton, 'Add add-on group'),
      );
      final newGroup = find.byType(ModifierGroupForm).last;
      await edit(tester, nameIn(newGroup), 'Extras');
      await tap(
        tester,
        inside(newGroup, find.widgetWithText(FilledButton, 'Create Group')),
      );
      expect(repo.groups, hasLength(2));
      expect(repo.writes, 0);
      await tap(tester, find.byKey(const ValueKey('catering-delete-new-o')));
      expect(deletion.calls, 0);
      await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
      await tester.pumpAndSettle();
      expect(deletion.calls, 0);
      await tap(tester, find.byKey(const ValueKey('catering-delete-new-o')));
      await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
      await tester.pumpAndSettle();
      expect(deletion.calls, 1);
      expect(repo.groups.first.options, hasLength(1));
      await tap(tester, find.byKey(const ValueKey('catering-delete-new-g')));
      await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
      await tester.pumpAndSettle();
      expect(deletion.calls, 2);
      expect(repo.groups, hasLength(1));
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('group submit blocks duplicates while validating and saving', (
    tester,
  ) async {
    final repo = InlineRepo()..holdGroup = Completer<void>();
    final router = await h.mount(tester, repo);
    router.go('/app/menu/catering/categories/c/products/p/edit');
    await tester.pumpAndSettle();
    await edit(tester, nameIn(groupEditor()), 'Changed');
    final save = inside(
      groupEditor(),
      find.widgetWithText(FilledButton, 'Save Group'),
    );
    await e.reveal(tester, save);
    await tester.tap(save);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(repo.groupWrites, 1);
    expect(find.byType(ModifierGroupForm), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(
            inside(groupEditor(), find.byType(FilledButton)),
          )
          .onPressed,
      isNull,
    );
    repo.holdGroup!.complete();
    await tester.pumpAndSettle();
    expect(repo.groupWrites, 1);
    expect(tester.takeException(), isNull);
  });
  testWidgets('Cancel discards only unsaved drafts and retains saved add-ons', (
    tester,
  ) async {
    final repo = InlineRepo();
    final router = await h.mount(tester, repo);
    router.push('/app/menu/catering/categories/c/products/p/edit');
    await tester.pumpAndSettle();
    await edit(tester, nameIn(groupEditor()), 'Persisted sides');
    await tap(
      tester,
      inside(groupEditor(), find.widgetWithText(FilledButton, 'Save Group')),
    );
    await edit(tester, e.field('Name').first, 'Unsaved product');
    await tap(tester, find.widgetWithText(OutlinedButton, 'Cancel'));
    expect(find.byType(AlertDialog), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Discard'));
    await tester.pumpAndSettle();
    expect(repo.groups.single.name, 'Persisted sides');
    expect(repo.writes, 0);
    expect(find.byType(ModifierGroupForm), findsNothing);
    expect(tester.takeException(), isNull);
  });
  for (final lang in ['en', 'es']) {
    for (final (width, scale) in [
      (390.0, 1.0),
      (320.0, 1.0),
      (320.0, 2.0),
      (800.0, 1.0),
    ]) {
      testWidgets('compact inline layout $lang $width $scale', (tester) async {
        final repo = InlineRepo();
        repo.groups = [
          repo.group('g', 'Sides for catering guests with seasonal choices', [
            repo.option('o', 'Optional side for guests with special requests'),
            repo.option('o2', 'Second option'),
          ]),
        ];
        final router = await h.mount(
          tester,
          repo,
          lang: lang,
          width: width,
          scale: scale,
        );
        router.go('/app/menu/catering/categories/c/products/p/edit');
        await tester.pumpAndSettle();
        final group = groupEditor(), option = optionEditor();
        final secondOption = find.byType(ModifierOptionForm).last;
        expect(
          tester.getRect(option).top - tester.getRect(group).bottom,
          greaterThanOrEqualTo(PelinesSpacing.md - 0.01),
        );
        expect(
          tester.getRect(secondOption).top - tester.getRect(option).bottom,
          greaterThanOrEqualTo(PelinesSpacing.md - 0.01),
        );
        for (final entity in [option, secondOption]) {
          final save = inside(
            entity,
            find.widgetWithText(
              FilledButton,
              lang == 'en' ? 'Save Option' : 'Guardar opción',
            ),
          );
          expect(
            tester.getRect(entity).bottom - tester.getRect(save).bottom,
            greaterThanOrEqualTo(PelinesSpacing.md - 0.01),
          );
        }

        // The group uses its existing outer card; an option has one compact card.
        expect(inside(group, find.byType(PelinesCard)), findsNothing);
        expect(inside(option, find.byType(PelinesCard)), findsOneWidget);
        for (final (editor, id, saveLabel) in [
          (group, 'g', lang == 'en' ? 'Save Group' : 'Guardar grupo'),
          (option, 'o', lang == 'en' ? 'Save Option' : 'Guardar opción'),
        ]) {
          final delete = inside(
            editor,
            find.byKey(ValueKey('catering-delete-$id')),
          );
          final name = inside(
            editor,
            e.field(lang == 'en' ? 'Name' : 'Nombre'),
          );
          expect(delete, findsOneWidget);
          expect(
            tester.getRect(editor).contains(tester.getCenter(delete)),
            isTrue,
          );
          expect(
            tester.getRect(name).right,
            lessThan(tester.getRect(delete).left),
          );
          final save = inside(
            editor,
            find.widgetWithText(FilledButton, saveLabel),
          );
          final reset = inside(
            editor,
            find.widgetWithText(
              OutlinedButton,
              lang == 'en' ? 'Reset changes' : 'Restablecer cambios',
            ),
          );
          final button = tester.widget<FilledButton>(save);
          expect(button.onPressed, isNull);
          expect(
            button.style!.backgroundColor!.resolve({WidgetState.disabled}),
            PelinesColors.mutedSurface,
          );
          expect(
            button.style!.foregroundColor!.resolve({WidgetState.disabled}),
            PelinesColors.textSecondary,
          );
          expect(tester.getSize(save).height, greaterThanOrEqualTo(48));
          if (width >= 390 && scale == 1) {
            expect(tester.getRect(save).top, tester.getRect(reset).top);
          } else {
            expect(
              tester.getRect(save).top,
              greaterThan(tester.getRect(reset).bottom),
            );
          }
          final advanced = inside(editor, find.byType(ExpansionTile));
          expect(advanced, findsOneWidget);
          expect(
            inside(editor, e.field(lang == 'en' ? 'Sort order' : 'Orden')),
            findsNothing,
          );
        }
        final target = inside(
          option,
          e.field(lang == 'en' ? 'Name' : 'Nombre'),
        );
        await e.reveal(tester, target);
        await tester.enterText(target, 'Keyboard draft');
        await tester.pumpAndSettle();
        tester.view.viewInsets = const FakeViewPadding(bottom: 300);
        addTearDown(tester.view.resetViewInsets);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(repo.writes, 0);
        expect(repo.optionWrites, 0);
      });
    }
  }
  testWidgets(
    'advanced values stay accessible and Reset changes restores the entity',
    (tester) async {
      final repo = InlineRepo();
      final router = await h.mount(tester, repo);
      router.go('/app/menu/catering/categories/c/products/p/edit');
      await tester.pumpAndSettle();
      await tap(tester, inside(groupEditor(), find.text('Advanced options')));
      expect(
        inside(groupEditor(), e.field('Minimum selections')),
        findsOneWidget,
      );
      expect(
        inside(groupEditor(), e.field('Maximum selections')),
        findsOneWidget,
      );
      await edit(
        tester,
        inside(groupEditor(), e.field('Maximum selections')),
        '3',
      );
      await tap(
        tester,
        inside(
          groupEditor(),
          find.widgetWithText(OutlinedButton, 'Reset changes'),
        ),
      );
      expect(repo.groupWrites, 0);
      await tap(tester, inside(groupEditor(), find.text('Advanced options')));
      expect(
        tester
            .widget<TextField>(
              inside(groupEditor(), e.field('Maximum selections')),
            )
            .controller!
            .text,
        '1',
      );
      await tap(tester, inside(optionEditor(), find.text('Advanced options')));
      await edit(tester, inside(optionEditor(), e.field('Sort order')), '5');
      await tap(
        tester,
        inside(
          optionEditor(),
          find.widgetWithText(FilledButton, 'Save Option'),
        ),
      );
      expect(repo.groups.single.options.single.sortOrder, 5);
      expect(repo.writes, 0);
      expect(repo.optionWrites, 1);
      expect(tester.takeException(), isNull);
    },
  );
}
