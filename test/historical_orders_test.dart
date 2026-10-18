import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pelines_admin_app/features/orders/models/orders_date_filter.dart';

import 'dart:async';

import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart';
import 'package:pelines_admin_app/app/l10n/admin_localizations.dart';
import 'package:pelines_admin_app/app/theme/app_theme.dart';
import 'package:pelines_admin_app/app/theme/pelines_components.dart';
import 'package:pelines_admin_app/app/theme/pelines_tokens.dart';
import 'package:pelines_admin_app/core/time/pelines_time.dart';
import 'package:pelines_admin_app/features/orders/presentation/historical_date_range.dart';
import 'package:pelines_admin_app/features/locations/presentation/pelines_location_context.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:pelines_admin_app/features/locations/models/location.dart';
import 'package:pelines_admin_app/features/locations/providers/locations_providers.dart';
import 'package:pelines_admin_app/features/orders/data/orders_repository.dart';
import 'package:pelines_admin_app/features/orders/models/order_models.dart';
import 'package:pelines_admin_app/features/orders/presentation/historical_orders_screen.dart';
import 'package:pelines_admin_app/features/orders/presentation/order_ui_helpers.dart';
import 'package:pelines_admin_app/features/orders/providers/orders_providers.dart';

void main() {
  setUpAll(() async {
    PelinesTime.initialize();
    final font = FontLoader(PelinesTypography.bodyFamily)
      ..addFont(
        rootBundle.load(
          'assets/fonts/work_sans/WorkSans-VariableFont_wght.ttf',
        ),
      );
    await font.load();
  });
  block5Tests();
  test('payment labels preserve every backend status', () {
    expect(paymentStatusLabel(PaymentStatus.unpaid), 'Unpaid');
    expect(paymentStatusLabel(PaymentStatus.paid), 'Paid');
    expect(paymentStatusLabel(PaymentStatus.refunded), 'Refunded');
    expect(paymentStatusLabel(PaymentStatus.failed), 'Failed');
  });

  test('completed and cancelled sorting uses real timestamps', () {
    final OrderSummary deliveredNewest = _order(
      'delivered-new',
      status: OrderStatus.delivered,
      createdAt: '2026-09-01T10:00:00Z',
      deliveredAt: '2026-09-04T12:00:00Z',
    );
    final OrderSummary deliveredOlder = _order(
      'delivered-old',
      status: OrderStatus.delivered,
      createdAt: '2026-09-03T10:00:00Z',
      deliveredAt: '2026-09-04T11:00:00Z',
    );
    expect(
      compareCompletedOrders(deliveredNewest, deliveredOlder),
      lessThan(0),
    );

    final OrderSummary cancelledScheduled = _order(
      'cancelled-scheduled',
      status: OrderStatus.cancelled,
      createdAt: '2026-09-01T10:00:00Z',
      scheduledFor: '2026-09-05T10:00:00Z',
    );
    final OrderSummary cancelledCreated = _order(
      'cancelled-created',
      status: OrderStatus.cancelled,
      createdAt: '2026-09-04T10:00:00Z',
    );
    expect(
      compareCancelledOrders(cancelledScheduled, cancelledCreated),
      lessThan(0),
    );
  });

  for (final _ProviderCase testCase in <_ProviderCase>[
    _ProviderCase(OrderStatus.delivered, true),
    _ProviderCase(OrderStatus.cancelled, false),
  ]) {
    test(
      '${testCase.status.name} provider follows location without mixing',
      () async {
        final _HistoryRepository repository = _HistoryRepository();
        final ProviderContainer container = ProviderContainer(
          overrides: [
            currentLocationProvider.overrideWith(_FakeCurrentLocation.new),
            ordersRepositoryProvider.overrideWithValue(repository),
          ],
        );
        addTearDown(container.dispose);
        final provider = testCase.completed
            ? completedOrdersProvider
            : cancelledOrdersProvider;
        final subscription = container.listen(provider, (_, _) {});
        addTearDown(subscription.close);

        expect(
          (await container.read(provider.future)).orders.single.locationId,
          'A',
        );
        (container.read(
          currentLocationProvider.notifier,
        ) as _FakeCurrentLocation).change(_location('B'));
        await Future<void>.delayed(Duration.zero);
        final HistoricalOrdersState second = await container.read(
          provider.future,
        );

        expect(second.orders.map((o) => o.locationId), <String>['B']);
        expect(repository.calls, <(String, OrderStatus?)>[
          ('A', testCase.status),
          ('B', testCase.status),
        ]);
      },
    );

    test('${testCase.status.name} provider supports empty and error', () async {
      final _HistoryRepository repository = _HistoryRepository(
        custom: <OrderSummary>[],
      );
      final ProviderContainer container = ProviderContainer(
        overrides: [
          currentLocationProvider.overrideWith(_FakeCurrentLocation.new),
          ordersRepositoryProvider.overrideWithValue(repository),
        ],
      );
      addTearDown(container.dispose);
      final provider = testCase.completed
          ? completedOrdersProvider
          : cancelledOrdersProvider;
      expect((await container.read(provider.future)).orders, isEmpty);
      repository.fail = true;
      await container.read(provider.notifier).refresh();
      expect(container.read(provider).value?.refreshError, isNotNull);
    });
  }

  test('no location makes no history request', () async {
    final _HistoryRepository repository = _HistoryRepository();
    final ProviderContainer container = ProviderContainer(
      overrides: [
        currentLocationProvider.overrideWith(_NoCurrentLocation.new),
        ordersRepositoryProvider.overrideWithValue(repository),
      ],
    );
    addTearDown(container.dispose);
    expect(
      (await container.read(completedOrdersProvider.future)).orders,
      isEmpty,
    );
    expect(repository.calls, isEmpty);
  });

  test('refresh error preserves completed data and retry succeeds', () async {
    final _HistoryRepository repository = _HistoryRepository();
    final ProviderContainer container = ProviderContainer(
      overrides: [
        currentLocationProvider.overrideWith(_FakeCurrentLocation.new),
        ordersRepositoryProvider.overrideWithValue(repository),
      ],
    );
    addTearDown(container.dispose);
    await container.read(completedOrdersProvider.future);
    repository.fail = true;
    await container.read(completedOrdersProvider.notifier).refresh();
    expect(container.read(completedOrdersProvider).value?.orders, isNotEmpty);
    expect(
      container.read(completedOrdersProvider).value?.refreshError,
      isNotNull,
    );
    repository.fail = false;
    await container.read(completedOrdersProvider.notifier).refresh();
    expect(container.read(completedOrdersProvider).value?.refreshError, isNull);
  });

  testWidgets('completed presentation and tap route use the real UUID', (
    tester,
  ) async {
    final _HistoryRepository repository = _HistoryRepository(
      custom: <OrderSummary>[
        _order(
          'completed-card',
          id: 'completed-uuid',
          status: OrderStatus.delivered,
          fulfillment: FulfillmentType.pickup,
          payment: PaymentStatus.refunded,
          deliveredAt: '2026-09-04T12:00:00Z',
        ),
      ],
    );
    final GoRouter router = _router(HistoricalOrdersKind.completed);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          currentLocationProvider.overrideWith(_FakeCurrentLocation.new),
          ordersRepositoryProvider.overrideWithValue(repository),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(PelinesLocationContext), findsOneWidget);
    final description = find.textContaining('Filtered by completion date');
    expect(description, findsOneWidget);
    expect(
      tester.getRect(description).top,
      greaterThanOrEqualTo(
        tester.getRect(find.byType(PelinesLocationContext)).bottom,
      ),
    );
    expect(
      tester.getRect(find.byKey(const Key('history-date-range'))).top,
      greaterThanOrEqualTo(tester.getRect(description).bottom),
    );

    expect(find.text('Picked up'), findsOneWidget);
    expect(find.text('Refunded'), findsOneWidget);
    await tester.tap(find.text('completed-card'));
    await tester.pumpAndSettle();
    expect(find.text('detail completed-uuid'), findsOneWidget);
    router.pop();
    await tester.pumpAndSettle();
    expect(find.text('Completed Orders'), findsOneWidget);
  });

  testWidgets('cancelled can remain paid and has no status actions', (
    tester,
  ) async {
    final _HistoryRepository repository = _HistoryRepository(
      custom: <OrderSummary>[
        _order(
          'cancelled-card',
          status: OrderStatus.cancelled,
          fulfillment: FulfillmentType.delivery,
          payment: PaymentStatus.paid,
        ),
      ],
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          currentLocationProvider.overrideWith(_FakeCurrentLocation.new),
          ordersRepositoryProvider.overrideWithValue(repository),
        ],
        child: MaterialApp.router(
          routerConfig: _router(HistoricalOrdersKind.cancelled),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(PelinesLocationContext), findsOneWidget);
    expect(find.text('Cancelled'), findsOneWidget);
    expect(find.text('Paid'), findsOneWidget);
    expect(find.textContaining('Cancelled at'), findsNothing);
    expect(find.byKey(const Key('order-primary-action')), findsNothing);
    expect(find.byKey(const Key('cancel-order-action')), findsNothing);
    expect(find.byIcon(Icons.chevron_right), findsOneWidget);
  });
}

