import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:pelines_admin_app/features/auth/models/admin_session.dart';
import 'package:pelines_admin_app/features/auth/providers/auth_controller.dart';
import 'package:pelines_admin_app/features/auth/providers/auth_providers.dart';
import 'package:pelines_admin_app/features/locations/models/location.dart';
import 'package:pelines_admin_app/features/locations/providers/locations_providers.dart';
import 'package:pelines_admin_app/features/orders/data/order_alert_sound.dart';
import 'package:pelines_admin_app/features/orders/data/order_alert_store.dart';
import 'package:pelines_admin_app/features/orders/models/order_models.dart';
import 'package:pelines_admin_app/features/orders/presentation/order_alert_shell.dart';
import 'package:pelines_admin_app/features/orders/providers/order_alerts_controller.dart';
import 'package:pelines_admin_app/features/orders/providers/orders_providers.dart';

import 'order_test_data.dart';

void main() {
  test('persisted legacy JSON loads as version zero and writes full snapshot version', () async {
    SharedPreferences.setMockInitialValues({
      'pelines.order_alerts.a': '{"known":["A"],"unseen":["A"]}',
    });
    final store = SharedPreferencesOrderAlertStore();
    final legacy = (await store.read('a'))!;
    expect(legacy.version, 0);
    await store.write(
      'a',
      StoredOrderAlerts(
        knownIds: legacy.knownIds,
        unseenIds: legacy.unseenIds,
        version: StoredOrderAlerts.fullSnapshotVersion,
      ),
    );
    final updated = (await store.read('a'))!;
    expect(updated.version, 1);
    expect(updated.unseenIds, ['A']);
  });
  test(
    'legacy baseline preserves unseen and does not flood expanded snapshot',
    () async {
      final store = _MemoryStore()
        ..values['a'] = const StoredOrderAlerts(
          knownIds: ['old'],
          unseenIds: ['old'],
        );
      final sound = _FakeSound();
      final container = _container(store, sound);
      addTearDown(container.dispose);
      await container.read(orderAlertsProvider.future);
      final controller = container.read(orderAlertsProvider.notifier);
      await controller.processSnapshot(
        locationId: 'a',
        orders: [_order('old'), _order('future')],
        mayPlaySound: true,
      );
      expect(container.read(orderAlertsProvider).requireValue.unseenIds, [
        'old',
      ]);
      expect(store.values['a']!.version, StoredOrderAlerts.fullSnapshotVersion);
      expect(sound.playCalls, 0);
      await controller.processSnapshot(
        locationId: 'a',
        orders: [_order('old'), _order('future'), _order('new')],
        mayPlaySound: true,
      );
      expect(container.read(orderAlertsProvider).requireValue.unseenIds, [
        'old',
        'new',
      ]);
      expect(sound.playCalls, 1);
    },
  );

  test(
    'more than 200 active IDs do not re-alert after acknowledge and restart',
    () async {
      final store = _MemoryStore();
      final sound = _FakeSound();
      final container = _container(store, sound);
      await container.read(orderAlertsProvider.future);
      final controller = container.read(orderAlertsProvider.notifier);
      await controller.processSnapshot(
        locationId: 'a',
        orders: [],
        mayPlaySound: true,
      );
      final orders = List.generate(205, (i) => _order('$i'));
      await controller.processSnapshot(
        locationId: 'a',
        orders: orders,
        mayPlaySound: true,
      );
      expect(container.read(orderAlertsProvider).requireValue.unseenCount, 205);
      await controller.acknowledge('0');
      container.dispose();
      final restarted = _container(store, sound);
      addTearDown(restarted.dispose);
      await restarted.read(orderAlertsProvider.future);
      await restarted
          .read(orderAlertsProvider.notifier)
          .processSnapshot(locationId: 'a', orders: orders, mayPlaySound: true);
      expect(restarted.read(orderAlertsProvider).requireValue.unseenCount, 204);
      expect(
        restarted.read(orderAlertsProvider).requireValue.unseenIds,
        isNot(contains('0')),
      );
      expect(sound.playCalls, 1);
    },
  );

  test('first load seeds without sound and later pending/confirmed alert once per batch', () async {
    final _MemoryStore store = _MemoryStore();
    final _FakeSound sound = _FakeSound();
    final ProviderContainer container = _container(store, sound);
    addTearDown(container.dispose);
    await container.read(orderAlertsProvider.future);
    final OrderAlertsController controller = container.read(
      orderAlertsProvider.notifier,
    );

    await controller.processSnapshot(
      locationId: 'a',
      orders: <OrderSummary>[_order('A')],
      mayPlaySound: true,
    );
    expect(container.read(orderAlertsProvider).value!.unseenCount, 0);
    expect(sound.playCalls, 0);

    await controller.processSnapshot(
      locationId: 'a',
      orders: <OrderSummary>[
        _order('A'),
        _order('B', status: OrderStatus.confirmed),
        _order('C'),
        _order('D'),
      ],
      mayPlaySound: true,
    );
    expect(container.read(orderAlertsProvider).value!.unseenIds, <String>[
      'B',
      'C',
      'D',
    ]);
    expect(sound.playCalls, 1);

    await controller.processSnapshot(
      locationId: 'a',
      orders: <OrderSummary>[
        _order('A'),
        _order('B', status: OrderStatus.confirmed),
        _order('C'),
        _order('D'),
      ],
      mayPlaySound: true,
    );
    expect(sound.playCalls, 1);
  });

  test('noneligible orders never become unseen or play sound', () async {
    final _MemoryStore store = _MemoryStore();
    final _FakeSound sound = _FakeSound();
    final ProviderContainer container = _container(store, sound);
    addTearDown(container.dispose);
    await container.read(orderAlertsProvider.future);
    final OrderAlertsController controller = container.read(
      orderAlertsProvider.notifier,
    );
    await controller.processSnapshot(
      locationId: 'a',
      orders: <OrderSummary>[_order('seed')],
      mayPlaySound: true,
    );
    await controller.processSnapshot(
      locationId: 'a',
      orders: <OrderSummary>[
        _order('failed', payment: PaymentStatus.failed),
        _order('unpaid', payment: PaymentStatus.unpaid),
        _order('refunded', payment: PaymentStatus.refunded),
        _order('cancelled', status: OrderStatus.cancelled),
        _order('delivered', status: OrderStatus.delivered),
      ],
      mayPlaySound: true,
    );
    expect(container.read(orderAlertsProvider).value!.unseenIds, isEmpty);
    expect(sound.playCalls, 0);
  });

  test(
    'acknowledgement persists and stale unseen orders are removed',
    () async {
      final _MemoryStore store = _MemoryStore();
      final _FakeSound sound = _FakeSound();
      final ProviderContainer container = _container(store, sound);
      await container.read(orderAlertsProvider.future);
      final OrderAlertsController controller = container.read(
        orderAlertsProvider.notifier,
      );
      await controller.processSnapshot(
        locationId: 'a',
        orders: <OrderSummary>[_order('A')],
        mayPlaySound: true,
      );
      await controller.processSnapshot(
        locationId: 'a',
        orders: <OrderSummary>[_order('A'), _order('B'), _order('C')],
        mayPlaySound: true,
      );
      await controller.acknowledge('B');
      expect(container.read(orderAlertsProvider).value!.unseenIds, <String>[
        'C',
      ]);
      container.dispose();

      final _FakeSound restartedSound = _FakeSound();
      final ProviderContainer restarted = _container(store, restartedSound);
      addTearDown(restarted.dispose);
      await restarted.read(orderAlertsProvider.future);
      await restarted
          .read(orderAlertsProvider.notifier)
          .processSnapshot(
            locationId: 'a',
            orders: <OrderSummary>[_order('A'), _order('B'), _order('C')],
            mayPlaySound: true,
          );
      expect(restarted.read(orderAlertsProvider).value!.unseenIds, <String>[
        'C',
      ]);
      expect(restartedSound.playCalls, 0);

      await restarted
          .read(orderAlertsProvider.notifier)
          .processSnapshot(
            locationId: 'a',
            orders: <OrderSummary>[_order('A'), _order('B')],
            mayPlaySound: true,
          );
      expect(restarted.read(orderAlertsProvider).value!.unseenIds, isEmpty);
    },
  );

  test(
    'locations seed independently and returning does not alert backlog',
    () async {
      final _MemoryStore store = _MemoryStore();
      final _FakeSound sound = _FakeSound();
      final ProviderContainer container = _container(store, sound);
      addTearDown(container.dispose);
      await container.read(orderAlertsProvider.future);
      final OrderAlertsController controller = container.read(
        orderAlertsProvider.notifier,
      );
      await controller.processSnapshot(
        locationId: 'a',
        orders: <OrderSummary>[_order('A1')],
        mayPlaySound: true,
      );
      await controller.processSnapshot(
        locationId: 'b',
        orders: <OrderSummary>[
          _order('B1', location: 'b'),
          _order('B2', location: 'b'),
        ],
        mayPlaySound: true,
      );
      expect(sound.playCalls, 0);
      await controller.processSnapshot(
        locationId: 'b',
        orders: <OrderSummary>[
          _order('B1', location: 'b'),
          _order('B2', location: 'b'),
          _order('B3', location: 'b'),
        ],
        mayPlaySound: true,
      );
      expect(sound.playCalls, 1);
      await controller.processSnapshot(
        locationId: 'a',
        orders: <OrderSummary>[_order('A1')],
        mayPlaySound: true,
      );
      expect(sound.playCalls, 1);
    },
  );

  test('background detection tracks unseen without playing audio', () async {
    final _MemoryStore store = _MemoryStore();
    final _FakeSound sound = _FakeSound();
    final ProviderContainer container = _container(store, sound);
    addTearDown(container.dispose);
    await container.read(orderAlertsProvider.future);
    final OrderAlertsController controller = container.read(
      orderAlertsProvider.notifier,
    );
    await controller.processSnapshot(
      locationId: 'a',
      orders: <OrderSummary>[_order('A')],
      mayPlaySound: false,
    );
    await controller.processSnapshot(
      locationId: 'a',
      orders: <OrderSummary>[_order('A'), _order('B')],
      mayPlaySound: false,
    );
    expect(container.read(orderAlertsProvider).value!.unseenIds, <String>['B']);
    expect(sound.playCalls, 0);
  });

  testWidgets(
    'fullscreen shows queue without auto acknowledgement and clears explicitly',
    (WidgetTester tester) async {
      final _MemoryStore store = _MemoryStore()
        ..values['a'] = const StoredOrderAlerts(
          knownIds: <String>['A', 'B', 'C'],
          unseenIds: <String>['B', 'C'],
        );
      final GoRouter router = GoRouter(
        initialLocation: '/app/promotions',
        routes: <RouteBase>[
          ShellRoute(
            builder: (_, _, Widget child) => OrderAlertShell(child: child),
            routes: <RouteBase>[
              GoRoute(
                path: '/app/promotions',
                builder: (_, _) => const Scaffold(body: Text('Promotions')),
              ),
              GoRoute(
                path: '/app/orders/:id',
                builder: (_, GoRouterState state) =>
                    _AcknowledgingDetail(orderId: state.pathParameters['id']!),
              ),
            ],
          ),
        ],
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            orderAlertStoreProvider.overrideWithValue(store),
            orderAlertSoundProvider.overrideWithValue(_FakeSound()),
            authControllerProvider.overrideWith(_FakeAuth.new),
            currentLocationProvider.overrideWith(_FakeLocation.new),
            todayOrdersProvider.overrideWith(_FakeToday.new),
            orderDetailProvider.overrideWith(
              (ref, id) async => orderDetail(
                id: id,
                locationId: 'a',
                status: OrderStatus.confirmed,
              ),
            ),
          ],
          child: MaterialApp.router(routerConfig: router),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('new-order-fullscreen')), findsOneWidget);
      expect(find.text('1 of 2'), findsOneWidget);
      final context = tester.element(
        find.byKey(const Key('new-order-fullscreen')),
      );
      final container = ProviderScope.containerOf(context);
      expect(container.read(orderAlertsProvider).value!.unseenIds, ['B', 'C']);
      await tester.tap(find.byKey(const Key('alert-acknowledge')));
      await tester.pumpAndSettle();
      expect(find.text('1 of 1'), findsOneWidget);
      expect(container.read(orderAlertsProvider).value!.unseenIds, ['C']);
      await tester.tap(find.byKey(const Key('alert-acknowledge')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('new-order-fullscreen')), findsNothing);
      expect(find.text('Promotions'), findsOneWidget);
    },
  );
}

