import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:pelines_admin_app/features/locations/models/location.dart';
import 'package:pelines_admin_app/features/locations/providers/locations_providers.dart';
import 'package:pelines_admin_app/features/orders/data/orders_repository.dart';
import 'package:pelines_admin_app/features/orders/models/history_filters.dart';
import 'package:pelines_admin_app/features/orders/models/order_models.dart';
import 'package:pelines_admin_app/features/orders/presentation/orders_calendar_screen.dart';
import 'package:pelines_admin_app/features/orders/providers/orders_providers.dart';

void main() {
  test('calendar includes only active statuses', () {
    final List<OrderSummary> result = calendarRelevantOrders(
      OrderStatus.values
          .map((status) => _order(status.name, status: status))
          .toList(),
    );
    expect(result.map((o) => o.status), <OrderStatus>[
      OrderStatus.pending,
      OrderStatus.confirmed,
      OrderStatus.preparing,
      OrderStatus.ready,
    ]);
  });

  test('groups UTC instants by Pacific day and sorts by instant', () {
    final List<OrderSummary> orders = <OrderSummary>[
      _order('later', scheduled: '2026-09-05T07:30:00Z'),
      _order('earlier', scheduled: '2026-09-05T06:30:00Z'),
    ];
    final Map<String, List<OrderSummary>> grouped =
        groupScheduledOrdersByPacificDay(orders);
    expect(grouped['2026-09-04']?.single.orderNumber, 'earlier');
    expect(grouped['2026-09-05']?.single.orderNumber, 'later');
  });

  test('Pacific grouping handles DST and keeps unscheduled separate', () {
    final OrderSummary beforeDst = _order(
      'before-dst',
      scheduled: '2026-03-08T07:30:00Z',
    );
    final OrderSummary afterDst = _order(
      'after-dst',
      scheduled: '2026-03-08T10:30:00Z',
    );
    final OrderSummary unscheduled = _order('needs-time');
    final grouped = groupScheduledOrdersByPacificDay(<OrderSummary>[
      beforeDst,
      afterDst,
      unscheduled,
    ]);
    expect(grouped['2026-03-07']?.single, beforeDst);
    expect(grouped['2026-03-08']?.single, afterDst);
    expect(
      unscheduledCalendarOrders(<OrderSummary>[beforeDst, unscheduled]),
      <OrderSummary>[unscheduled],
    );
  });

  test('history date boundaries use Pacific and filters compose with AND', () {
    final DateTime now = DateTime.parse(
      '2026-09-05T06:30:00Z',
    ); // Sep 4 Pacific
    final List<OrderSummary> loaded = <OrderSummary>[
      _order(
        'match',
        created: '2026-09-04T08:00:00Z',
        type: OrderType.catering,
        fulfillment: FulfillmentType.delivery,
        payment: PaymentStatus.refunded,
      ),
      _order('wrong-type', created: '2026-09-04T08:00:00Z'),
      _order('seven-day-boundary', created: '2026-08-30T06:59:00Z'),
      _order('thirty-day-boundary', created: '2026-08-06T07:00:00Z'),
    ];
    expect(filterHistoricalOrders(loaded, const HistoryFilters()).length, 4);
    expect(
      filterHistoricalOrders(
        loaded,
        const HistoryFilters(
          date: HistoryDateFilter.today,
          orderType: OrderType.catering,
          fulfillment: FulfillmentType.delivery,
          payment: PaymentStatus.refunded,
        ),
        now: now,
      ).map((o) => o.orderNumber),
      <String>['match'],
    );
    expect(
      filterHistoricalOrders(
        loaded,
        const HistoryFilters(date: HistoryDateFilter.last7Days),
        now: now,
      ).map((o) => o.orderNumber),
      contains('seven-day-boundary'),
    );
    expect(
      filterHistoricalOrders(
        loaded,
        const HistoryFilters(date: HistoryDateFilter.last30Days),
        now: now,
      ).map((o) => o.orderNumber),
      contains('thirty-day-boundary'),
    );
    expect(const HistoryFilters().isClear, isTrue);
  });

  test(
    'calendar provider switches location without status query or mixing',
    () async {
      final _Repository repository = _Repository();
      final ProviderContainer container = ProviderContainer(
        overrides: [
          currentLocationProvider.overrideWith(_CurrentLocation.new),
          ordersRepositoryProvider.overrideWithValue(repository),
        ],
      );
      addTearDown(container.dispose);
      final subscription = container.listen(calendarOrdersProvider, (_, _) {});
      addTearDown(subscription.close);
      expect(
        (await container.read(calendarOrdersProvider.future))
            .orders
            .single
            .locationId,
        'A',
      );
      (container.read(currentLocationProvider.notifier) as _CurrentLocation)
          .change(_location('B'));
      await Future<void>.delayed(Duration.zero);
      expect(
        (await container.read(calendarOrdersProvider.future))
            .orders
            .single
            .locationId,
        'B',
      );
      expect(repository.calls, <(String, OrderStatus?)>[
        ('A', null),
        ('B', null),
      ]);
    },
  );

  testWidgets('calendar card opens detail UUID and Back restores calendar', (
    tester,
  ) async {
    final GoRouter router = GoRouter(
      initialLocation: '/app/orders/calendar',
      routes: <RouteBase>[
        GoRoute(
          path: '/app/orders/calendar',
          builder: (_, _) => const OrdersCalendarScreen(),
        ),
        GoRoute(
          path: '/app/orders/:id',
          builder: (_, state) =>
              Scaffold(body: Text('detail ${state.pathParameters['id']}')),
        ),
      ],
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          currentLocationProvider.overrideWith(_CurrentLocation.new),
          ordersRepositoryProvider.overrideWithValue(
            _Repository(scheduled: DateTime.now().toUtc().toIso8601String()),
          ),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('calendar-order'));
    await tester.pumpAndSettle();
    expect(find.text('detail calendar-uuid'), findsOneWidget);
    router.pop();
    await tester.pumpAndSettle();
    expect(find.text('Orders Calendar'), findsOneWidget);
  });
}