GoRouter _router(HistoricalOrdersKind kind) => GoRouter(
  initialLocation: kind == HistoricalOrdersKind.completed
      ? '/app/orders/completed'
      : '/app/orders/cancelled',
  routes: <RouteBase>[
    GoRoute(
      path: '/app/orders/completed',
      builder: (_, _) =>
          const HistoricalOrdersScreen(kind: HistoricalOrdersKind.completed),
    ),
    GoRoute(
      path: '/app/orders/cancelled',
      builder: (_, _) =>
          const HistoricalOrdersScreen(kind: HistoricalOrdersKind.cancelled),
    ),
    GoRoute(
      path: '/app/orders/:id',
      builder: (_, GoRouterState state) =>
          Scaffold(body: Text('detail ${state.pathParameters['id']}')),
    ),
  ],
);

class _ProviderCase {
  const _ProviderCase(this.status, this.completed);
  final OrderStatus status;
  final bool completed;
}

OrderSummary _order(
  String number, {
  String? id,
  required OrderStatus status,
  String createdAt = '2026-09-04T10:00:00Z',
  String? scheduledFor,
  String? deliveredAt,
  String locationId = 'A',
  FulfillmentType fulfillment = FulfillmentType.pickup,
  PaymentStatus payment = PaymentStatus.paid,
  OrderType type = OrderType.online,
}) => OrderSummary(
  id: id ?? '$number-id',
  orderNumber: number,
  locationId: locationId,
  orderType: type,
  status: status,
  rawStatus: status.name,
  paymentStatus: payment,
  fulfillmentType: fulfillment,
  contactName: 'Customer',
  createdAt: DateTime.parse(createdAt),
  scheduledFor: scheduledFor == null ? null : DateTime.parse(scheduledFor),
  deliveredAt: deliveredAt == null ? null : DateTime.parse(deliveredAt),
  itemCount: 2,
  totalCents: 1100,
);

