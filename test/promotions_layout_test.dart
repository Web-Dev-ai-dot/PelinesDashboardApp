import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:pelines_admin_app/app/l10n/admin_localizations.dart';
import 'package:pelines_admin_app/app/navigation/admin_navigation.dart';
import 'package:pelines_admin_app/app/theme/app_theme.dart';
import 'package:pelines_admin_app/app/theme/pelines_components.dart';
import 'package:pelines_admin_app/core/api/api_client.dart';
import 'package:pelines_admin_app/core/api/api_exception.dart';
import 'package:pelines_admin_app/features/locations/models/location.dart';
import 'package:pelines_admin_app/features/locations/providers/locations_providers.dart';
import 'package:pelines_admin_app/features/promotions/data/promotions_repository.dart';
import 'package:pelines_admin_app/features/promotions/models/discount.dart';
import 'package:pelines_admin_app/features/promotions/presentation/promotions_screen.dart';
import 'package:pelines_admin_app/features/promotions/presentation/promotion_detail_screen.dart';
import 'package:pelines_admin_app/features/promotions/presentation/promotion_form_screen.dart';
import 'package:pelines_admin_app/features/promotions/providers/promotions_providers.dart';

Location location([String id = 'a']) => Location(
  id: id,
  name: id == 'a' ? 'Tualatin' : 'Troutdale',
  slug: id,
  address: '42 Backend Road',
  isActive: true,
  isAcceptingOrders: true,
  deliveryFeeCents: 0,
  deliveryMinimumCents: 0,
  createdAt: DateTime.utc(2026),
  updatedAt: DateTime.utc(2026),
);
Discount discount({
  String id = 'local',
  String? scope = 'a',
  String? code,
  String type = 'percent',
  int value = 12,
  int? limit = 5,
  int used = 2,
  String applies = 'both',
  bool active = true,
  DateTime? start,
  DateTime? end,
  DateTime? updated,
}) => Discount(
  id: id,
  code: code ?? 'TEST-$id',
  type: type,
  value: value,
  minSubtotalCents: 0,
  startsAt: start,
  endsAt: end,
  usageLimit: limit,
  timesRedeemed: used,
  locationId: scope,
  appliesTo: applies,
  isActive: active,
  createdAt: DateTime.utc(2026),
  updatedAt: updated ?? DateTime.utc(2026),
);

class Current extends CurrentLocationController {
  Current(this.selected);
  final Location selected;
  @override
  Future<Location?> build() async => selected;
  void replace(Location value) => state = AsyncData(value);
}

class Repo implements PromotionsRepository {
  Repo(this.current);
  List<Discount> current;
  int reads = 0, deletes = 0;
  bool fail = false, applyDelete = true;
  int? failReadsAfter;
  Object? deleteError;
  Completer<void>? readHold, deleteHold;
  final deleteStarted = Completer<void>();
  @override
  Future<List<Discount>> getDiscounts() async {
    reads++;
    await readHold?.future;
    if (fail || (failReadsAfter != null && reads > failReadsAfter!)) {
      throw const ApiException(message: 'Mock loading error', statusCode: 503);
    }
    return [...current];
  }

  @override
  Future<void> deletePromotion(String id) async {
    deletes++;
    if (!deleteStarted.isCompleted) deleteStarted.complete();
    await deleteHold?.future;
    if (applyDelete) current = current.where((d) => d.id != id).toList();
    if (deleteError != null) throw deleteError!;
  }

  @override
  Future<Discount> createPromotion(Map<String, dynamic> body) =>
      throw UnimplementedError();
  @override
  Future<Discount> updatePromotion(String id, Map<String, dynamic> patch) =>
      throw UnimplementedError();
  @override
  Future<Discount> setActive(String id, bool isActive) =>
      throw UnimplementedError();
}

ProviderContainer container(Repo repo, {String branch = 'a'}) =>
    ProviderContainer(
      retry: (_, _) => null,
      overrides: [
        promotionsRepositoryProvider.overrideWithValue(repo),
        currentLocationProvider.overrideWith(() => Current(location(branch))),
      ],
    );
