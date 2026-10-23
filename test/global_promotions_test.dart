import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pelines_admin_app/core/api/api_exception.dart';
import 'package:pelines_admin_app/features/promotions/models/discount.dart';
import 'package:pelines_admin_app/features/promotions/models/promotion_write.dart';
import 'package:pelines_admin_app/features/promotions/providers/promotions_providers.dart';

import 'promotions_layout_test.dart' as h;

import 'package:pelines_admin_app/features/locations/providers/locations_providers.dart';

class GlobalRepo extends h.Repo {
  GlobalRepo() : super([h.discount(id: 'global', scope: null)]);
  int updates = 0;
  Map<String, dynamic>? patch;
  Object? updateError;
  Completer<void>? updateHold;
  @override
  Future<Discount> updatePromotion(String id, Map<String, dynamic> body) async {
    updates++;
    patch = body;
    await updateHold?.future;
    if (updateError != null) throw updateError!;
    current = [
      Discount.fromJson({
        ...discountEditableBody(current.single),
        'id': id,
        'locationId': current.single.locationId,
        'timesRedeemed': current.single.timesRedeemed,
        'createdAt': '2026-01-01T00:00:00Z',
        'updatedAt': '2026-02-01T00:00:00Z',
        ...body,
      }),
    ];
    return current.single;
  }
}