Location _location(String id) => Location(
  id: id,
  name: 'Location $id',
  slug: id,
  isActive: true,
  deliveryFeeCents: 0,
  deliveryMinimumCents: 0,
  isAcceptingOrders: true,
  createdAt: DateTime.utc(2026),
  updatedAt: DateTime.utc(2026),
);

class _FakeCurrentLocation extends CurrentLocationController {
  @override
  Future<Location?> build() async => _location('A');
  void change(Location location) => state = AsyncData<Location?>(location);
}

class _NoCurrentLocation extends CurrentLocationController {
  @override
  Future<Location?> build() async => null;
}

class _HistoryRepository implements OrdersRepository {
  _HistoryRepository({this.custom});
  List<OrderSummary>? custom;
  Completer<List<OrderSummary>>? pending;
  final List<(String, OrderStatus?)> calls = <(String, OrderStatus?)>[];
  bool fail = false;

  @override
  Future<List<OrderSummary>> getOrders({
    required String locationId,
    OrderStatus? status,
  }) async {
    calls.add((locationId, status));
    if (fail) throw Exception('offline');
    if (pending != null) return pending!.future;
    return custom ??
        <OrderSummary>[
          _order(
            '$locationId-${status!.name}',
            status: status,
            locationId: locationId,
          ),
        ];
  }

