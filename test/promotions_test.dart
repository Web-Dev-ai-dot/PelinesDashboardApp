import 'package:dio/dio.dart';
import 'package:pelines_admin_app/features/locations/presentation/pelines_location_context.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:pelines_admin_app/app/l10n/admin_localizations.dart';
import 'package:pelines_admin_app/core/api/api_client.dart';
import 'package:pelines_admin_app/core/api/api_exception.dart';
import 'package:pelines_admin_app/features/locations/models/location.dart';
import 'package:pelines_admin_app/features/locations/providers/locations_providers.dart';
import 'package:pelines_admin_app/features/promotions/data/promotions_repository.dart';
import 'package:pelines_admin_app/features/promotions/models/discount.dart';
import 'package:pelines_admin_app/features/promotions/presentation/promotion_detail_screen.dart';
import 'package:pelines_admin_app/features/promotions/presentation/promotions_screen.dart';
import 'package:pelines_admin_app/features/promotions/providers/promotions_providers.dart';

void main() {
  group('display semantics', () {
    final DateTime now = DateTime.utc(2026, 9, 5, 12);

    test('effective status precedence and inclusive boundaries', () {
      expect(
        _discount(
          isActive: false,
          startsAt: now.add(const Duration(days: 1)),
        ).effectiveStatus(now),
        PromotionEffectiveStatus.inactive,
      );
      expect(
        _discount(startsAt: now.add(const Duration(seconds: 1)))
            .effectiveStatus(now),
        PromotionEffectiveStatus.scheduled,
      );
      expect(
        _discount(endsAt: now.subtract(const Duration(seconds: 1)))
            .effectiveStatus(now),
        PromotionEffectiveStatus.expired,
      );
      expect(
        _discount(usageLimit: 5, timesRedeemed: 5).effectiveStatus(now),
        PromotionEffectiveStatus.usageLimitReached,
      );
      expect(
        _discount(startsAt: now, endsAt: now).effectiveStatus(now),
        PromotionEffectiveStatus.active,
      );
    });

    test('percent, fixed, minimum and usage use exact wording', () {
      expect(_discount(value: 10).discountLabel, '10% off');
      expect(_discount(type: 'fixed', value: 500).discountLabel, r'$5.00 off');
      expect(_discount().minimumLabel, 'No minimum');
      expect(
        _discount(minSubtotalCents: 1500).minimumLabel,
        r'$15.00 minimum subtotal',
      );
      expect(_discount(usageLimit: 10, timesRedeemed: 5).usageLabel, '5 / 10');
      expect(_discount(timesRedeemed: 5).usageLabel, '5 claimed · Unlimited');
    });

    test('timestamps display in Pacific across a UTC day boundary', () {
      final Discount discount = _discount(
        startsAt: DateTime.parse('2026-09-05T00:30:00Z'),
      );
      expect(discount.startsLabel, contains('Sep 4, 2026'));
      expect(discount.startsLabel, contains('5:30 PM'));
    });

    test('malformed timestamps are rejected instead of reinterpreted', () {
      expect(
        () => Discount.fromJson(_json()..['startsAt'] = '2026-09-05'),
        throwsFormatException,
      );
    });
  });

  test('web date precedence, offsets and millisecond boundaries', () {
    final now = DateTime.parse('2026-09-05T12:00:00Z');
    final invalidRange = _discount(
      startsAt: now.add(const Duration(days: 1)),
      endsAt: now.subtract(const Duration(days: 1)),
    );
    expect(invalidRange.effectiveStatus(now), PromotionEffectiveStatus.expired);
    expect(
      _discount(
        isActive: false,
        endsAt: now.subtract(const Duration(days: 1)),
      ).effectiveStatus(now),
      PromotionEffectiveStatus.inactive,
    );
    final sameInstant = DateTime.parse('2026-09-05T05:00:00-07:00');
    final bounded = _discount(startsAt: sameInstant, endsAt: sameInstant);
    expect(
      bounded.effectiveStatus(now.subtract(const Duration(milliseconds: 1))),
      PromotionEffectiveStatus.scheduled,
    );
    expect(bounded.effectiveStatus(now), PromotionEffectiveStatus.active);
    expect(
      bounded.effectiveStatus(now.add(const Duration(milliseconds: 1))),
      PromotionEffectiveStatus.expired,
    );
  });

  for (final width in [390.0, 900.0]) {
    for (final language in ['en', 'es']) {
      for (final status in PromotionEffectiveStatus.values.take(4)) {
        testWidgets('$status list/detail $language at $width', (tester) async {
          tester.view.physicalSize = Size(width, 1200);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          final now = DateTime.now();
          final discount = _discount(
            locationId: 'location-a',
            isActive: status != PromotionEffectiveStatus.inactive,
            startsAt: status == PromotionEffectiveStatus.scheduled
                ? now.add(const Duration(days: 30))
                : null,
            endsAt: status == PromotionEffectiveStatus.expired
                ? now.subtract(const Duration(days: 30))
                : null,
          );
          final container = await _readyContainer(
            _FakePromotionsRepository([discount]),
          );
          addTearDown(container.dispose);
          final label = AdminLocalizations(Locale(language))
              .text(status.label, key: 'promotion.${status.label}');
          for (final screen in <Widget>[
            const PromotionsScreen(),
            const PromotionDetailScreen(discountId: 'discount-id'),
          ]) {
            await tester.pumpWidget(
              UncontrolledProviderScope(
                container: container,
                child: MaterialApp(
                  locale: Locale(language),
                  supportedLocales: AdminLocalizations.supportedLocales,
                  localizationsDelegates: const [
                    AdminLocalizations.delegate,
                    ...GlobalMaterialLocalizations.delegates,
                  ],
                  home: screen,
                ),
              ),
            );
            await tester.pumpAndSettle();
            expect(find.text(label), findsOneWidget);
            expect(
              find.byType(PelinesLocationContext),
              screen is PromotionsScreen ? findsOneWidget : findsNothing,
            );
            expect(tester.takeException(), isNull);
          }
        });
      }
    }
  }

  for (final bool requested in <bool>[false, true]) {
    test(
      'repository sends one exact active-only PATCH for $requested',
      () async {
        int patchCalls = 0;
        Object? body;
        final Dio dio = Dio(BaseOptions(baseUrl: 'https://example.test/v1/'));
        dio.interceptors.add(
          InterceptorsWrapper(
            onRequest: (RequestOptions options, handler) {
              patchCalls++;
              body = options.data;
              handler.resolve(
                Response<dynamic>(requestOptions: options, data: _json()),
              );
            },
          ),
        );
        final ApiPromotionsRepository repository = ApiPromotionsRepository(
          ApiClient(dio: dio),
        );
        await repository.setActive('discount-id', requested);
        expect(patchCalls, 1);
        expect(body, <String, dynamic>{'isActive': requested});
      },
    );
  }

  test('malformed canonical list is rejected', () async {
    final Dio dio = Dio(BaseOptions(baseUrl: 'https://example.test/v1/'));
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (RequestOptions options, handler) => handler.resolve(
          Response<dynamic>(requestOptions: options, data: <dynamic>[42]),
        ),
      ),
    );
    await expectLater(
      ApiPromotionsRepository(ApiClient(dio: dio)).getDiscounts(),
      throwsA(isA<ApiException>()),
    );
  });

  testWidgets('filters another location and separates local/global', (
    WidgetTester tester,
  ) async {
    final _FakePromotionsRepository repository = _FakePromotionsRepository(
      <Discount>[
        _discount(id: 'local', code: 'LOCAL', locationId: 'location-a'),
        _discount(id: 'global', code: 'GLOBAL'),
        _discount(id: 'other', code: 'OTHER', locationId: 'location-b'),
      ],
    );
    final ProviderContainer container = await _readyContainer(repository);
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: PromotionsScreen()),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('This location'), findsNWidgets(2));
    expect(find.text('All locations'), findsNWidgets(2));
    expect(find.text('LOCAL'), findsOneWidget);
    expect(find.text('GLOBAL'), findsOneWidget);
    expect(find.text('OTHER'), findsNothing);
  });

  testWidgets('global detail is read-only and uses required explanation', (
    WidgetTester tester,
  ) async {
    final ProviderContainer container = await _readyContainer(
      _FakePromotionsRepository(<Discount>[
        _discount(id: 'global', code: 'GLOBAL'),
      ]),
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          home: PromotionDetailScreen(discountId: 'global'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Usage claimed'), 400);
    expect(find.text('Usage claimed'), findsOneWidget);
    expect(find.textContaining('created but not completed'), findsOneWidget);
    expect(
      find.textContaining('can only be managed from the desktop'),
      findsOneWidget,
    );
    expect(find.byKey(const Key('promotion-active-action')), findsNothing);
  });

  testWidgets('cancelled activation confirmation makes no PATCH', (
    WidgetTester tester,
  ) async {
    final _FakePromotionsRepository repository = _FakePromotionsRepository(
      <Discount>[
        _discount(id: 'local', code: 'SUMMER10', locationId: 'location-a'),
      ],
    );
    final ProviderContainer container = await _readyContainer(repository);
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          home: PromotionDetailScreen(discountId: 'local'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(const Key('promotion-active-action')),
      400,
    );
    await tester.ensureVisible(
      find.byKey(const Key('promotion-active-action')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('promotion-active-action')));
    await tester.pumpAndSettle();
    expect(find.text('Deactivate SUMMER10?'), findsOneWidget);
    await tester.tap(find.byKey(const Key('promotion-confirm-cancel')));
    await tester.pumpAndSettle();
    expect(repository.patchCalls, 0);
  });

  test('preflight conflict and scope change never PATCH', () async {
    for (final Discount canonical in <Discount>[
      _discount(locationId: 'location-a', updatedAt: DateTime.utc(2026, 9, 6)),
      _discount(locationId: null),
      _discount(locationId: 'location-b'),
    ]) {
      final _FakePromotionsRepository repository = _FakePromotionsRepository(
        <Discount>[canonical],
      );
      final ProviderContainer container = _container(repository);
      addTearDown(container.dispose);
      await container.read(currentLocationProvider.future);
      await container.read(promotionsProvider.future);
      await container
          .read(promotionMutationProvider.notifier)
          .setActive(
            discountId: canonical.id,
            locationId: 'location-a',
            originalUpdatedAt: DateTime.utc(2026, 9, 5),
            isActive: false,
          );
      expect(repository.patchCalls, 0);
      expect(
        container.read(promotionMutationProvider).phase,
        canonical.locationId == 'location-a'
            ? PromotionMutationPhase.conflict
            : PromotionMutationPhase.error,
      );
    }
  });

  test('current location change blocks mutation before preflight', () async {
    final _FakePromotionsRepository repository = _FakePromotionsRepository(
      <Discount>[_discount(locationId: 'location-a')],
    );
    final ProviderContainer container = _container(
      repository,
      location: _location(id: 'location-b'),
    );
    addTearDown(container.dispose);
    await container.read(currentLocationProvider.future);
    await container
        .read(promotionMutationProvider.notifier)
        .setActive(
          discountId: 'discount-id',
          locationId: 'location-a',
          originalUpdatedAt: DateTime.utc(2026, 9, 5),
          isActive: false,
        );
    expect(repository.getCalls, 0);
    expect(repository.patchCalls, 0);
  });

  test(
    'successful change uses preflight, one PATCH, then reconciliation',
    () async {
      final Discount before = _discount(locationId: 'location-a');
      final Discount after = _discount(
        locationId: 'location-a',
        isActive: false,
        updatedAt: DateTime.utc(2026, 9, 6),
      );
      final _FakePromotionsRepository repository = _FakePromotionsRepository(
        <Discount>[before],
        afterPatch: <Discount>[after],
      );
      final ProviderContainer container = _container(repository);
      addTearDown(container.dispose);
      await container.read(currentLocationProvider.future);
      await container.read(promotionsProvider.future);
      await container
          .read(promotionMutationProvider.notifier)
          .setActive(
            discountId: before.id,
            locationId: 'location-a',
            originalUpdatedAt: before.updatedAt,
            isActive: false,
          );
      expect(
        repository.getCalls,
        3,
      ); // initial provider + preflight + reconcile
      expect(repository.patchCalls, 1);
      expect(
        container.read(promotionMutationProvider).phase,
        PromotionMutationPhase.success,
      );
      expect(container.read(promotionsProvider).value!.single.isActive, false);
    },
  );

  for (final ({String name, List<Discount> result, bool success}) scenario
      in <({String name, List<Discount> result, bool success})>[
        (
          name: 'applied',
          result: <Discount>[
            _discount(locationId: 'location-a', isActive: false),
          ],
          success: true,
        ),
        (
          name: 'not applied',
          result: <Discount>[_discount(locationId: 'location-a')],
          success: false,
        ),
        (name: 'missing', result: <Discount>[], success: false),
      ]) {
    test(
      'timeout ${scenario.name} reconciles without a second PATCH',
      () async {
        final Discount before = _discount(locationId: 'location-a');
        final _FakePromotionsRepository repository = _FakePromotionsRepository(
          <Discount>[before],
          afterPatch: scenario.result,
          patchError: _timeout(),
        );
        final ProviderContainer container = _container(repository);
        addTearDown(container.dispose);
        await container.read(currentLocationProvider.future);
        await container.read(promotionsProvider.future);
        await container
            .read(promotionMutationProvider.notifier)
            .setActive(
              discountId: before.id,
              locationId: 'location-a',
              originalUpdatedAt: before.updatedAt,
              isActive: false,
            );
        expect(repository.patchCalls, 1);
        expect(
          container.read(promotionMutationProvider).phase,
          scenario.success
              ? PromotionMutationPhase.success
              : PromotionMutationPhase.error,
        );
      },
    );
  }
}

ProviderContainer _container(
  _FakePromotionsRepository repository, {
  Location? location,
}) => ProviderContainer(
  overrides: [
    promotionsRepositoryProvider.overrideWithValue(repository),
    currentLocationProvider.overrideWith(
      () => _FixedLocationController(location ?? _location()),
    ),
  ],
);

Future<ProviderContainer> _readyContainer(
  _FakePromotionsRepository repository,
) async {
  final ProviderContainer container = _container(repository);
  await container.read(currentLocationProvider.future);
  await container.read(promotionsProvider.future);
  return container;
}

class _FixedLocationController extends CurrentLocationController {
  _FixedLocationController(this.location);
  final Location location;
  @override
  Future<Location?> build() async => location;
}

class _FakePromotionsRepository implements PromotionsRepository {
  _FakePromotionsRepository(this.current, {this.afterPatch, this.patchError});
  List<Discount> current;
  final List<Discount>? afterPatch;
  final Object? patchError;
  int getCalls = 0;
  int patchCalls = 0;

  @override
  Future<Discount> createPromotion(Map<String, dynamic> body) =>
      throw UnimplementedError();

  @override
  Future<Discount> updatePromotion(String id, Map<String, dynamic> patch) =>
      setActive(id, patch['isActive'] as bool);

  @override
  Future<List<Discount>> getDiscounts() async {
    getCalls++;
    return List<Discount>.of(current);
  }

  @override
  Future<Discount> setActive(String id, bool isActive) async {
    patchCalls++;
    if (afterPatch != null) current = List<Discount>.of(afterPatch!);
    if (patchError != null) throw patchError!;
    return current.singleWhere((Discount value) => value.id == id);
  }
}

Location _location({String id = 'location-a'}) => Location(
  id: id,
  name: 'Tualatin',
  slug: 'tualatin',
  isActive: true,
  deliveryFeeCents: 0,
  deliveryMinimumCents: 0,
  isAcceptingOrders: true,
  createdAt: DateTime.utc(2026),
  updatedAt: DateTime.utc(2026),
);

Discount _discount({
  String id = 'discount-id',
  String code = 'SAVE10',
  String type = 'percent',
  int value = 10,
  int minSubtotalCents = 0,
  DateTime? startsAt,
  DateTime? endsAt,
  int? usageLimit,
  int timesRedeemed = 0,
  String? locationId,
  bool isActive = true,
  DateTime? updatedAt,
}) => Discount(
  id: id,
  code: code,
  type: type,
  value: value,
  minSubtotalCents: minSubtotalCents,
  startsAt: startsAt,
  endsAt: endsAt,
  usageLimit: usageLimit,
  timesRedeemed: timesRedeemed,
  locationId: locationId,
  appliesTo: 'regular',
  isActive: isActive,
  createdAt: DateTime.utc(2026),
  updatedAt: updatedAt ?? DateTime.utc(2026, 9, 5),
);

Map<String, dynamic> _json() => <String, dynamic>{
  'id': 'discount-id',
  'code': 'SAVE10',
  'type': 'percent',
  'value': 10,
  'minSubtotalCents': 0,
  'startsAt': null,
  'endsAt': null,
  'usageLimit': null,
  'timesRedeemed': 0,
  'locationId': 'location-a',
  'appliesTo': 'regular',
  'isActive': true,
  'createdAt': '2026-01-01T00:00:00.000Z',
  'updatedAt': '2026-09-05T00:00:00.000Z',
};

ApiException _timeout() => ApiException(
  message: 'The Pelines server timed out.',
  cause: DioException(
    requestOptions: RequestOptions(path: 'discounts/discount-id'),
    type: DioExceptionType.receiveTimeout,
  ),
);
