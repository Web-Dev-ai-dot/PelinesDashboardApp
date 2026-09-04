import 'package:flutter/material.dart';
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
    expect(find.text('Cancelled'), findsOneWidget);
    expect(find.text('Paid'), findsOneWidget);
    expect(find.textContaining('Cancelled at'), findsNothing);
    expect(find.byType(FilledButton), findsNothing);
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
}) => OrderSummary(
  id: id ?? '$number-id',
  orderNumber: number,
  locationId: locationId,
  orderType: OrderType.online,
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
  final List<OrderSummary>? custom;
  final List<(String, OrderStatus?)> calls = <(String, OrderStatus?)>[];
  bool fail = false;

  @override
  Future<List<OrderSummary>> getOrders({
    required String locationId,
    OrderStatus? status,
  }) async {
    calls.add((locationId, status));
    if (fail) throw Exception('offline');
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