  @override
  Future<OrderDetail> getOrderById(String id) => throw UnimplementedError();
  @override
  Future<OrderDetail> updateInternalNotes({
    required String orderId,
    required String internalNotes,
  }) => throw UnimplementedError();
  @override
  Future<OrderDetail> updateOrderStatus({
    required String orderId,
    required OrderStatus status,
  }) => throw UnimplementedError();
}

List<OrderSummary> _loadedRows(
  int count,
  HistoricalOrdersKind kind, {
  String location = 'A',
}) => [
  for (var i = 0; i < count; i++)
    _order(
      '$location-row$i',
      status: kind == HistoricalOrdersKind.completed
          ? OrderStatus.delivered
          : OrderStatus.cancelled,
      locationId: location,
      createdAt: DateTime.utc(2026, 11, i + 1, 20).toIso8601String(),
      deliveredAt: kind == HistoricalOrdersKind.completed && i > 0
          ? DateTime.utc(2026, 11, i + 1, 21).toIso8601String()
          : null,
      fulfillment: i.isEven ? FulfillmentType.pickup : FulfillmentType.delivery,
      type: i.isEven ? OrderType.online : OrderType.catering,
      payment: i.isEven ? PaymentStatus.paid : PaymentStatus.refunded,
    ),
];

Future<ProviderContainer> _mountHistory(
  WidgetTester tester,
  _HistoryRepository repo,
  HistoricalOrdersKind kind, {
  double width = 390,
  double scale = 1,
  String language = 'en',
  bool settle = true,
}) async {
  tester.view.physicalSize = Size(width, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final container = ProviderContainer(
    overrides: [
      currentLocationProvider.overrideWith(_FakeCurrentLocation.new),
      ordersRepositoryProvider.overrideWithValue(repo),
    ],
  );
  addTearDown(container.dispose);
  final router = _router(kind);
  addTearDown(router.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(
        theme: AppTheme.light,
        routerConfig: router,
        locale: Locale(language),
        supportedLocales: AdminLocalizations.supportedLocales,
        localizationsDelegates: const [
          AdminLocalizations.delegate,
          ...GlobalMaterialLocalizations.delegates,
        ],
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
      ),
    ),
  );
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    await tester.pump();
  }
  if (settle &&
      find.byKey(const Key('history-loaded-count')).evaluate().isNotEmpty) {
    await _historyReveal(
      tester,
      find.byKey(const Key('history-showing-count')),
    );
  }
  return container;
}

Future<void> _historyReveal(WidgetTester tester, Finder target) async {
  if (target.evaluate().isEmpty) {
    final scrollable = find
        .descendant(
          of: find.byType(CustomScrollView).first,
          matching: find.byType(Scrollable),
        )
        .first;
    tester.state<ScrollableState>(scrollable).position.jumpTo(0);
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      target,
      300,
      scrollable: find
          .descendant(
            of: find.byType(CustomScrollView).first,
            matching: find.byType(Scrollable),
          )
          .first,
    );
  } else {
    await tester.ensureVisible(target);
  }
  await tester.pumpAndSettle();
}

Future<void> _historyTap(WidgetTester tester, String key) async {
  final target = find.byKey(Key(key));
  await _historyReveal(tester, target);
  await tester.tap(target);
  await tester.pumpAndSettle();
  if (find.byType(CustomScrollView).evaluate().isNotEmpty &&
      find.byKey(const Key('history-range-sheet')).evaluate().isEmpty &&
      find.byType(DatePickerDialog).evaluate().isEmpty) {
    await _historyReveal(
      tester,
      find.byKey(const Key('history-showing-count')),
    );
  }
}

Future<void> _historyPick(
  WidgetTester tester,
  String bound,
  DateTime date,
) async {
  if (find.byKey(Key('history-$bound')).evaluate().isEmpty) {
    await _historyTap(tester, 'history-preset-Custom range');
  }
  await _historyTap(tester, 'history-$bound');
  await tester.tap(find.byIcon(Icons.edit_outlined));
  await tester.pumpAndSettle();
  await tester.enterText(
    find.byType(TextField).last,
    DateFormat.yMd('en').format(date),
  );
  await tester.tap(find.text('OK'));
  await tester.pumpAndSettle();
}

