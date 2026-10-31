import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pelines_admin_app/core/time/pelines_time.dart';
import 'package:pelines_admin_app/features/locations/models/location.dart';
import 'package:pelines_admin_app/features/locations/providers/locations_providers.dart';
import 'package:pelines_admin_app/features/orders/data/orders_repository.dart';
import 'package:pelines_admin_app/features/orders/models/order_models.dart';
import 'package:pelines_admin_app/features/orders/models/orders_date_filter.dart';
import 'package:pelines_admin_app/features/orders/providers/orders_providers.dart';

void main() {
  setUpAll(PelinesTime.initialize);
  test(
    'Picked Up follows Refresh and location without additional queries',
    () async {
      final today = DateTime.now().toUtc().toIso8601String();
      final repository = _RecordingRepository();
      repository.rows['first'] = [
        _order('collected', OrderStatus.delivered, today, locationId: 'first'),
        _order(
          'delivery',
          OrderStatus.delivered,
          today,
          locationId: 'first',
          fulfillment: FulfillmentType.delivery,
        ),
      ];
      repository.rows['second'] = [
        _order(
          'second-pickup',
          OrderStatus.delivered,
          today,
          locationId: 'second',
        ),
      ];
      final container = ProviderContainer(
        overrides: [
          currentLocationProvider.overrideWith(_FakeCurrentLocation.new),
          ordersRepositoryProvider.overrideWithValue(repository),
        ],
      );
      addTearDown(container.dispose);
      final subscription = container.listen(todayOrdersProvider, (_, _) {});
      addTearDown(subscription.close);
      final first = await container.read(todayOrdersProvider.future);
      expect(first.orders, isEmpty);
      expect(
        filterTodayPickedUpOrders(
          first.fullLocationSnapshot!,
          locationId: 'first',
        ).map((o) => o.id),
        ['collected-id'],
      );
      expect(repository.locationIds, ['first']);
      repository.rows['first'] = [];
      await container.read(todayOrdersProvider.notifier).refresh();
      expect(
        container.read(todayOrdersProvider).requireValue.fullLocationSnapshot,
        isEmpty,
      );
      (container.read(currentLocationProvider.notifier) as _FakeCurrentLocation)
          .change(_location('second'));
      final second = await container.read(todayOrdersProvider.future);
      expect(second.snapshotLocationId, 'second');
      expect(
        filterTodayPickedUpOrders(
          second.fullLocationSnapshot!,
          locationId: 'second',
        ).map((o) => o.id),
        ['second-pickup-id'],
      );
      expect(repository.locationIds, ['first', 'first', 'second']);
      expect(repository.statuses, everyElement(isNull));
    },
  );
  test('Upcoming retains one location response for Picked Up, Refresh and location changes', () async {
    final future = DateTime.now()
        .add(const Duration(days: 2))
        .toUtc()
        .toIso8601String();
    final repo = _RecordingRepository();
    repo.rows['first'] = [
      _order('active', OrderStatus.confirmed, future, locationId: 'first'),
      _order('picked', OrderStatus.delivered, future, locationId: 'first'),
      _order(
        'delivery',
        OrderStatus.delivered,
        future,
        locationId: 'first',
        fulfillment: FulfillmentType.delivery,
      ),
      _order('foreign', OrderStatus.delivered, future, locationId: 'second'),
    ];
    repo.rows['second'] = [
      _order('other', OrderStatus.delivered, future, locationId: 'second'),
    ];
    final container = ProviderContainer(
      overrides: [
        currentLocationProvider.overrideWith(_FakeCurrentLocation.new),
        ordersRepositoryProvider.overrideWithValue(repo),
      ],
    );
    addTearDown(container.dispose);
    final sub = container.listen(calendarOrdersProvider, (_, _) {});
    addTearDown(sub.close);
    final first = await container.read(calendarOrdersProvider.future);
    expect(first.orders.map((o) => o.id), ['active-id']);
    expect(first.snapshotLocationId, 'first');
    expect(
      filterPickedUpOrders(
        first.fullLocationSnapshot!,
        locationId: 'first',
        dateFilter: OrdersDateFilter.upcoming,
      ).map((o) => o.id),
      ['picked-id'],
    );
    expect(repo.locationIds, ['first']);
    expect(
      first.refreshing().fullLocationSnapshot,
      same(first.fullLocationSnapshot),
    );
    expect(
      first.failed('offline').fullLocationSnapshot,
      same(first.fullLocationSnapshot),
    );
    repo.rows['first'] = [];
    await container.read(calendarOrdersProvider.notifier).refresh();
    expect(
      container.read(calendarOrdersProvider).requireValue.fullLocationSnapshot,
      isEmpty,
    );
    (container.read(currentLocationProvider.notifier) as _FakeCurrentLocation)
        .change(_location('second'));
    final second = await container.read(calendarOrdersProvider.future);
    expect(second.snapshotLocationId, 'second');
    expect(
      filterPickedUpOrders(
        second.fullLocationSnapshot!,
        locationId: 'second',
        dateFilter: OrdersDateFilter.upcoming,
      ).map((o) => o.id),
      ['other-id'],
    );
    expect(repo.locationIds, ['first', 'first', 'second']);
    expect(repo.statuses, everyElement(isNull));
  });
  test('Upcoming Picked Up shares paid pickup classification and uses future Pacific operational dates', () {
    final now = DateTime.parse('2026-11-01T06:30:00Z'); // Oct 31 Pacific.
    final picked = _order(
      'picked',
      OrderStatus.delivered,
      '2026-11-01T07:30:00Z',
    );
    final rows = [
      picked,
      picked,
      _order('today', OrderStatus.delivered, '2026-11-01T06:45:00Z'),
      _order(
        'delivery',
        OrderStatus.delivered,
        '2026-11-01T07:30:00Z',
        fulfillment: FulfillmentType.delivery,
      ),
      _order(
        'unpaid',
        OrderStatus.delivered,
        '2026-11-01T07:30:00Z',
        payment: PaymentStatus.unpaid,
      ),
      _order(
        'refunded',
        OrderStatus.delivered,
        '2026-11-01T07:30:00Z',
        payment: PaymentStatus.refunded,
      ),
      _order(
        'foreign',
        OrderStatus.delivered,
        '2026-11-01T07:30:00Z',
        locationId: 'other',
      ),
      _order('ready', OrderStatus.ready, '2026-11-01T07:30:00Z'),
    ];
    expect(
      filterPickedUpOrders(
        rows,
        locationId: 'location-id',
        dateFilter: OrdersDateFilter.upcoming,
        now: now,
      ).map((o) => o.id),
      ['picked-id'],
    );
    expect(calendarRelevantOrders(rows).map((o) => o.id), ['ready-id']);
  });

  test('Picked Up uses the existing full snapshot, excludes delivery and deduplicates', () {
    final now = DateTime.parse('2026-09-04T19:00:00Z');
    final picked = _order(
      'picked',
      OrderStatus.delivered,
      '2026-09-04T18:00:00Z',
    );
    final snapshot = [
      picked,
      picked,
      _order(
        'delivery',
        OrderStatus.delivered,
        '2026-09-04T18:00:00Z',
        fulfillment: FulfillmentType.delivery,
      ),
      _order(
        'unknown',
        OrderStatus.delivered,
        '2026-09-04T18:00:00Z',
        fulfillment: FulfillmentType.unknown,
      ),
      _order(
        'foreign',
        OrderStatus.delivered,
        '2026-09-04T18:00:00Z',
        locationId: 'other',
      ),
      _order('yesterday', OrderStatus.delivered, '2026-09-03T18:00:00Z'),
      _order(
        'refunded',
        OrderStatus.delivered,
        '2026-09-04T18:00:00Z',
        payment: PaymentStatus.refunded,
      ),
      _order('ready', OrderStatus.ready, '2026-09-04T18:00:00Z'),
      _order('cancelled', OrderStatus.cancelled, '2026-09-04T18:00:00Z'),
    ];
    final result = filterTodayPickedUpOrders(
      snapshot,
      locationId: 'location-id',
      now: now,
    );
    expect(result.map((o) => o.id), [picked.id]);
    expect(filterTodayActiveOrders(snapshot, now: now).map((o) => o.id), [
      'ready-id',
    ]);
    expect(
      filterTodayPickedUpOrders(
        snapshot,
        locationId: 'other',
        now: now,
      ).map((o) => o.id),
      ['foreign-id'],
    );
  });
  for (final fail in [false, true]) {
    test(
      'late location response cannot replace full snapshot, failure=$fail',
      () async {
        final repository = _RecordingRepository();
        final container = ProviderContainer(
          overrides: [
            currentLocationProvider.overrideWith(_FakeCurrentLocation.new),
            ordersRepositoryProvider.overrideWithValue(repository),
          ],
        );
        addTearDown(container.dispose);
        final subscription = container.listen(todayOrdersProvider, (_, _) {});
        addTearDown(subscription.close);
        await container.read(todayOrdersProvider.future);
        final pending = Completer<List<OrderSummary>>();
        repository.pending = pending;
        final refresh = container.read(todayOrdersProvider.notifier).refresh();
        await Future<void>.delayed(Duration.zero);
        (container.read(
          currentLocationProvider.notifier,
        ) as _FakeCurrentLocation).change(_location('second'));
        await Future<void>.delayed(Duration.zero);
        await container.read(todayOrdersProvider.future);
        if (fail) {
          pending.completeError(Exception('old request failed'));
        } else {
          pending.complete([]);
        }
        await refresh;
        final snapshot = container.read(todayOrdersProvider).requireValue;
        expect(snapshot.snapshotLocationId, 'second');
        expect(snapshot.refreshError, isNull);
      },
    );
  }

  test('Today uses Pacific commercial date across UTC boundary and DST', () {
    final DateTime now = DateTime.parse(
      '2026-07-01T07:30:00Z',
    ); // Jul 1 00:30 PDT
    expect(
      PelinesTime.isToday(DateTime.parse('2026-07-01T06:45:00Z'), now: now),
      isFalse,
    );
    expect(
      PelinesTime.isToday(DateTime.parse('2026-07-01T07:05:00Z'), now: now),
      isTrue,
    );
    expect(
      PelinesTime.inPacific(now).timeZoneOffset,
      const Duration(hours: -7),
    );

    final DateTime winter = DateTime.parse('2026-01-15T20:00:00Z');
    expect(
      PelinesTime.inPacific(winter).timeZoneOffset,
      const Duration(hours: -8),
    );
  });

  test(
    'filters active statuses and excludes delivered, cancelled and other days',
    () {
      final DateTime now = DateTime.parse('2026-09-04T19:00:00Z');
      final List<OrderSummary> result = filterTodayActiveOrders(<OrderSummary>[
        _order('pending', OrderStatus.pending, '2026-09-04T18:00:00Z'),
        _order('delivered', OrderStatus.delivered, '2026-09-04T17:00:00Z'),
        _order('cancelled', OrderStatus.cancelled, '2026-09-04T16:00:00Z'),
        _order('yesterday', OrderStatus.ready, '2026-09-03T16:00:00Z'),
      ], now: now);
      expect(result.map((OrderSummary o) => o.orderNumber), <String>[
        'pending',
      ]);
    },
  );

  test('sorts scheduled orders by timestamp before ASAP orders, stably', () {
    final DateTime now = DateTime.parse('2026-09-04T19:00:00Z');
    final OrderSummary asap = _order(
      'ASAP',
      OrderStatus.pending,
      '2026-09-04T16:00:00Z',
    );
    final OrderSummary later = _order(
      'LATER',
      OrderStatus.ready,
      '2026-09-04T15:00:00Z',
      scheduled: '2026-09-04T20:00:00Z',
    );
    final OrderSummary sooner = _order(
      'SOONER',
      OrderStatus.confirmed,
      '2026-09-04T14:00:00Z',
      scheduled: '2026-09-04T19:30:00Z',
    );
    final List<OrderSummary> result = filterTodayActiveOrders(<OrderSummary>[
      asap,
      later,
      sooner,
    ], now: now);
    expect(result.map((OrderSummary o) => o.orderNumber), <String>[
      'SOONER',
      'LATER',
      'ASAP',
    ]);
  });

  test('only paid active orders enter the operational Today flow', () {
    final DateTime now = DateTime.parse('2026-09-04T19:00:00Z');
    final List<OrderSummary> result = filterTodayActiveOrders(<OrderSummary>[
      _order('pending-paid', OrderStatus.pending, '2026-09-04T18:00:00Z'),
      _order('confirmed-paid', OrderStatus.confirmed, '2026-09-04T18:01:00Z'),
      _order('preparing-paid', OrderStatus.preparing, '2026-09-04T18:02:00Z'),
      _order('ready-paid', OrderStatus.ready, '2026-09-04T18:03:00Z'),
      _order(
        'pending-failed',
        OrderStatus.pending,
        '2026-09-04T18:04:00Z',
        payment: PaymentStatus.failed,
      ),
      _order(
        'pending-unpaid',
        OrderStatus.pending,
        '2026-09-04T18:05:00Z',
        payment: PaymentStatus.unpaid,
      ),
      _order(
        'pending-refunded',
        OrderStatus.pending,
        '2026-09-04T18:06:00Z',
        payment: PaymentStatus.refunded,
      ),
      _order(
        'pending-unknown',
        OrderStatus.pending,
        '2026-09-04T18:07:00Z',
        payment: PaymentStatus.unknown,
      ),
    ], now: now);

    expect(result.map((OrderSummary order) => order.orderNumber), <String>[
      'pending-paid',
      'confirmed-paid',
      'preparing-paid',
      'ready-paid',
    ]);
  });

  test(
    'changing CurrentLocation reloads orders without mixing UUIDs',
    () async {
      final _RecordingRepository repository = _RecordingRepository();
      final ProviderContainer container = ProviderContainer(
        overrides: [
          currentLocationProvider.overrideWith(_FakeCurrentLocation.new),
          ordersRepositoryProvider.overrideWithValue(repository),
        ],
      );
      addTearDown(container.dispose);
      final subscription = container.listen(todayOrdersProvider, (_, _) {});
      addTearDown(subscription.close);

      await container.read(todayOrdersProvider.future);
      final _FakeCurrentLocation current = container.read(
        currentLocationProvider.notifier,
      ) as _FakeCurrentLocation;
      current.change(_location('second'));
      await Future<void>.delayed(Duration.zero);
      await container.read(todayOrdersProvider.future);

      expect(repository.locationIds, <String>['first', 'second']);
    },
  );
}

