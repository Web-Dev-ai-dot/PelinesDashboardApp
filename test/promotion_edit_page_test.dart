import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pelines_admin_app/core/api/api_exception.dart';
import 'package:pelines_admin_app/features/promotions/models/discount.dart';
import 'package:pelines_admin_app/features/promotions/models/promotion_write.dart';
import 'package:pelines_admin_app/features/promotions/presentation/promotion_detail_screen.dart';
import 'package:pelines_admin_app/features/promotions/presentation/promotion_form_screen.dart';
import 'package:pelines_admin_app/features/promotions/presentation/promotions_screen.dart';

import 'promotions_layout_test.dart' as h;

Discount record({bool global = false}) => Discount.fromJson({
  ...discountEditableBody(h.discount()),
  'id': 'local',
  'code': 'REALCODE',
  'type': 'fixed',
  'value': 1250,
  'minSubtotalCents': 599,
  'startsAt': '2035-07-02T15:43:00Z',
  'endsAt': '2035-07-04T18:45:00Z',
  'timesRedeemed': 2,
  'usageLimit': 12,
  'locationId': global ? null : 'a',
  'isActive': false,
  'appliesTo': 'catering',
  'createdAt': '2026-01-01T00:00:00Z',
  'updatedAt': '2026-01-01T00:00:00Z',
});

class EditRepo extends h.Repo {
  EditRepo({bool global = false}) : super([record(global: global)]);
  int writes = 0;
  Object? error;
  Map<String, dynamic>? patch;
  Completer<void>? hold;
  @override
  Future<Discount> updatePromotion(String id, Map<String, dynamic> body) async {
    writes++;
    patch = body;
    await hold?.future;
    if (error != null) throw error!;
    final previous = current.single;
    current = [
      Discount.fromJson({
        ...discountEditableBody(previous),
        'id': id,
        'locationId': previous.locationId,
        'timesRedeemed': previous.timesRedeemed,
        'createdAt': '2026-01-01T00:00:00Z',
        'updatedAt': '2026-02-01T00:00:00Z',
        ...body,
      }),
    ];
    return current.single;
  }
}

Future<void> open(WidgetTester tester) => h.tap(tester, 'promotion-edit-local');
String field(WidgetTester t, String key) =>
    t.widget<TextField>(find.byKey(Key(key))).controller!.text;