void block5Tests() {
  test(
    'historical presets use inclusive Pacific days around midnight and DST',
    () {
      for (final instant in [
        DateTime.parse('2026-03-09T06:59:59Z'),
        DateTime.parse('2026-11-02T07:59:59Z'),
        DateTime.parse('2026-10-18T01:00:00Z'),
      ]) {
        final today = pacificDate(instant);
        for (final days in [1, 7, 30, 90]) {
          final range = historicalPresetRange(days, now: instant);
          expect(range.$2, today);
          expect(
            range.$1,
            DateTime.utc(today.year, today.month, today.day - days + 1),
          );
          expect(range.$2.difference(range.$1).inDays + 1, days);
        }
      }
    },
  );

  for (final language in ['en', 'es']) {
    for (final size in [
      const Size(320, 480),
      const Size(768, 1000),
      const Size(1400, 900),
    ]) {
      testWidgets(
        'history bottom sheet presets/draft/reset $language/$size at 2x',
        (tester) async {
          tester.view.devicePixelRatio = 1;
          tester.view.physicalSize = size;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          (DateTime?, DateTime?)? applied;
          await tester.pumpWidget(
            MaterialApp(
              theme: AppTheme.light,
              locale: Locale(language),
              supportedLocales: const [Locale('en'), Locale('es')],
              localizationsDelegates: const [
                AdminLocalizations.delegate,
                GlobalMaterialLocalizations.delegate,
                GlobalWidgetsLocalizations.delegate,
                GlobalCupertinoLocalizations.delegate,
              ],
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context)
                    .copyWith(textScaler: const TextScaler.linear(2)),
                child: child!,
              ),
              home: Builder(
                builder: (context) => Scaffold(
                  body: Center(
                    child: TextButton(
                      onPressed: () async {
                        final result = await showHistoricalDateRange(
                          context,
                          applied?.$1,
                          applied?.$2,
                        );
                        if (result != null) applied = result;
                      },
                      child: const Text('Open range'),
                    ),
                  ),
                ),
              ),
            ),
          );
          for (final days in [1, 7, 30, 90]) {
            await tester.tap(find.text('Open range'));
            await tester.pumpAndSettle();
            expect(
              find.byKey(const Key('history-range-sheet')),
              findsOneWidget,
            );
            expect(find.byType(AlertDialog), findsNothing);
            final sheet = tester.widget<BottomSheet>(find.byType(BottomSheet));
            expect(sheet.backgroundColor, PelinesColors.card);
            expect(
              (sheet.shape! as RoundedRectangleBorder).borderRadius,
              const BorderRadius.vertical(top: Radius.circular(32)),
            );
            await _historyTap(
              tester,
              'history-preset-${days == 1 ? 'Today' : 'Last $days days'}',
            );
            await _historyTap(tester, 'history-range-apply');
            expect(applied, historicalPresetRange(days));
            expect(tester.takeException(), isNull);
          }
          final before = applied;
          await tester.tap(find.text('Open range'));
          await tester.pumpAndSettle();
          await _historyTap(tester, 'history-range-reset');
          await _historyTap(tester, 'history-range-cancel');
          expect(applied, before);
          await tester.tap(find.text('Open range'));
          await tester.pumpAndSettle();
          await _historyTap(tester, 'history-preset-Custom range');
          expect(find.byKey(const Key('history-from')), findsOneWidget);
          expect(find.byKey(const Key('history-to')), findsOneWidget);
          await _historyTap(tester, 'history-range-reset');
          await _historyTap(tester, 'history-range-apply');
          expect(applied, (null, null));
          expect(tester.takeException(), isNull);
        },
      );
    }
  }

  for (final kind in HistoricalOrdersKind.values) {
    testWidgets(
      '${kind.name}: local 5/+5/partial, filters, refresh and location reset',
      (tester) async {
        final repo = _HistoryRepository(
          custom: [
            ..._loadedRows(17, kind),
            ..._loadedRows(17, kind, location: 'B'),
          ],
        );
        final container = await _mountHistory(tester, repo, kind);
        for (final label in [
          'All loaded',
          'All types',
          'All fulfillment',
          'All payments',
        ]) {
          expect(find.text(label), findsNothing);
        }
        expect(find.byType(PopupMenuButton<PaymentStatus?>), findsNothing);
        expect(find.text('Showing 5 of 17 loaded orders'), findsOneWidget);
        expect(find.byKey(const Key('history-shared-surface')), findsOneWidget);
        final dividers = find.descendant(
          of: find.byKey(const Key('history-shared-surface')),
          matching: find.byType(Divider),
        );
        expect(dividers, findsNWidgets(4));
        for (final count in [10, 15, 17]) {
          await _historyTap(tester, 'history-load-more');
          expect(
            find.text('Showing $count of 17 loaded orders'),
            findsOneWidget,
          );
        }
        expect(find.byKey(const Key('history-load-more')), findsNothing);
        expect(repo.calls.length, 1);
        final provider = kind == HistoricalOrdersKind.completed
            ? completedOrdersProvider
            : cancelledOrdersProvider;
        await container.read(provider.notifier).refresh();
        await tester.pumpAndSettle();
        await _historyReveal(
          tester,
          find.byKey(const Key('history-showing-count')),
        );
        expect(find.text('Showing 5 of 17 loaded orders'), findsOneWidget);
        (container.read(
          currentLocationProvider.notifier,
        ) as _FakeCurrentLocation).change(_location('B'));
        await tester.pumpAndSettle();
        await _historyReveal(
          tester,
          find.byKey(const Key('history-showing-count')),
        );
        expect(find.text('Showing 5 of 17 loaded orders'), findsOneWidget);
        expect(
          find.byKey(const ValueKey('history-row-A-row16-id')),
          findsNothing,
        );
        expect(
          find.byKey(const ValueKey('history-row-B-row16-id')),
          findsOneWidget,
        );
        expect(repo.calls.last, (
          'B',
          kind == HistoricalOrdersKind.completed
              ? OrderStatus.delivered
              : OrderStatus.cancelled,
        ));
        repo.custom = _loadedRows(3, kind, location: 'B');
        await container.read(provider.notifier).refresh();
        await tester.pumpAndSettle();
        await _historyReveal(
          tester,
          find.byKey(const Key('history-showing-count')),
        );
        expect(find.text('Showing 3 of 3 loaded orders'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('history range validates, applies locally, discards and resets', (
    tester,
  ) async {
    final repo = _HistoryRepository(
      custom: _loadedRows(17, HistoricalOrdersKind.completed),
    );
    await _mountHistory(tester, repo, HistoricalOrdersKind.completed);
    await _historyTap(tester, 'history-load-more');
    await _historyTap(tester, 'history-date-range');
    await _historyPick(tester, 'from', DateTime(2026, 11, 5));
    await _historyPick(tester, 'to', DateTime(2026, 11, 2));
    await _historyTap(tester, 'history-range-apply');
    expect(find.text('From must be on or before To.'), findsOneWidget);
    await _historyPick(tester, 'to', DateTime(2026, 11, 7));
    await _historyTap(tester, 'history-range-apply');
    expect(find.text('Showing 3 of 3 loaded orders'), findsOneWidget);
    await _historyReveal(tester, find.byKey(const Key('history-loaded-count')));
    expect(find.text('Loaded orders: 3'), findsOneWidget);
    await _historyTap(tester, 'history-date-range');
    await _historyTap(tester, 'history-range-reset');
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.text('Showing 3 of 3 loaded orders'), findsOneWidget);
    await _historyTap(tester, 'history-date-range');
    await _historyTap(tester, 'history-range-reset');
    await _historyTap(tester, 'history-range-apply');
    expect(find.text('Showing 5 of 17 loaded orders'), findsOneWidget);
    expect(repo.calls.length, 1);
    expect(tester.takeException(), isNull);
  });

  test('range uses inclusive Pacific days across both DST changes and real timestamps', () {
    for (final bounds in [
      (
        '2026-03-08T08:00:00Z',
        '2026-03-09T06:59:59Z',
        DateTime.utc(2026, 3, 8),
      ),
      (
        '2026-11-01T07:00:00Z',
        '2026-11-02T07:59:59Z',
        DateTime.utc(2026, 11, 1),
      ),
    ]) {
      final rows = [
        _order(
          'before',
          status: OrderStatus.delivered,
          deliveredAt: DateTime.parse(bounds.$1)
              .subtract(const Duration(seconds: 1))
              .toIso8601String(),
        ),
        _order('start', status: OrderStatus.delivered, deliveredAt: bounds.$1),
        _order('end', status: OrderStatus.delivered, createdAt: bounds.$2),
        _order(
          'after',
          status: OrderStatus.delivered,
          deliveredAt: DateTime.parse(bounds.$2)
              .add(const Duration(seconds: 1))
              .toIso8601String(),
        ),
      ];
      expect(
        filterHistoricalDateRange(
          rows,
          completed: true,
          from: bounds.$3,
          to: bounds.$3,
        ).map((o) => o.orderNumber),
        ['start', 'end'],
      );
      final cancelled = _order(
        'cancelled',
        status: OrderStatus.cancelled,
        createdAt: bounds.$1,
        deliveredAt: '2030-01-01T00:00:00Z',
      );
      expect(
        filterHistoricalDateRange(
          [cancelled],
          completed: false,
          from: bounds.$3,
          to: bounds.$3,
        ),
        [cancelled],
      );
    }
  });

  for (final kind in HistoricalOrdersKind.values) {
    for (final language in ['en', 'es']) {
      for (final size in [
        (320.0, 2.0),
        (390.0, 1.0),
        (768.0, 2.0),
        (1400.0, 1.0),
      ]) {
        testWidgets(
          '${kind.name} compact/table layout ${size.$1}/${size.$2}/$language',
          (tester) async {
            final repo = _HistoryRepository(custom: _loadedRows(5, kind));
            await _mountHistory(
              tester,
              repo,
              kind,
              width: size.$1,
              scale: size.$2,
              language: language,
            );
            await _historyReveal(
              tester,
              find.byKey(const Key('history-loaded-count')),
            );
            expect(
              find.text(
                language == 'es' ? 'Pedidos completados' : 'Completed orders',
              ),
              language == 'es' && kind == HistoricalOrdersKind.completed
                  ? findsOneWidget
                  : findsNothing,
            );
            expect(
              find.text(
                language == 'es' ? 'Pedidos cancelados' : 'Cancelled orders',
              ),
              language == 'es' && kind == HistoricalOrdersKind.cancelled
                  ? findsOneWidget
                  : findsNothing,
            );
            expect(
              find.text(
                language == 'es' ? 'Pedidos cargados: 5' : 'Loaded orders: 5',
              ),
              findsOneWidget,
            );
            final countRect = tester.getRect(
              find.byKey(const Key('history-loaded-count')),
            );
            final dateRect = tester.getRect(
              find.byKey(const Key('history-date-range')),
            );
            if (size.$2 == 1) {
              expect(
                countRect.center.dy,
                closeTo(dateRect.center.dy, 1),
                reason: 'badge $countRect, button $dateRect',
              );
              expect(countRect.right, lessThan(dateRect.left));
            }
            expect(tester.takeException(), isNull);
            await _historyReveal(
              tester,
              find.byKey(const Key('history-showing-count')),
            );
            final table = size.$1 - 32 >= 840 * size.$2;
            expect(
              find.byType(DataTable),
              table ? findsOneWidget : findsNothing,
            );
            expect(
              find.byKey(const Key('history-shared-surface')),
              table ? findsNothing : findsOneWidget,
            );
            expect(
              find.byIcon(
                kind == HistoricalOrdersKind.completed
                    ? Icons.check_circle_outline
                    : Icons.cancel_outlined,
              ),
              findsNWidgets(5),
            );
            final badges = tester.widgetList<PelinesStateBadge>(
              find.byType(PelinesStateBadge),
            );
            final status = badges.where(
              (b) =>
                  b.icon ==
                  (kind == HistoricalOrdersKind.completed
                      ? Icons.check_circle_outline
                      : Icons.cancel_outlined),
            );
            expect(
              status.every(
                (b) =>
                    b.foreground ==
                    (kind == HistoricalOrdersKind.completed
                        ? PelinesColors.successForeground
                        : PelinesColors.destructive),
              ),
              isTrue,
            );
            if (kind == HistoricalOrdersKind.cancelled) {
              expect(
                find.byKey(const ValueKey('history-refund-warning-A-row4-id')),
                findsOneWidget,
              );
              expect(
                find.text(language == 'es' ? 'Reembolsado' : 'Refunded'),
                findsNWidgets(2),
              );
            }
            await _historyTap(
              tester,
              table ? 'history-view-A-row4-id' : 'history-row-A-row4-id',
            );
            expect(find.text('detail A-row4-id'), findsOneWidget);
            expect(repo.calls.length, 1);
            expect(tester.takeException(), isNull);
          },
        );
      }
    }
  }

  testWidgets(
    'history loading, error/retry and empty refer only to loaded data',
    (tester) async {
      final repo = _HistoryRepository()
        ..pending = Completer<List<OrderSummary>>();
      await _mountHistory(
        tester,
        repo,
        HistoricalOrdersKind.cancelled,
        settle: false,
      );
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      repo.pending!.complete([]);
      repo.pending = null;
      await tester.pumpAndSettle();
      expect(
        find.text('No cancelled orders loaded for this location.'),
        findsOneWidget,
      );
      await _historyReveal(
        tester,
        find.byKey(const Key('history-showing-count')),
      );
      expect(find.text('Showing 0 of 0 loaded orders'), findsOneWidget);
      expect(
        find.text(
          'History is limited to loaded orders; more may exist on the server.',
        ),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'cancelled preserves all financial states and warns only for paid',
    (tester) async {
      final repo = _HistoryRepository(
        custom: [
          for (final payment in PaymentStatus.values)
            _order(
              payment.name,
              status: OrderStatus.cancelled,
              payment: payment,
            ),
        ],
      );
      await _mountHistory(tester, repo, HistoricalOrdersKind.cancelled);
      for (final payment in PaymentStatus.values) {
        expect(find.text(paymentStatusLabel(payment)), findsOneWidget);
      }
      expect(
        find.byKey(const ValueKey('history-refund-warning-paid-id')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('history-refund-warning-refunded-id')),
        findsNothing,
      );
      expect(find.byKey(const Key('order-primary-action')), findsNothing);
      expect(find.byKey(const Key('cancel-order-action')), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'history initial error retries without claiming complete history',
    (tester) async {
      final repo = _HistoryRepository(custom: [])..fail = true;
      await _mountHistory(tester, repo, HistoricalOrdersKind.completed);
      expect(find.textContaining('offline'), findsOneWidget);
      final callsBeforeRetry = repo.calls.length;
      repo.fail = false;
      await tester.tap(find.text('Try again'));
      await tester.pumpAndSettle();
      expect(
        find.text('No completed orders loaded for this location.'),
        findsOneWidget,
      );
      expect(repo.calls.length, callsBeforeRetry + 1);
    },
  );

  testWidgets('wrong location/status never enters the historical projection', (
    tester,
  ) async {
    final repo = _HistoryRepository(
      custom: [
        ..._loadedRows(7, HistoricalOrdersKind.completed),
        ..._loadedRows(7, HistoricalOrdersKind.cancelled),
        ..._loadedRows(7, HistoricalOrdersKind.completed, location: 'B'),
      ],
    );
    await _mountHistory(tester, repo, HistoricalOrdersKind.completed);
    await _historyReveal(tester, find.byKey(const Key('history-loaded-count')));
    expect(find.text('Loaded orders: 7'), findsOneWidget);
    await _historyReveal(
      tester,
      find.byKey(const Key('history-showing-count')),
    );
    expect(find.text('Showing 5 of 7 loaded orders'), findsOneWidget);
    expect(find.byKey(const ValueKey('history-row-B-row6-id')), findsNothing);
    await _historyTap(tester, 'history-date-range');
    await _historyPick(tester, 'from', DateTime(2030, 1, 1));
    await _historyTap(tester, 'history-range-apply');
    expect(find.text('No loaded orders match these filters.'), findsOneWidget);
    expect(find.text('Showing 0 of 0 loaded orders'), findsOneWidget);
    expect(repo.calls.length, 1);
    expect(tester.takeException(), isNull);
  });
}