OrderSummary _order(
  String number,
  OrderStatus status,
  String created, {
  String? scheduled,
  PaymentStatus payment = PaymentStatus.paid,
  FulfillmentType fulfillment = FulfillmentType.pickup,
  String locationId = 'location-id',
}) => OrderSummary(
  id: '$number-id',
  orderNumber: number,
  locationId: locationId,
  orderType: OrderType.online,
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

class _FakeCurrentLocation extends CurrentLocationController {
  @override
  Future<Location?> build() async => _location('first');
  void change(Location location) => state = AsyncData<Location?>(location);
}

class _RecordingRepository implements OrdersRepository {
  final rows = <String, List<OrderSummary>>{};
  final statuses = <OrderStatus?>[];
  Completer<List<OrderSummary>>? pending;
  final List<String> locationIds = <String>[];
  @override
  Future<List<OrderSummary>> getOrders({
    required String locationId,
    OrderStatus? status,
  }) async {
    locationIds.add(locationId);
    statuses.add(status);
    final held = pending;
    pending = null;
    if (held != null) return held.future;
    return rows[locationId] ?? <OrderSummary>[];
  }

  @override
  Future<OrderDetail> getOrderById(String id) => throw UnimplementedError();

  @override
  Future<OrderDetail> updateOrderStatus({
    required String orderId,
    required OrderStatus status,
  }) => throw UnimplementedError();

  @override
  Future<OrderDetail> updateInternalNotes({
    required String orderId,
    required String internalNotes,
  }) => throw UnimplementedError();
}
