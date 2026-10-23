import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pelines_admin_app/core/api/api_exception.dart';
import 'package:pelines_admin_app/features/locations/providers/locations_providers.dart';
import 'package:pelines_admin_app/features/promotions/models/discount.dart';
import 'package:pelines_admin_app/features/promotions/models/promotion_write.dart';
import 'package:pelines_admin_app/features/promotions/presentation/promotion_detail_screen.dart';
import 'package:pelines_admin_app/features/promotions/presentation/promotion_form_screen.dart';
import 'package:pelines_admin_app/features/promotions/presentation/promotions_screen.dart';
import 'package:pelines_admin_app/features/promotions/providers/promotions_providers.dart';

import 'promotions_layout_test.dart' as h;

Future<void> open(WidgetTester tester, {bool global = false}) =>
    h.tap(tester, 'promotion-view-${global ? 'global' : 'local'}');
void main() {
  for (final width in [320.0, 390.0, 800.0]) {
    for (final scale in [1.0, 2.0]) {
      for (final lang in ['en', 'es']) {
        testWidgets('details ten ordered rows $width $scale $lang', (
          tester,
        ) async {
          final repo = h.Repo([
            h.discount(code: 'REAL-LONG-PROMOTION-CODE-1234567890'),
          ]);
          await h.pump(tester, repo, width: width, scale: scale, lang: lang);
          await open(tester);
          expect(find.byType(PromotionDetailScreen), findsOneWidget);
          expect(find.byType(AlertDialog), findsNothing);
          expect(
            find.text('REAL-LONG-PROMOTION-CODE-1234567890'),
            findsOneWidget,
          );
          final labels = lang == 'en'
              ? [
                  'Type',
                  'Value',
                  'Applies to',
                  'Minimum order',
                  'Start date',
                  'End date',
                  'Usage limit',
                  'Times redeemed',
                  'Location',
                  'Status',
                ]
              : [
                  'Tipo',
                  'Valor',
                  'Se aplica a',
                  'Pedido mínimo',
                  'Fecha de inicio',
                  'Fecha de fin',
                  'Límite de uso',
                  'Canjes realizados',
                  'Sucursal',
                  'Estado',
                ];
          double previous = -1;
          for (final label in labels) {
            final row = find.byKey(ValueKey('promotion-detail-row-$label'));
            expect(row, findsOneWidget);
            final y = tester.getTopLeft(row).dy;
            expect(y, greaterThan(previous));
            previous = y;
          }
          expect(find.text('12%'), findsOneWidget);
          expect(find.text('2 / 5'), findsOneWidget);
          expect(find.text('Tualatin'), findsOneWidget);
          expect(find.text('—'), findsNWidgets(2));
          await h.tap(tester, 'promotion-details-close');
          expect(find.byType(PromotionsScreen), findsOneWidget);
          expect(tester.takeException(), isNull);
        });
      }
    }
  }
  testWidgets('real fixed money dates global scope unlimited and expired', (
    tester,
  ) async {
    final d = h.discount(
      id: 'global',
      scope: null,
      type: 'fixed',
      value: 1234,
      limit: null,
      used: 7,
    );
    final repo = h.Repo([
      Discount.fromJson({
        ...discountEditableBody(d),
        'id': d.id,
        'locationId': null,
        'timesRedeemed': 7,
        'minSubtotalCents': 599,
        'startsAt': '2019-12-31T08:00:00Z',
        'endsAt': '2020-01-02T08:00:00Z',
        'createdAt': '2019-01-01T00:00:00Z',
        'updatedAt': '2026-01-01T00:00:00Z',
      }),
    ]);
    await h.pump(tester, repo);
    await open(tester, global: true);
    for (final text in [
      r'$12.34',
      r'$5.99',
      '2019-12-31',
      '2020-01-02',
      'Unlimited',
      '7',
      'All locations',
      'Expired',
    ]) {
      expect(find.text(text), findsOneWidget);
    }
  });
  for (final key in [
    'promotion-details-back',
    'promotion-details-x',
    'promotion-details-close',
  ]) {
    testWidgets(
      '$key returns to list preserving location including deep link',
      (tester) async {
        final result = await h.pump(tester, h.Repo([h.discount()]));
        result.router.go('/app/promotions/local');
        await tester.pumpAndSettle();
        await h.tap(tester, key);
        expect(find.byType(PromotionsScreen), findsOneWidget);
        expect(result.c.read(currentLocationProvider).value!.id, 'a');
      },
    );
  }
  testWidgets('system back returns to list', (tester) async {
    await h.pump(tester, h.Repo([h.discount()]));
    await open(tester);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byType(PromotionsScreen), findsOneWidget);
  });
  for (final global in [false, true]) {
    testWidgets('detail edit reuses form global=$global', (tester) async {
      final id = global ? 'global' : 'local';
      await h.pump(
        tester,
        h.Repo([h.discount(id: id, scope: global ? null : 'a')]),
      );
      await open(tester, global: global);
      await h.tap(tester, 'edit-promotion');
      expect(
        tester
            .widget<PromotionFormScreen>(find.byType(PromotionFormScreen))
            .discountId,
        id,
      );
      expect(find.byType(TextField), findsWidgets);
    });
    testWidgets('detail delete cancel then successful return global=$global', (
      tester,
    ) async {
      final id = global ? 'global' : 'local';
      final repo = h.Repo([h.discount(id: id, scope: global ? null : 'a')]);
      final result = await h.pump(tester, repo);
      await open(tester, global: global);
      await h.tap(tester, 'promotion-details-delete');
      expect(
        find.text(global ? 'Delete global promotion' : 'Delete discount code?'),
        findsOneWidget,
      );
      expect(find.textContaining('TEST-$id'), findsWidgets);
      await tester.tap(find.byKey(const Key('promotion-delete-cancel')));
      await tester.pumpAndSettle();
      expect(find.byType(PromotionDetailScreen), findsOneWidget);
      expect(repo.deletes, 0);
      await h.tap(tester, 'promotion-details-delete');
      await tester.tap(find.byKey(const Key('promotion-delete-confirm')));
      await tester.pumpAndSettle();
      expect(repo.deletes, 1);
      expect(find.byType(PromotionsScreen), findsOneWidget);
      expect(result.c.read(promotionsProvider).value, isEmpty);
    });
  }
  testWidgets('delete server rejection stays on details and keeps record', (
    tester,
  ) async {
    final repo = h.Repo([h.discount()])
      ..applyDelete = false
      ..deleteError = const ApiException(
        message: 'Administrator access is required.',
        statusCode: 403,
      );
    await h.pump(tester, repo);
    await open(tester);
    await h.tap(tester, 'promotion-details-delete');
    await tester.tap(find.byKey(const Key('promotion-delete-confirm')));
    await tester.pumpAndSettle();
    expect(find.byType(PromotionDetailScreen), findsOneWidget);
    expect(find.text('Administrator access is required.'), findsOneWidget);
    expect(repo.current, hasLength(1));
  });
  testWidgets(
    'detail stale snapshot cannot delete and duplicate dialogs blocked',
    (tester) async {
      final repo = h.Repo([h.discount()]);
      await h.pump(tester, repo);
      await open(tester);
      repo.current = [h.discount(updated: DateTime.utc(2026, 2))];
      await h.tap(tester, 'promotion-details-delete');
      expect(find.byType(AlertDialog), findsOneWidget);
      await tester.tap(find.byKey(const Key('promotion-delete-confirm')));
      await tester.pumpAndSettle();
      expect(repo.deletes, 0);
      expect(find.byType(PromotionDetailScreen), findsOneWidget);
      expect(
        find.text('This promotion was changed elsewhere.'),
        findsOneWidget,
      );
    },
  );
  testWidgets('missing record and other branch are not editable', (
    tester,
  ) async {
    final repo = h.Repo([h.discount()]);
    final result = await h.pump(tester, repo);
    result.router.go('/app/promotions/missing');
    await tester.pumpAndSettle();
    expect(find.text('This promotion no longer exists.'), findsOneWidget);
    result.router.go('/app/promotions/local');
    await tester.pumpAndSettle();
    (result.c.read(currentLocationProvider.notifier) as h.Current).replace(
      h.location('b'),
    );
    await tester.pumpAndSettle();
    expect(
      find.text('This promotion is not available for the selected location.'),
      findsOneWidget,
    );
    expect(find.byKey(const Key('edit-promotion')), findsNothing);
    expect(find.byKey(const Key('promotion-details-delete')), findsNothing);
  });
  testWidgets('detail delete blocks duplicates and back during request', (
    tester,
  ) async {
    final repo = h.Repo([h.discount()])..deleteHold = Completer<void>();
    await h.pump(tester, repo);
    await open(tester);
    await h.tap(tester, 'promotion-details-delete');
    expect(
      tester
          .widget<TextButton>(find.byKey(const Key('promotion-details-delete')))
          .onPressed,
      isNull,
    );
    await tester.tap(find.byKey(const Key('promotion-delete-confirm')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(repo.deletes, 1);
    expect(
      tester
          .widget<TextButton>(find.byKey(const Key('promotion-details-delete')))
          .onPressed,
      isNull,
    );
    await tester.binding.handlePopRoute();
    await tester.pump();
    expect(find.byType(PromotionDetailScreen), findsOneWidget);
    repo.deleteHold!.complete();
    await tester.pumpAndSettle();
    expect(repo.deletes, 1);
    expect(find.byType(PromotionsScreen), findsOneWidget);
  });
  testWidgets('changing detail ID resolves new record and snapshot', (
    tester,
  ) async {
    final repo = h.Repo([
      h.discount(),
      h.discount(id: 'global', scope: null, updated: DateTime.utc(2026, 2)),
    ]);
    final result = await h.pump(tester, repo);
    await open(tester);
    result.router.go('/app/promotions/global');
    await tester.pumpAndSettle();
    expect(find.text('TEST-global'), findsOneWidget);
    expect(find.text('TEST-local'), findsNothing);
    await h.tap(tester, 'promotion-details-delete');
    await tester.tap(find.byKey(const Key('promotion-delete-confirm')));
    await tester.pumpAndSettle();
    expect(repo.deletes, 1);
    expect(repo.current.single.id, 'local');
    expect(find.byType(PromotionsScreen), findsOneWidget);
  });
  testWidgets('detail loading error retry and localization', (tester) async {
    final repo = h.Repo([h.discount()])..readHold = Completer<void>();
    final result = await h.pump(tester, repo, lang: 'es');
    result.router.go('/app/promotions/local');
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    repo.fail = true;
    repo.readHold!.complete();
    await tester.pumpAndSettle();
    expect(find.text('Mock loading error'), findsOneWidget);
    repo.fail = false;
    await tester.tap(find.text('Intentar de nuevo'));
    await tester.pumpAndSettle();
    expect(find.text('Detalles del código de descuento'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