Future<ProviderContainer> ready(Repo repo, {String branch = 'a'}) async {
  final c = container(repo, branch: branch);
  addTearDown(c.dispose);
  await c.read(currentLocationProvider.future);
  await c.read(promotionsProvider.future);
  return c;
}

Future<({ProviderContainer c, GoRouter router})> pump(
  WidgetTester tester,
  Repo repo, {
  double width = 390,
  double scale = 1,
  String lang = 'en',
}) async {
  tester.view.physicalSize = Size(width, 1100);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final c = container(repo);
  addTearDown(c.dispose);
  final router = GoRouter(
    initialLocation: '/app/promotions',
    routes: [
      GoRoute(
        path: '/app/promotions',
        builder: (_, _) => const PromotionsScreen(),
      ),
      GoRoute(
        path: '/app/promotions/new',
        builder: (_, _) => const PromotionFormScreen(),
      ),
      GoRoute(
        path: '/app/promotions/:id/edit',
        builder: (_, s) =>
            PromotionFormScreen(discountId: s.pathParameters['id']!),
      ),
      GoRoute(
        path: '/app/promotions/:id',
        builder: (_, s) =>
            PromotionDetailScreen(discountId: s.pathParameters['id']!),
      ),
    ],
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: c,
      child: MaterialApp.router(
        routerConfig: router,
        theme: AppTheme.light,
        locale: Locale(lang),
        supportedLocales: AdminLocalizations.supportedLocales,
        localizationsDelegates: const [
          AdminLocalizations.delegate,
          ...GlobalMaterialLocalizations.delegates,
        ],
        builder: (ctx, child) => MediaQuery(
          data: MediaQuery.of(ctx)
              .copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
      ),
    ),
  );
  await tester.pump();
  if (repo.readHold == null) await tester.pumpAndSettle();
  return (c: c, router: router);
}