void main() {
  for (final lang in ['en', 'es']) {
    testWidgets('global edit cancel confirm and fixed scope $lang', (
      tester,
    ) async {
      final repo = GlobalRepo();
      await h.pump(tester, repo, lang: lang, width: 320, scale: 2);
      await h.tap(tester, 'promotion-edit-global');
      final scope = lang == 'en' ? 'All locations' : 'Todas las sucursales';
      expect(find.text(scope), findsWidgets);
      final code = find.byType(TextField).first;
      expect(tester.widget<TextField>(code).controller!.text, 'TEST-global');
      await tester.enterText(code, 'GLOBALNEW');
      await h.tap(tester, 'promotion-form-save');
      expect(
        find.text(
          lang == 'en'
              ? 'Modify global promotion'
              : 'Modificar promoción global',
        ),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const Key('global-save-cancel')));
      await tester.pumpAndSettle();
      expect(repo.updates, 0);
      expect(find.text(scope), findsWidgets);
      await h.tap(tester, 'promotion-form-save');
      await tester.tap(find.byKey(const Key('global-save-confirm')));
      await tester.pumpAndSettle();
      expect(repo.updates, 1);
      expect(repo.patch, {'code': 'GLOBALNEW'});
      expect(repo.current.single.locationId, isNull);
      expect(repo.current.single.code, 'GLOBALNEW');
      expect(tester.takeException(), isNull);
    });
    testWidgets('global delete cancel then confirm $lang', (tester) async {
      final repo = GlobalRepo();
      await h.pump(tester, repo, lang: lang);
      await h.tap(tester, 'promotion-delete-global');
      expect(
        find.text(
          lang == 'en'
              ? 'Delete global promotion'
              : 'Eliminar promoción global',
        ),
        findsOneWidget,
      );
      expect(find.textContaining('TEST-global'), findsWidgets);
      await tester.tap(find.byKey(const Key('promotion-delete-cancel')));
      await tester.pumpAndSettle();
      expect(repo.deletes, 0);
      await h.tap(tester, 'promotion-delete-global');
      await tester.tap(find.byKey(const Key('promotion-delete-confirm')));
      await tester.pumpAndSettle();
      expect(repo.deletes, 1);
      expect(repo.current, isEmpty);
    });
  }
  for (final status in [403, 500]) {
    test('global save server rejection $status is not success', () async {
      final repo = GlobalRepo()
        ..updateError = ApiException(message: 'Rejected', statusCode: status);
      final c = await h.ready(repo);
      await c
          .read(promotionFormMutationProvider.notifier)
          .edit(
            discountId: 'global',
            locationId: 'a',
            global: true,
            originalUpdatedAt: DateTime.utc(2026),
            desired: {
              ...discountEditableBody(repo.current.single),
              'code': 'NEW',
            },
          );
      expect(repo.updates, 1);
      expect(
        c.read(promotionFormMutationProvider).phase,
        PromotionFormPhase.error,
      );
      expect(repo.current.single.code, 'TEST-global');
    });
    test('global delete server rejection $status is not success', () async {
      final repo = GlobalRepo()
        ..applyDelete = false
        ..deleteError = ApiException(message: 'Rejected', statusCode: status);
      final c = await h.ready(repo);
      await c
          .read(promotionMutationProvider.notifier)
          .delete(
            discountId: 'global',
            locationId: 'a',
            global: true,
            originalUpdatedAt: DateTime.utc(2026),
          );
      expect(repo.deletes, 1);
      expect(
        c.read(promotionMutationProvider).phase,
        PromotionMutationPhase.error,
      );
      expect(c.read(promotionsProvider).value, hasLength(1));
    });
  }
  test(
    'global edit prevents duplicate writes and retains null scope',
    () async {
      final repo = GlobalRepo()..updateHold = Completer<void>();
      final c = await h.ready(repo);
      Future<void> save() => c
          .read(promotionFormMutationProvider.notifier)
          .edit(
            discountId: 'global',
            locationId: 'a',
            global: true,
            originalUpdatedAt: DateTime.utc(2026),
            desired: {
              ...discountEditableBody(repo.current.single),
              'code': 'NEW',
              'locationId': 'b',
            },
          );
      final first = save();
      await Future<void>.delayed(Duration.zero);
      await save();
      expect(repo.updates, 1);
      repo.updateHold!.complete();
      await first;
      expect(repo.patch!.containsKey('locationId'), isFalse);
      expect(repo.current.single.locationId, isNull);
      expect(
        c.read(promotionFormMutationProvider).phase,
        PromotionFormPhase.success,
      );
    },
  );
  test('global delete blocks duplicate submissions', () async {
    final repo = GlobalRepo()..deleteHold = Completer<void>();
    final c = await h.ready(repo);
    Future<void> remove() => c
        .read(promotionMutationProvider.notifier)
        .delete(
          discountId: 'global',
          locationId: 'a',
          global: true,
          originalUpdatedAt: DateTime.utc(2026),
        );
    final first = remove();
    await repo.deleteStarted.future;
    await remove();
    expect(repo.deletes, 1);
    repo.deleteHold!.complete();
    await first;
    expect(
      c.read(promotionMutationProvider).phase,
      PromotionMutationPhase.success,
    );
  });
  test('global delete preserves context protection during preflight', () async {
    final repo = GlobalRepo();
    final c = await h.ready(repo);
    repo.readHold = Completer<void>();
    final pending = c
        .read(promotionMutationProvider.notifier)
        .delete(
          discountId: 'global',
          locationId: 'a',
          global: true,
          originalUpdatedAt: DateTime.utc(2026),
        );
    (c.read(currentLocationProvider.notifier) as h.Current).replace(
      h.location('b'),
    );
    repo.readHold!.complete();
    await pending;
    expect(repo.deletes, 0);
    expect(
      c.read(promotionMutationProvider).phase,
      PromotionMutationPhase.error,
    );
  });
  for (final other in [false, true]) {
    test('global write rejects changed scope or stamp $other', () async {
      final repo = GlobalRepo();
      repo.current = [
        h.discount(
          id: 'global',
          scope: other ? 'b' : null,
          updated: other ? null : DateTime.utc(2026, 2),
        ),
      ];
      final c = await h.ready(repo);
      await c
          .read(promotionFormMutationProvider.notifier)
          .edit(
            discountId: 'global',
            locationId: 'a',
            global: true,
            originalUpdatedAt: DateTime.utc(2026),
            desired: {'code': 'NEW'},
          );
      await c
          .read(promotionMutationProvider.notifier)
          .delete(
            discountId: 'global',
            locationId: 'a',
            global: true,
            originalUpdatedAt: DateTime.utc(2026),
          );
      expect(repo.updates, 0);
      expect(repo.deletes, 0);
    });
  }
}