OrderSummary _order(
  String number, {
  OrderStatus status = OrderStatus.pending,
  String created = '2026-09-04T08:00:00Z',
  String? scheduled,
  String location = 'A',
  OrderType type = OrderType.online,
  FulfillmentType fulfillment = FulfillmentType.pickup,
  PaymentStatus payment = PaymentStatus.paid,
  String? id,
}) => OrderSummary(
  id: id ?? '$number-id',
  orderNumber: number,
  locationId: location,
  orderType: type,
  status: status,
  rawStatus: status.name,
  paymentStatus: payment,
  fulfillmentType: fulfillment,
  contactName: 'Customer',
  scheduledFor: scheduled == null ? null : DateTime.parse(scheduled),
  createdAt: DateTime.parse(created),
  itemCount: 1,
  totalCents: 1000,
);

Location _location(String id) => Location(
  id: id,
  name: id,
  slug: id,
  isActive: true,
  deliveryFeeCents: 0,
  deliveryMinimumCents: 0,
  isAcceptingOrders: true,
  createdAt: DateTime.utc(2026),
  updatedAt: DateTime.utc(2026),
);

class _CurrentLocation extends CurrentLocationController {
  @override
  Future<Location?> build() async => _location('A');
  void change(Location value) => state = AsyncData<Location?>(value);
}

class _Repository implements OrdersRepository {
  _Repository({this.scheduled});
  final String? scheduled;
  final List<(String, OrderStatus?)> calls = <(String, OrderStatus?)>[];
  @override
  Future<List<OrderSummary>> getOrders({
    required String locationId,
    OrderStatus? status,
  }) async {
    calls.add((locationId, status));
    return <OrderSummary>[
      _order(
        'calendar-order',
        id: 'calendar-uuid',
        location: locationId,
        scheduled: scheduled,
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
