import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pelines_admin_app/core/time/pelines_time.dart';
import 'package:pelines_admin_app/features/locations/models/location.dart';
import 'package:pelines_admin_app/features/locations/providers/locations_providers.dart';
import 'package:pelines_admin_app/features/orders/data/orders_repository.dart';
import 'package:pelines_admin_app/features/orders/models/order_models.dart';
import 'package:pelines_admin_app/features/orders/providers/orders_providers.dart';

void main() {
  setUpAll(PelinesTime.initialize);
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
}) => OrderSummary(
  id: '$number-id',
  orderNumber: number,
  locationId: 'location-id',
  orderType: OrderType.online,
  status: status,
  rawStatus: status.name,
  paymentStatus: payment,
  fulfillmentType: FulfillmentType.pickup,
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
  Completer<List<OrderSummary>>? pending;
  final List<String> locationIds = <String>[];
  @override
  Future<List<OrderSummary>> getOrders({
    required String locationId,
    OrderStatus? status,
  }) async {
    locationIds.add(locationId);
    final held = pending;
    pending = null;
    if (held != null) return held.future;
    return <OrderSummary>[];
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