ProviderContainer _container(_MemoryStore store, _FakeSound sound) =>
    ProviderContainer(
      overrides: [
        orderAlertStoreProvider.overrideWithValue(store),
        orderAlertSoundProvider.overrideWithValue(sound),
      ],
    );

OrderSummary _order(
  String id, {
  OrderStatus status = OrderStatus.pending,
  PaymentStatus payment = PaymentStatus.paid,
  String location = 'a',
}) => OrderSummary(
  id: id,
  orderNumber: id,
  locationId: location,
  orderType: OrderType.online,
  status: status,
  rawStatus: status.name,
  paymentStatus: payment,
  fulfillmentType: FulfillmentType.pickup,
  contactName: 'Customer',
  createdAt: DateTime.utc(2026),
  itemCount: 1,
  totalCents: 1000,
);

class _MemoryStore implements OrderAlertStore {
  final Map<String, StoredOrderAlerts> values = <String, StoredOrderAlerts>{};

  @override
  Future<StoredOrderAlerts?> read(String locationId) async =>
      values[locationId];

  @override
  Future<void> write(String locationId, StoredOrderAlerts alerts) async {
    values[locationId] = alerts;
  }
}

class _FakeSound implements OrderAlertSound {
  int playCalls = 0;
  @override
  Future<void> play() async => playCalls++;
  @override
  Future<void> dispose() async {}
}

class _FakeAuth extends AuthController {
  @override
  Future<AdminSession?> build() async => null;
}

class _FakeLocation extends CurrentLocationController {
  @override
  Future<Location?> build() async => Location(
    id: 'a',
    name: 'Location A',
    slug: 'location-a',
    isActive: true,
    deliveryFeeCents: 0,
    deliveryMinimumCents: 0,
    isAcceptingOrders: true,
    createdAt: DateTime.utc(2026),
    updatedAt: DateTime.utc(2026),
  );
}

class _FakeToday extends TodayOrdersController {
  @override
  Future<TodayOrdersState> build() async => TodayOrdersState(
    orders: <OrderSummary>[_order('A'), _order('B'), _order('C')],
    snapshotLocationId: 'a',
    fullLocationSnapshot: [_order('A'), _order('B'), _order('C')],
  );

  @override
  Future<void> refresh() async {}
}

class _AcknowledgingDetail extends ConsumerWidget {
  const _AcknowledgingDetail({required this.orderId});
  final String orderId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(orderAlertsProvider.notifier).acknowledge(orderId);
    });
    return Scaffold(body: Center(child: Text('Order $orderId')));
  }
}