void main() {
  for (final width in [320.0, 390.0, 800.0, 1200.0]) {
    for (final scale in [1.0, 2.0]) {
      for (final lang in ['en', 'es']) {
        testWidgets('edit prefill responsive keyboard $width $scale $lang', (
          tester,
        ) async {
          addTearDown(tester.view.resetViewInsets);
          final repo = EditRepo();
          await h.pump(tester, repo, width: width, scale: scale, lang: lang);
          await open(tester);
          expect(find.byType(PromotionFormScreen), findsOneWidget);
          expect(find.byType(AlertDialog), findsNothing);
          expect(field(tester, 'promotion-code'), 'REALCODE');
          expect(field(tester, 'promotion-value'), '12.50');
          expect(field(tester, 'promotion-minimum'), '5.99');
          expect(field(tester, 'promotion-usage'), '12');
          expect(
            find.text(
              lang == 'en'
                  ? 'Edit discount code'
                  : 'Editar código de descuento',
            ),
            findsOneWidget,
          );
          expect(
            find.text(lang == 'en' ? 'Catering orders' : 'Pedidos de catering'),
            findsOneWidget,
          );
          expect(find.text('Tualatin'), findsOneWidget);
          expect(
            find.byKey(
              ValueKey(
                'promotion-type-value-${width >= 800 && (scale == 1 || width >= 1200) ? 'row' : 'column'}',
              ),
            ),
            findsOneWidget,
          );
          expect(
            find.byKey(ValueKey('promotion-date-pair-column')),
            findsOneWidget,
          );
          final active = tester
              .widgetList<SwitchListTile>(find.byType(SwitchListTile))
              .last;
          expect(active.value, false);
          await h.tap(tester, 'promotion-form-save');
          expect(repo.writes, 0);
          expect(
            tester
                .widget<FilledButton>(
                  find.byKey(const Key('promotion-form-save')),
                )
                .onPressed,
            isNull,
          );
          await tester.ensureVisible(find.byKey(const Key('promotion-code')));
          await tester.pumpAndSettle();
          await tester.tap(find.byKey(const Key('promotion-code')));
          tester.view.viewInsets = const FakeViewPadding(bottom: 300);
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          tester.view.resetViewInsets();
          await tester.pumpAndSettle();
        });
      }
    }
  }
  for (final lang in ['en', 'es']) {
    testWidgets('mobile dates are stacked with inline actions $lang', (
      tester,
    ) async {
      await h.pump(tester, EditRepo(), width: 390, lang: lang);
      await open(tester);
      final start = find.byKey(
        const ValueKey('promotion-date-field-Start date'),
      );
      final end = find.byKey(const ValueKey('promotion-date-field-End date'));
      await tester.ensureVisible(start);
      await tester.pumpAndSettle();
      final left = tester.getRect(start);
      final right = tester.getRect(end);
      expect(right.top - left.bottom, closeTo(16, .1));
      expect(left.left, closeTo(right.left, .1));
      expect(left.width, closeTo(right.width, .1));
      expect(
        left.width,
        closeTo(
          tester
              .getSize(find.byKey(const ValueKey('promotion-date-pair-column')))
              .width,
          .1,
        ),
      );
      final startInput = tester.getRect(
        find.byKey(const ValueKey('promotion-date-input-Start date')),
      );
      final endInput = tester.getRect(
        find.byKey(const ValueKey('promotion-date-input-End date')),
      );
      expect(endInput.top, greaterThan(startInput.bottom));
      expect(startInput.height, closeTo(endInput.height, .1));
      for (final field in [start, end]) {
        final buttons = find.descendant(
          of: field,
          matching: find.byType(IconButton),
        );
        expect(buttons, findsNWidgets(2));
        final dateText = find
            .descendant(of: field, matching: find.byType(Text))
            .last;
        for (final button in buttons.evaluate()) {
          expect(
            tester.getCenter(find.byWidget(button.widget)).dy,
            closeTo(tester.getCenter(dateText).dy, .1),
          );
        }
        for (final button in buttons.evaluate()) {
          final size = tester.getSize(find.byWidget(button.widget));
          expect(size.width, greaterThanOrEqualTo(48));
          expect(size.height, greaterThanOrEqualTo(48));
        }
      }
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets(
    'mobile dates stay stacked when start is empty and end is populated',
    (tester) async {
      final repo = EditRepo();
      final d = repo.current.single;
      repo.current = [
        Discount.fromJson({
          ...discountEditableBody(d),
          'id': d.id,
          'locationId': d.locationId,
          'timesRedeemed': d.timesRedeemed,
          'startsAt': null,
          'createdAt': '2026-01-01T00:00:00Z',
          'updatedAt': '2026-01-01T00:00:00Z',
        }),
      ];
      await h.pump(tester, repo, width: 390);
      await open(tester);
      final start = find.byKey(
        const ValueKey('promotion-date-input-Start date'),
      );
      final end = find.byKey(const ValueKey('promotion-date-input-End date'));
      expect(
        find.byKey(const ValueKey('promotion-date-pair-column')),
        findsOneWidget,
      );
      expect(
        tester.getRect(end).top,
        greaterThan(tester.getRect(start).bottom),
      );
      expect(
        tester.getSize(start).height,
        closeTo(tester.getSize(end).height, .1),
      );
      expect(tester.takeException(), isNull);
    },
  );
  for (final fromDetail in [false, true]) {
    for (final control in ['promotion-form-cancel', 'promotion-form-close']) {
      testWidgets(
        '$control discards without writing returns to source detail=$fromDetail',
        (tester) async {
          addTearDown(tester.view.resetViewInsets);
          final repo = EditRepo();
          await h.pump(tester, repo);
          if (fromDetail) {
            await h.tap(tester, 'promotion-view-local');
            await h.tap(tester, 'edit-promotion');
          } else {
            await open(tester);
          }
          await tester.enterText(
            find.byKey(const Key('promotion-code')),
            'DRAFT',
          );
          await h.tap(tester, control);
          expect(find.text('Discard changes?'), findsOneWidget);
          await tester.tap(find.byKey(const Key('promotion-discard-cancel')));
          await tester.pumpAndSettle();
          expect(field(tester, 'promotion-code'), 'DRAFT');
          await h.tap(tester, control);
          await tester.tap(find.byKey(const Key('promotion-discard-confirm')));
          await tester.pumpAndSettle();
          expect(repo.writes, 0);
          expect(
            find.byType(fromDetail ? PromotionDetailScreen : PromotionsScreen),
            findsOneWidget,
          );
        },
      );
    }
  }
  testWidgets('unchanged direct link closes without discard prompt', (
    tester,
  ) async {
    final result = await h.pump(tester, EditRepo());
    result.router.go('/app/promotions/local/edit');
    await tester.pumpAndSettle();
    await h.tap(tester, 'promotion-form-close');
    expect(find.byType(PromotionsScreen), findsOneWidget);
    expect(find.byType(AlertDialog), findsNothing);
  });
  for (final global in [false, true]) {
    testWidgets('save exact patch preserves dates and scope global=$global', (
      tester,
    ) async {
      final repo = EditRepo(global: global);
      await h.pump(tester, repo);
      await open(tester);
      await tester.enterText(
        find.byKey(const Key('promotion-code')),
        'CHANGED',
      );
      await h.tap(tester, 'promotion-form-save');
      if (global) {
        expect(find.text('Modify global promotion'), findsOneWidget);
        await tester.tap(find.byKey(const Key('global-save-cancel')));
        await tester.pumpAndSettle();
        expect(repo.writes, 0);
        await h.tap(tester, 'promotion-form-save');
        await tester.tap(find.byKey(const Key('global-save-confirm')));
        await tester.pumpAndSettle();
      }
      expect(repo.writes, 1);
      expect(repo.patch, {'code': 'CHANGED'});
      expect(
        repo.current.single.startsAt,
        DateTime.parse('2035-07-02T15:43:00Z'),
      );
      expect(
        repo.current.single.endsAt,
        DateTime.parse('2035-07-04T18:45:00Z'),
      );
      expect(repo.current.single.locationId, global ? isNull : 'a');
      expect(find.byType(PromotionDetailScreen), findsOneWidget);
      expect(find.text('CHANGED'), findsOneWidget);
    });
  }
  testWidgets('validation and backend errors translated in Spanish', (
    tester,
  ) async {
    final repo = EditRepo()
      ..error = const ApiException(
        message: 'Administrator access is required.',
        statusCode: 403,
      );
    await h.pump(tester, repo, lang: 'es');
    await open(tester);
    await tester.enterText(find.byKey(const Key('promotion-value')), 'bad');
    await h.tap(tester, 'promotion-form-save');
    expect(repo.writes, 0);
    expect(find.byKey(const Key('promotion-validation-error')), findsOneWidget);
    await tester.ensureVisible(find.byKey(const Key('promotion-value')));
    await tester.enterText(find.byKey(const Key('promotion-value')), '13.50');
    await h.tap(tester, 'promotion-form-save');
    expect(repo.writes, 1);
    expect(find.byKey(const Key('promotion-save-error')), findsOneWidget);
    expect(find.text('Se requiere acceso de administrador.'), findsOneWidget);
    expect(find.byType(PromotionFormScreen), findsOneWidget);
  });
  testWidgets('busy save cannot submit twice or discard', (tester) async {
    final repo = EditRepo()..hold = Completer<void>();
    await h.pump(tester, repo);
    await open(tester);
    await tester.enterText(find.byKey(const Key('promotion-code')), 'CHANGED');
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('promotion-form-save')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('promotion-form-save')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(repo.writes, 1);
    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('promotion-form-save')))
          .onPressed,
      isNull,
    );
    expect(
      tester
          .widget<IconButton>(find.byKey(const Key('promotion-form-close')))
          .onPressed,
      isNull,
    );
    await tester.binding.handlePopRoute();
    await tester.pump();
    expect(find.byType(PromotionFormScreen), findsOneWidget);
    repo.hold!.complete();
    await tester.pumpAndSettle();
    expect(repo.writes, 1);
  });
  testWidgets(
    'conflict cancel does not advance original version; reload is explicit',
    (tester) async {
      final repo = EditRepo();
      await h.pump(tester, repo);
      await open(tester);
      await tester.enterText(find.byKey(const Key('promotion-code')), 'DRAFT');
      final d = repo.current.single;
      repo.current = [
        Discount.fromJson({
          ...discountEditableBody(d),
          'id': d.id,
          'code': 'SERVER',
          'locationId': d.locationId,
          'timesRedeemed': d.timesRedeemed,
          'createdAt': '2026-01-01T00:00:00Z',
          'updatedAt': '2026-02-01T00:00:00Z',
        }),
      ];
      await h.tap(tester, 'promotion-form-save');
      expect(
        find.text('This promotion was changed elsewhere.'),
        findsOneWidget,
      );
      await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
      await tester.pumpAndSettle();
      await h.tap(tester, 'promotion-form-save');
      expect(
        find.text('This promotion was changed elsewhere.'),
        findsOneWidget,
      );
      expect(repo.writes, 0);
      await tester.tap(find.widgetWithText(FilledButton, 'Reload'));
      await tester.pumpAndSettle();
      expect(field(tester, 'promotion-code'), 'SERVER');
      expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('promotion-form-save')))
            .onPressed,
        isNull,
      );
    },
  );
}