Future<void> tap(WidgetTester tester, String key) async {
  final finder = find.byKey(Key(key));
  await tester.scrollUntilVisible(
    finder,
    250,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.pumpAndSettle();
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Future<String> count(WidgetTester tester) async {
  final finder = find.byKey(const Key('promotions-count'));
  await tester.scrollUntilVisible(
    finder,
    -250,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.pumpAndSettle();
  return tester.widget<PelinesStateBadge>(finder).label;
}

IconButton action(WidgetTester tester, String key) => tester.widget<IconButton>(
  find.descendant(of: find.byKey(Key(key)), matching: find.byType(IconButton)),
);
ApiException timeout() => ApiException(
  message: 'timeout',
  cause: DioException(
    requestOptions: RequestOptions(path: 'discounts/local'),
    type: DioExceptionType.receiveTimeout,
  ),
);
void main() {
  for (final status in [200, 204]) {
    test('DELETE existing contract supports empty response $status', () async {
      final requests = <RequestOptions>[];
      final dio = Dio(BaseOptions(baseUrl: 'https://example.test/v1/'))
        ..interceptors.add(
          InterceptorsWrapper(
            onRequest: (o, h) {
              requests.add(o);
              h.resolve(
                Response<dynamic>(
                  requestOptions: o,
                  statusCode: status,
                  data: null,
                ),
              );
            },
          ),
        );
      await ApiPromotionsRepository(ApiClient(dio: dio))
          .deletePromotion('local');
      expect(requests, hasLength(1));
      expect(requests.single.method, 'DELETE');
      expect(requests.single.path, 'discounts/local');
      expect(requests.single.data, isNull);
    });
  }
  test(
    'delete rejects changed stamp scope and branch before any DELETE',
    () async {
      for (final canonical in [
        discount(updated: DateTime.utc(2026, 2)),
        discount(scope: null),
        discount(scope: 'b'),
      ]) {
        final repo = Repo([canonical]);
        final c = await ready(repo);
        await c
            .read(promotionMutationProvider.notifier)
            .delete(
              discountId: 'local',
              locationId: 'a',
              originalUpdatedAt: DateTime.utc(2026),
            );
        expect(repo.deletes, 0);
        expect(
          c.read(promotionMutationProvider).phase,
          isNot(PromotionMutationPhase.success),
        );
      }
      final repo = Repo([discount()]);
      final c = await ready(repo, branch: 'b');
      final before = repo.reads;
      await c
          .read(promotionMutationProvider.notifier)
          .delete(
            discountId: 'local',
            locationId: 'a',
            originalUpdatedAt: DateTime.utc(2026),
          );
      expect(repo.reads, before);
      expect(repo.deletes, 0);
    },
  );
  test('location change while preflight is pending never DELETEs', () async {
    final repo = Repo([discount()]);
    final c = await ready(repo);
    repo.readHold = Completer<void>();
    final pending = c
        .read(promotionMutationProvider.notifier)
        .delete(
          discountId: 'local',
          locationId: 'a',
          originalUpdatedAt: DateTime.utc(2026),
        );
    (c.read(currentLocationProvider.notifier) as Current).replace(
      location('b'),
    );
    repo.readHold!.complete();
    await pending;
    expect(repo.deletes, 0);
  });
  test(
    'successful deletion checks canonical absence and blocks duplicates',
    () async {
      final repo = Repo([discount(), discount(id: 'global', scope: null)])
        ..deleteHold = Completer<void>();
      final c = await ready(repo);
      final ctrl = c.read(promotionMutationProvider.notifier);
      final pending = ctrl.delete(
        discountId: 'local',
        locationId: 'a',
        originalUpdatedAt: DateTime.utc(2026),
      );
      await repo.deleteStarted.future;
      await ctrl.delete(
        discountId: 'local',
        locationId: 'a',
        originalUpdatedAt: DateTime.utc(2026),
      );
      expect(repo.deletes, 1);
      repo.deleteHold!.complete();
      await pending;
      expect(
        c.read(promotionMutationProvider).phase,
        PromotionMutationPhase.success,
      );
      expect(c.read(promotionsProvider).value!.map((d) => d.id), ['global']);
      expect(repo.reads, 3);
    },
  );
  for (final applied in [true, false]) {
    test(
      'ambiguous delete applied=$applied reads back without retry',
      () async {
        final repo = Repo([discount()])
          ..deleteError = timeout()
          ..applyDelete = applied;
        final c = await ready(repo);
        await c
            .read(promotionMutationProvider.notifier)
            .delete(
              discountId: 'local',
              locationId: 'a',
              originalUpdatedAt: DateTime.utc(2026),
            );
        expect(repo.deletes, 1);
        expect(
          c.read(promotionMutationProvider).phase,
          applied
              ? PromotionMutationPhase.success
              : PromotionMutationPhase.error,
        );
      },
    );
  }
  test('already removed does not send DELETE and failed reconciliation is explicit', () async {
    final repo = Repo([]);
    final c = await ready(repo);
    await c
        .read(promotionMutationProvider.notifier)
        .delete(
          discountId: 'local',
          locationId: 'a',
          originalUpdatedAt: DateTime.utc(2026),
        );
    expect(repo.deletes, 0);
    expect(
      c.read(promotionMutationProvider).phase,
      PromotionMutationPhase.success,
    );
    repo.current = [discount()];
    repo.failReadsAfter = repo.reads + 1;
    await c
        .read(promotionMutationProvider.notifier)
        .delete(
          discountId: 'local',
          locationId: 'a',
          originalUpdatedAt: DateTime.utc(2026),
        );
    expect(repo.deletes, 1);
    expect(
      c.read(promotionMutationProvider).message,
      contains('could not be confirmed'),
    );
  });
  for (final width in [320.0, 390.0, 768.0, 1400.0]) {
    for (final scale in [1.0, 2.0]) {
      for (final lang in ['en', 'es']) {
        testWidgets('cards full content $width/$scale/$lang', (tester) async {
          final repo = Repo([
            discount(code: 'LONG-DISCOUNT-CODE-FROM-BACKEND'),
            discount(
              id: 'global',
              scope: null,
              type: 'fixed',
              value: 1234,
              limit: null,
              used: 3,
            ),
            discount(id: 'other', scope: 'b'),
          ]);
          await pump(tester, repo, width: width, scale: scale, lang: lang);
          expect(
            find.text('Tualatin · 42 Backend Road', findRichText: true),
            findsOneWidget,
          );
          expect(
            tester
                .widget<OutlinedButton>(
                  find.byKey(const Key('generate-promotion-code')),
                )
                .onPressed,
            isNull,
          );
          expect(find.byType(DataTable), findsNothing);
          await tester.scrollUntilVisible(
            find.byKey(const Key('promotion-card-local')),
            250,
            scrollable: find.byType(Scrollable).first,
          );
          await tester.pumpAndSettle();
          expect(await count(tester), lang == 'en' ? '2 total' : '2 en total');
          expect(find.text('12%'), findsOneWidget);
          expect(find.text('2 / 5'), findsOneWidget);
          await tap(tester, 'promotion-view-global');
          expect(find.byType(PromotionDetailScreen), findsOneWidget);
          expect(tester.takeException(), isNull);
        });
      }
    }
  }
  testWidgets(
    'global buttons permit edit and delete; unlimited money is real',
    (tester) async {
      final repo = Repo([
        discount(
          id: 'global',
          scope: null,
          type: 'fixed',
          value: 1234,
          limit: null,
          used: 3,
        ),
      ]);
      final result = await pump(tester, repo);
      await tester.scrollUntilVisible(
        find.byKey(const Key('promotion-card-global')),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      expect(find.text(r'$12.34'), findsOneWidget);
      expect(find.text('3 · Unlimited'), findsOneWidget);
      expect(
        find.text('This promotion applies to all locations.'),
        findsOneWidget,
      );
      expect(find.byTooltip('Edit · All locations · Read-only'), findsNothing);
      expect(action(tester, 'promotion-edit-global').onPressed, isNotNull);
      expect(action(tester, 'promotion-delete-global').onPressed, isNotNull);
      await tap(tester, 'promotion-delete-global');
      expect(
        result.router.routeInformationProvider.value.uri.path,
        '/app/promotions',
      );
      expect(find.text('Delete global promotion'), findsOneWidget);
      await tester.tap(find.byKey(const Key('promotion-delete-cancel')));
      await tester.pumpAndSettle();
      expect(repo.deletes, 0);
      expect(find.byType(PromotionDetailScreen), findsNothing);
      expect(
        tester.getSize(find.byKey(const Key('promotion-delete-global'))).height,
        greaterThanOrEqualTo(48),
      );
    },
  );
  final localStatuses = <String, Discount>{
    'active': discount(),
    'inactive': discount(active: false),
    'expired': discount(end: DateTime.utc(2020)),
    'scheduled': discount(start: DateTime.utc(2100)),
    'limit reached': discount(limit: 2, used: 2),
  };
  for (final entry in localStatuses.entries) {
    testWidgets('selected-location ${entry.key} permits edit and delete', (
      tester,
    ) async {
      await pump(
        tester,
        Repo([entry.value, discount(id: 'other', scope: 'b')]),
      );
      await tester.scrollUntilVisible(
        find.byKey(const Key('promotion-delete-local')),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      expect(action(tester, 'promotion-edit-local').onPressed, isNotNull);
      expect(action(tester, 'promotion-delete-local').onPressed, isNotNull);
      expect(find.byKey(const Key('promotion-card-other')), findsNothing);
    });
  }
  for (final kind in ['view', 'edit', 'create']) {
    testWidgets('$kind opens existing real flow', (tester) async {
      await pump(tester, Repo([discount()]));
      await tap(
        tester,
        kind == 'create' ? 'add-promotion' : 'promotion-$kind-local',
      );
      if (kind == 'view') {
        expect(
          tester
              .widget<PromotionDetailScreen>(find.byType(PromotionDetailScreen))
              .discountId,
          'local',
        );
      } else {
        expect(
          tester
              .widget<PromotionFormScreen>(find.byType(PromotionFormScreen))
              .discountId,
          kind == 'edit' ? 'local' : null,
        );
        expect(
          find.text(kind == 'edit' ? 'Edit Promotion' : 'Add Promotion'),
          findsOneWidget,
        );
      }
    });
  }
  testWidgets('all model statuses are preserved in cards', (tester) async {
    final repo = Repo([
      discount(id: 'active'),
      discount(id: 'expired', end: DateTime.utc(2020)),
      discount(id: 'scheduled', start: DateTime.utc(2100)),
      discount(id: 'inactive', active: false),
      discount(id: 'limit', limit: 2, used: 2),
    ]);
    await pump(tester, repo);
    await tester.scrollUntilVisible(
      find.byKey(const Key('promotion-card-active')),
      250,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    for (final label in [
      'Active',
      'Expired',
      'Scheduled',
      'Inactive',
      'Usage limit reached',
    ]) {
      expect(find.text(label), findsOneWidget);
    }
    expect(find.text('2 / 2'), findsOneWidget);
  });
  testWidgets(
    'delete cancellation does not write then success updates list and count',
    (tester) async {
      final repo = Repo([discount(), discount(id: 'global', scope: null)]);
      await pump(tester, repo);
      await tap(tester, 'promotion-delete-local');
      await tester.tap(find.byKey(const Key('promotion-delete-cancel')));
      await tester.pumpAndSettle();
      expect(repo.deletes, 0);
      await tap(tester, 'promotion-delete-local');
      await tester.tap(find.byKey(const Key('promotion-delete-confirm')));
      await tester.pumpAndSettle();
      expect(repo.deletes, 1);
      expect(find.byKey(const Key('promotion-card-local')), findsNothing);
      expect(await count(tester), '1 total');
    },
  );
  testWidgets('delete failure preserves card and reports error', (
    tester,
  ) async {
    final repo = Repo([discount()])
      ..applyDelete = false
      ..deleteError = const ApiException(
        message: 'Administrator access is required.',
        statusCode: 403,
      );
    await pump(tester, repo);
    await tap(tester, 'promotion-delete-local');
    await tester.tap(find.byKey(const Key('promotion-delete-confirm')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('promotion-card-local')), findsOneWidget);
    expect(find.text('Administrator access is required.'), findsOneWidget);
    expect(repo.deletes, 1);
  });
  testWidgets('confirmed delete busy blocks all second submissions', (
    tester,
  ) async {
    final repo = Repo([discount()])..deleteHold = Completer<void>();
    await pump(tester, repo);
    await tap(tester, 'promotion-delete-local');
    await tester.tap(find.byKey(const Key('promotion-delete-confirm')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(action(tester, 'promotion-delete-local').onPressed, isNull);
    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('add-promotion')))
          .onPressed,
      isNull,
    );
    repo.deleteHold!.complete();
    await tester.pumpAndSettle();
    expect(repo.deletes, 1);
    expect(
      find.text('No promotions available for this location.'),
      findsOneWidget,
    );
  });
  testWidgets(
    'error retry empty refresh and selected branch scope remain correct',
    (tester) async {
      final repo = Repo([])..fail = true;
      final result = await pump(tester, repo);
      expect(find.text('Mock loading error'), findsOneWidget);
      repo.fail = false;
      await tester.tap(find.text('Try again'));
      await tester.pumpAndSettle();
      expect(
        find.text('No promotions available for this location.'),
        findsOneWidget,
      );
      expect(await count(tester), '0 total');
      repo.current = [
        discount(),
        discount(id: 'global', scope: null),
        discount(id: 'other', scope: 'b'),
      ];
      await tester.tap(
        find.descendant(
          of: find.byType(AdminHeaderRefresh),
          matching: find.byType(OutlinedButton),
        ),
      );
      await tester.pumpAndSettle();
      (result.c.read(currentLocationProvider.notifier) as Current).replace(
        location('b'),
      );
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.byKey(const Key('promotion-card-other')),
        250,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('promotion-card-local')), findsNothing);
      expect(find.byKey(const Key('promotion-card-other')), findsOneWidget);
      expect(await count(tester), '2 total');
    },
  );
  testWidgets('loading remains loading without a fictitious count', (
    tester,
  ) async {
    final repo = Repo([])..readHold = Completer<void>();
    await pump(tester, repo);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.byKey(const Key('promotions-count')), findsNothing);
    repo.readHold!.complete();
    await tester.pumpAndSettle();
    expect(
      find.text('No promotions available for this location.'),
      findsOneWidget,
    );
  });
}
